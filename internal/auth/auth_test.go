package auth

import (
	"bytes"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestPasswordRoundTripAndPepper(t *testing.T) {
	pepper := []byte("test-pepper")
	hash, err := HashPassword("correct horse battery staple", pepper)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(hash, "$argon2id$v=19$pv=1,h=hmac-sha256,") {
		t.Fatalf("unexpected PHC string: %q", hash)
	}

	valid, err := VerifyPassword("correct horse battery staple", pepper, hash)
	if err != nil || !valid {
		t.Fatalf("VerifyPassword() = %v, %v", valid, err)
	}
	valid, err = VerifyPassword("wrong", pepper, hash)
	if err != nil || valid {
		t.Fatalf("wrong password = %v, %v", valid, err)
	}
	valid, err = VerifyPassword("correct horse battery staple", []byte("wrong-pepper"), hash)
	if err != nil || valid {
		t.Fatalf("wrong pepper = %v, %v", valid, err)
	}
}

func TestPasswordRejectsOldOrMalformedFormat(t *testing.T) {
	valid, err := VerifyPassword("password", []byte("pepper"), "$argon2id$v=19$m=65536,t=3,p=1$c2FsdHNhbHRzYWx0c2FsdA$YWJjZGVmZ2hpamtsbW5vcA")
	if valid || !errors.Is(err, ErrInvalidPasswordHash) {
		t.Fatalf("VerifyPassword() = %v, %v", valid, err)
	}
}

func TestSessionCookieExpiryAndLogout(t *testing.T) {
	now := time.Date(2026, 8, 5, 12, 0, 0, 0, time.UTC)
	store := NewStore(Config{
		Now:    func() time.Time { return now },
		Random: bytes.NewReader(make([]byte, 64)),
		Cookie: DefaultCookieConfig(),
	})

	recorder := httptest.NewRecorder()
	session, err := store.StartSession(recorder, "user-1")
	if err != nil {
		t.Fatal(err)
	}
	if session.ExpiresAt.Sub(session.CreatedAt) != SessionLifetime {
		t.Fatalf("session lifetime = %s", session.ExpiresAt.Sub(session.CreatedAt))
	}
	cookie := recorder.Result().Cookies()[0]
	if !cookie.Secure || !cookie.HttpOnly || cookie.SameSite != http.SameSiteLaxMode {
		t.Fatalf("insecure session cookie: %#v", cookie)
	}

	request := httptest.NewRequest(http.MethodGet, "/", nil)
	request.AddCookie(cookie)
	got, ok := store.SessionFromRequest(request)
	if !ok || got.UserID != "user-1" {
		t.Fatalf("SessionFromRequest() = %#v, %v", got, ok)
	}

	logoutRecorder := httptest.NewRecorder()
	store.Logout(logoutRecorder, request)
	if _, ok := store.SessionFromRequest(request); ok {
		t.Fatal("logout retained the server session")
	}
	if logoutRecorder.Result().Cookies()[0].MaxAge != -1 {
		t.Fatal("logout did not expire the cookie")
	}

	now = now.Add(SessionLifetime)
	if _, ok := store.GetSession(cookie.Value); ok {
		t.Fatal("session survived its expiry boundary")
	}
}

func TestFailureLimitUsesInjectedClock(t *testing.T) {
	now := time.Date(2026, 8, 5, 12, 0, 0, 0, time.UTC)
	store := NewStore(Config{Now: func() time.Time { return now }})

	for attempt := 1; attempt <= FailureLimit; attempt++ {
		if !store.AllowAttempt("client") {
			t.Fatalf("attempt %d blocked before recording", attempt)
		}
		blocked := store.RecordFailure("client")
		if blocked != (attempt == FailureLimit) {
			t.Fatalf("attempt %d blocked = %v", attempt, blocked)
		}
	}
	if store.AllowAttempt("client") {
		t.Fatal("sixth attempt was allowed")
	}

	now = now.Add(FailureWindow)
	if !store.AllowAttempt("client") {
		t.Fatal("client remained blocked after the failure window")
	}

	store.RecordFailure("client")
	store.ClearFailures("client")
	if !store.AllowAttempt("client") {
		t.Fatal("cleared failures still blocked the client")
	}
}

func TestChallengeLimitUsesInjectedClock(t *testing.T) {
	now := time.Date(2026, time.January, 1, 0, 0, 0, 0, time.UTC)
	store := NewStore(Config{Now: func() time.Time { return now }})
	for attempt := 0; attempt < ChallengeLimit; attempt++ {
		if !store.AllowChallenge("client") {
			t.Fatalf("challenge %d was blocked", attempt+1)
		}
	}
	if store.AllowChallenge("client") {
		t.Fatal("challenge limit did not block the client")
	}
	now = now.Add(ChallengeWindow)
	if !store.AllowChallenge("client") {
		t.Fatal("challenge limit did not expire")
	}
}

func TestStoreSupportsConcurrentAccess(t *testing.T) {
	now := time.Date(2026, 8, 5, 12, 0, 0, 0, time.UTC)
	store := NewStore(Config{Now: func() time.Time { return now }})
	var wait sync.WaitGroup

	for worker := 0; worker < 20; worker++ {
		wait.Add(1)
		go func() {
			defer wait.Done()
			token, _, err := store.CreateSession("user")
			if err != nil {
				t.Errorf("CreateSession(): %v", err)
				return
			}
			if _, ok := store.GetSession(token); !ok {
				t.Error("created session was not found")
			}
			store.RecordFailure("client")
			store.AllowAttempt("client")
			store.DeleteSession(token)
		}()
	}
	wait.Wait()
}
