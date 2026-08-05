package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"io"
	"net/http"
	"sync"
	"time"
)

const (
	SessionLifetime = 24 * time.Hour
	FailureWindow   = 30 * time.Second
	FailureLimit    = 5
	ChallengeWindow = time.Minute
	ChallengeLimit  = 10
	maxChallengeIPs = 1024
)

type Clock func() time.Time

type CookieConfig struct {
	Name     string
	Path     string
	Domain   string
	Secure   bool
	HTTPOnly bool
	SameSite http.SameSite
}

func DefaultCookieConfig() CookieConfig {
	return CookieConfig{
		Name:     "session",
		Path:     "/",
		Secure:   true,
		HTTPOnly: true,
		SameSite: http.SameSiteLaxMode,
	}
}

type Config struct {
	Now    Clock
	Random io.Reader
	Cookie CookieConfig
}

type Session struct {
	UserID    string
	CreatedAt time.Time
	ExpiresAt time.Time
}

type Store struct {
	mu         sync.Mutex
	now        Clock
	random     io.Reader
	cookie     CookieConfig
	sessions   map[[sha256.Size]byte]Session
	failures   map[string][]time.Time
	challenges map[string][]time.Time
}

func NewStore(config Config) *Store {
	now := config.Now
	if now == nil {
		now = time.Now
	}
	random := config.Random
	if random == nil {
		random = rand.Reader
	}
	cookie := config.Cookie
	if cookie == (CookieConfig{}) {
		cookie = DefaultCookieConfig()
	}
	if cookie.Name == "" {
		cookie.Name = "session"
	}
	if cookie.Path == "" {
		cookie.Path = "/"
	}

	return &Store{
		now:        now,
		random:     random,
		cookie:     cookie,
		sessions:   make(map[[sha256.Size]byte]Session),
		failures:   make(map[string][]time.Time),
		challenges: make(map[string][]time.Time),
	}
}

// CreateSession creates an opaque bearer token with a fixed 24-hour lifetime.
func (s *Store) CreateSession(userID string) (string, Session, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	tokenBytes := make([]byte, 32)
	if _, err := io.ReadFull(s.random, tokenBytes); err != nil {
		return "", Session{}, fmt.Errorf("auth: generate session token: %w", err)
	}
	token := base64.RawURLEncoding.EncodeToString(tokenBytes)
	key := sha256.Sum256([]byte(token))
	now := s.now()
	session := Session{UserID: userID, CreatedAt: now, ExpiresAt: now.Add(SessionLifetime)}

	for storedKey, stored := range s.sessions {
		if !now.Before(stored.ExpiresAt) {
			delete(s.sessions, storedKey)
		}
	}
	if _, exists := s.sessions[key]; exists {
		return "", Session{}, fmt.Errorf("auth: duplicate session token")
	}
	s.sessions[key] = session
	return token, session, nil
}

func (s *Store) GetSession(token string) (Session, bool) {
	key := sha256.Sum256([]byte(token))
	now := s.now()

	s.mu.Lock()
	defer s.mu.Unlock()
	session, exists := s.sessions[key]
	if !exists {
		return Session{}, false
	}
	if !now.Before(session.ExpiresAt) {
		delete(s.sessions, key)
		return Session{}, false
	}
	return session, true
}

func (s *Store) DeleteSession(token string) {
	key := sha256.Sum256([]byte(token))
	s.mu.Lock()
	delete(s.sessions, key)
	s.mu.Unlock()
}

// StartSession creates the server session and writes its bearer token as a cookie.
func (s *Store) StartSession(w http.ResponseWriter, userID string) (Session, error) {
	token, session, err := s.CreateSession(userID)
	if err != nil {
		return Session{}, err
	}
	http.SetCookie(w, s.sessionCookie(token, session.ExpiresAt, 0))
	return session, nil
}

func (s *Store) SessionFromRequest(r *http.Request) (Session, bool) {
	cookie, err := r.Cookie(s.cookie.Name)
	if err != nil {
		return Session{}, false
	}
	return s.GetSession(cookie.Value)
}

// Logout removes the server session and expires the client cookie.
func (s *Store) Logout(w http.ResponseWriter, r *http.Request) {
	if cookie, err := r.Cookie(s.cookie.Name); err == nil {
		s.DeleteSession(cookie.Value)
	}
	http.SetCookie(w, s.sessionCookie("", time.Unix(1, 0), -1))
}

// AllowAttempt reports whether the key has fewer than five recent failures.
func (s *Store) AllowAttempt(key string) bool {
	now := s.now()
	s.mu.Lock()
	defer s.mu.Unlock()
	recent := pruneFailures(s.failures[key], now)
	if len(recent) == 0 {
		delete(s.failures, key)
	} else {
		s.failures[key] = recent
	}
	return len(recent) < FailureLimit
}

// AllowChallenge applies a bounded per-client rate limit and records the request.
func (s *Store) AllowChallenge(key string) bool {
	now := s.now()
	s.mu.Lock()
	defer s.mu.Unlock()
	recent := pruneTimes(s.challenges[key], now, ChallengeWindow)
	if len(recent) >= ChallengeLimit {
		s.challenges[key] = recent
		return false
	}
	if len(recent) == 0 && len(s.challenges) >= maxChallengeIPs {
		for storedKey, attempts := range s.challenges {
			attempts = pruneTimes(attempts, now, ChallengeWindow)
			if len(attempts) == 0 {
				delete(s.challenges, storedKey)
			} else {
				s.challenges[storedKey] = attempts
			}
		}
		if len(s.challenges) >= maxChallengeIPs {
			return false
		}
	}
	s.challenges[key] = append(recent, now)
	return true
}

// RecordFailure records one failure and reports whether the key is now blocked.
func (s *Store) RecordFailure(key string) bool {
	now := s.now()
	s.mu.Lock()
	defer s.mu.Unlock()
	recent := pruneFailures(s.failures[key], now)
	if len(recent) >= FailureLimit {
		s.failures[key] = recent
		return true
	}
	recent = append(recent, now)
	s.failures[key] = recent
	return len(recent) >= FailureLimit
}

func (s *Store) ClearFailures(key string) {
	s.mu.Lock()
	delete(s.failures, key)
	s.mu.Unlock()
}

func (s *Store) sessionCookie(value string, expires time.Time, maxAge int) *http.Cookie {
	return &http.Cookie{
		Name:     s.cookie.Name,
		Value:    value,
		Path:     s.cookie.Path,
		Domain:   s.cookie.Domain,
		Expires:  expires,
		MaxAge:   maxAge,
		Secure:   s.cookie.Secure,
		HttpOnly: s.cookie.HTTPOnly,
		SameSite: s.cookie.SameSite,
	}
}

func pruneFailures(failures []time.Time, now time.Time) []time.Time {
	return pruneTimes(failures, now, FailureWindow)
}

func pruneTimes(values []time.Time, now time.Time, window time.Duration) []time.Time {
	firstRecent := 0
	for firstRecent < len(values) && !now.Before(values[firstRecent].Add(window)) {
		firstRecent++
	}
	return values[firstRecent:]
}
