package auth

import (
	"bytes"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/go-webauthn/webauthn/protocol"
	"github.com/go-webauthn/webauthn/protocol/webauthncbor"
	"github.com/go-webauthn/webauthn/protocol/webauthncose"
	"github.com/go-webauthn/webauthn/webauthn"
)

const PasskeyCeremonyLifetime = 5 * time.Minute

const (
	maxPasskeyLoginBody  = 1 << 20
	maxPasskeyCeremonies = 256
)

type PasskeyConfig struct {
	CredentialsFile  string
	RPID             string
	RPDisplayName    string
	RPOrigins        []string
	AdminName        string
	AdminDisplayName string
	Now              Clock
	Random           io.Reader
}

type Passkey struct {
	ID         string              `json:"id"`
	Label      string              `json:"label"`
	Credential webauthn.Credential `json:"credential"`
	FlagsKnown bool                `json:"flags_known"`
}

type PasskeyStore struct {
	mu       sync.Mutex
	path     string
	now      Clock
	random   io.Reader
	webAuthn *webauthn.WebAuthn
	user     passkeyUser
	sessions map[[sha256.Size]byte]passkeyCeremony
}

type passkeyUser struct {
	handle      []byte
	name        string
	displayName string
	passkeys    []Passkey
}

func (u passkeyUser) WebAuthnID() []byte          { return u.handle }
func (u passkeyUser) WebAuthnName() string        { return u.name }
func (u passkeyUser) WebAuthnDisplayName() string { return u.displayName }
func (u passkeyUser) WebAuthnCredentials() []webauthn.Credential {
	credentials := make([]webauthn.Credential, len(u.passkeys))
	for i := range u.passkeys {
		credentials[i] = u.passkeys[i].Credential
	}
	return credentials
}

type ceremonyKind uint8

const (
	registrationCeremony ceremonyKind = iota + 1
	loginCeremony
)

type passkeyCeremony struct {
	kind      ceremonyKind
	label     string
	session   webauthn.SessionData
	expiresAt time.Time
}

type passkeyFileV3 struct {
	Version     int       `json:"version"`
	UserHandle  []byte    `json:"user_handle"`
	Credentials []Passkey `json:"credentials"`
}

// NewPasskeyStore loads credentials and creates a stable admin handle when needed.
func NewPasskeyStore(config PasskeyConfig) (*PasskeyStore, error) {
	if config.CredentialsFile == "" {
		return nil, errors.New("auth: WebAuthn credentials file is empty")
	}
	if config.RPID == "" || config.RPDisplayName == "" || len(config.RPOrigins) == 0 {
		return nil, errors.New("auth: WebAuthn RP ID, display name, and origins are required")
	}
	for _, origin := range config.RPOrigins {
		if origin == "" {
			return nil, errors.New("auth: WebAuthn origin is empty")
		}
	}

	now := config.Now
	if now == nil {
		now = time.Now
	}
	random := config.Random
	if random == nil {
		random = rand.Reader
	}
	name := config.AdminName
	if name == "" {
		name = "admin"
	}
	displayName := config.AdminDisplayName
	if displayName == "" {
		displayName = "Administrator"
	}

	wa, err := webauthn.New(&webauthn.Config{
		RPID:          config.RPID,
		RPDisplayName: config.RPDisplayName,
		RPOrigins:     append([]string(nil), config.RPOrigins...),
		AuthenticatorSelection: protocol.AuthenticatorSelection{
			ResidentKey:      protocol.ResidentKeyRequirementRequired,
			UserVerification: protocol.VerificationRequired,
		},
	})
	if err != nil {
		return nil, fmt.Errorf("auth: configure WebAuthn: %w", err)
	}

	store := &PasskeyStore{
		path:     config.CredentialsFile,
		now:      now,
		random:   random,
		webAuthn: wa,
		user: passkeyUser{
			name:        name,
			displayName: displayName,
		},
		sessions: make(map[[sha256.Size]byte]passkeyCeremony),
	}
	migrated, err := store.load()
	if err != nil {
		return nil, err
	}
	if len(store.user.handle) == 0 {
		store.user.handle = make([]byte, 32)
		if _, err = io.ReadFull(store.random, store.user.handle); err != nil {
			return nil, fmt.Errorf("auth: generate WebAuthn user handle: %w", err)
		}
		migrated = true
	}
	if migrated {
		if err = store.saveLocked(); err != nil {
			return nil, err
		}
	}
	return store, nil
}

// BeginRegistration creates browser options and an opaque ceremony token.
func (s *PasskeyStore) BeginRegistration(label string) (*protocol.CredentialCreation, string, error) {
	label = strings.TrimSpace(label)
	if label == "" {
		return nil, "", errors.New("auth: passkey label is empty")
	}

	s.mu.Lock()
	user := clonePasskeyUser(s.user)
	s.mu.Unlock()
	creation, session, err := s.webAuthn.BeginRegistration(
		user,
		webauthn.WithResidentKeyRequirement(protocol.ResidentKeyRequirementRequired),
		webauthn.WithAuthenticatorSelection(protocol.AuthenticatorSelection{
			ResidentKey:      protocol.ResidentKeyRequirementRequired,
			UserVerification: protocol.VerificationRequired,
		}),
	)
	if err != nil {
		return nil, "", fmt.Errorf("auth: begin passkey registration: %w", err)
	}
	token, err := s.storeCeremony(registrationCeremony, label, *session)
	if err != nil {
		return nil, "", err
	}
	return creation, token, nil
}

// FinishRegistration validates a registration response and persists the credential.
func (s *PasskeyStore) FinishRegistration(token string, request *http.Request) (Passkey, error) {
	ceremony, err := s.takeCeremony(token, registrationCeremony)
	if err != nil {
		return Passkey{}, err
	}

	s.mu.Lock()
	user := clonePasskeyUser(s.user)
	s.mu.Unlock()
	credential, err := s.webAuthn.FinishRegistration(user, ceremony.session, request)
	if err != nil {
		return Passkey{}, fmt.Errorf("auth: finish passkey registration: %w", err)
	}
	passkey := Passkey{
		ID:         base64.RawURLEncoding.EncodeToString(credential.ID),
		Label:      ceremony.label,
		Credential: *credential,
		FlagsKnown: true,
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	for _, existing := range s.user.passkeys {
		if existing.ID == passkey.ID || bytes.Equal(existing.Credential.ID, credential.ID) {
			return Passkey{}, errors.New("auth: passkey credential already exists")
		}
	}
	s.user.passkeys = append(s.user.passkeys, passkey)
	if err = s.saveLocked(); err != nil {
		s.user.passkeys = s.user.passkeys[:len(s.user.passkeys)-1]
		return Passkey{}, err
	}
	return clonePasskey(passkey), nil
}

// BeginDiscoverableLogin creates passkey assertion options without an allow list.
func (s *PasskeyStore) BeginDiscoverableLogin() (*protocol.CredentialAssertion, string, error) {
	assertion, session, err := s.webAuthn.BeginDiscoverableLogin(
		webauthn.WithUserVerification(protocol.VerificationRequired),
	)
	if err != nil {
		return nil, "", fmt.Errorf("auth: begin passkey login: %w", err)
	}
	token, err := s.storeCeremony(loginCeremony, "", *session)
	if err != nil {
		return nil, "", err
	}
	return assertion, token, nil
}

// FinishPasskeyLogin validates an assertion and persists its updated credential state.
func (s *PasskeyStore) FinishPasskeyLogin(token string, request *http.Request) (Passkey, error) {
	ceremony, err := s.takeCeremony(token, loginCeremony)
	if err != nil {
		return Passkey{}, err
	}

	if request == nil || request.Body == nil {
		return Passkey{}, errors.New("auth: passkey login request body is missing")
	}
	body, err := io.ReadAll(io.LimitReader(request.Body, maxPasskeyLoginBody+1))
	closeErr := request.Body.Close()
	if err != nil {
		return Passkey{}, fmt.Errorf("auth: read passkey login request: %w", err)
	}
	if closeErr != nil {
		return Passkey{}, fmt.Errorf("auth: close passkey login request: %w", closeErr)
	}
	if len(body) > maxPasskeyLoginBody {
		return Passkey{}, errors.New("auth: passkey login request is too large")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	user := clonePasskeyUser(s.user)

	matchedPasskey := -1
	handler := func(rawID, userHandle []byte) (webauthn.User, error) {
		if !bytes.Equal(userHandle, user.handle) {
			return nil, errors.New("unknown WebAuthn user handle")
		}
		for i, passkey := range user.passkeys {
			if bytes.Equal(rawID, passkey.Credential.ID) {
				matchedPasskey = i
				return user, nil
			}
		}
		return nil, errors.New("unknown passkey credential")
	}
	validate := func() (webauthn.User, *webauthn.Credential, error) {
		request.Body = io.NopCloser(bytes.NewReader(body))
		return s.webAuthn.FinishPasskeyLogin(handler, ceremony.session, request)
	}
	resolved, credential, err := validate()
	if err != nil && matchedPasskey >= 0 && !user.passkeys[matchedPasskey].FlagsKnown && isBackupEligibleMismatch(err) {
		user.passkeys[matchedPasskey].Credential.Flags.BackupEligible =
			!user.passkeys[matchedPasskey].Credential.Flags.BackupEligible
		resolved, credential, err = validate()
	}
	if err != nil {
		return Passkey{}, fmt.Errorf("auth: finish passkey login: %w", err)
	}
	if !bytes.Equal(resolved.WebAuthnID(), user.handle) {
		return Passkey{}, errors.New("auth: passkey login resolved an unexpected user")
	}

	for i := range s.user.passkeys {
		if !bytes.Equal(s.user.passkeys[i].Credential.ID, credential.ID) {
			continue
		}
		previous := s.user.passkeys[i].Credential
		previousFlagsKnown := s.user.passkeys[i].FlagsKnown
		s.user.passkeys[i].Credential = *credential
		s.user.passkeys[i].FlagsKnown = true
		if err = s.saveLocked(); err != nil {
			s.user.passkeys[i].Credential = previous
			s.user.passkeys[i].FlagsKnown = previousFlagsKnown
			return Passkey{}, err
		}
		return clonePasskey(s.user.passkeys[i]), nil
	}
	return Passkey{}, errors.New("auth: authenticated passkey was removed")
}

func isBackupEligibleMismatch(err error) bool {
	var protocolError *protocol.Error
	return errors.As(err, &protocolError) &&
		protocolError.Details == "Backup Eligible flag inconsistency detected during login validation"
}

func (s *PasskeyStore) List() []Passkey {
	s.mu.Lock()
	defer s.mu.Unlock()
	passkeys := make([]Passkey, len(s.user.passkeys))
	for i := range s.user.passkeys {
		passkeys[i] = clonePasskey(s.user.passkeys[i])
	}
	return passkeys
}

func (s *PasskeyStore) Remove(id string) error {
	return s.remove(id, false)
}

func (s *PasskeyStore) RemoveUnlessLast(id string) error {
	return s.remove(id, true)
}

func (s *PasskeyStore) remove(id string, keepOne bool) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if keepOne && len(s.user.passkeys) <= 1 {
		return errors.New("auth: cannot remove the last passkey without password authentication")
	}
	for i := range s.user.passkeys {
		if s.user.passkeys[i].ID != id {
			continue
		}
		removed := s.user.passkeys[i]
		s.user.passkeys = append(s.user.passkeys[:i], s.user.passkeys[i+1:]...)
		if err := s.saveLocked(); err != nil {
			s.user.passkeys = append(s.user.passkeys, Passkey{})
			copy(s.user.passkeys[i+1:], s.user.passkeys[i:])
			s.user.passkeys[i] = removed
			return err
		}
		return nil
	}
	return fmt.Errorf("auth: passkey %q not found", id)
}

func (s *PasskeyStore) storeCeremony(kind ceremonyKind, label string, session webauthn.SessionData) (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	tokenBytes := make([]byte, 32)
	if _, err := io.ReadFull(s.random, tokenBytes); err != nil {
		return "", fmt.Errorf("auth: generate WebAuthn ceremony token: %w", err)
	}
	token := base64.RawURLEncoding.EncodeToString(tokenBytes)
	key := sha256.Sum256([]byte(token))
	now := s.now()
	session.Expires = time.Time{}

	for storedKey, ceremony := range s.sessions {
		if !now.Before(ceremony.expiresAt) {
			delete(s.sessions, storedKey)
		}
	}
	if len(s.sessions) >= maxPasskeyCeremonies {
		return "", errors.New("auth: too many pending WebAuthn ceremonies")
	}
	if _, exists := s.sessions[key]; exists {
		return "", errors.New("auth: duplicate WebAuthn ceremony token")
	}
	s.sessions[key] = passkeyCeremony{
		kind:      kind,
		label:     label,
		session:   session,
		expiresAt: now.Add(PasskeyCeremonyLifetime),
	}
	return token, nil
}

func (s *PasskeyStore) takeCeremony(token string, kind ceremonyKind) (passkeyCeremony, error) {
	key := sha256.Sum256([]byte(token))
	s.mu.Lock()
	defer s.mu.Unlock()
	ceremony, exists := s.sessions[key]
	if !exists {
		return passkeyCeremony{}, errors.New("auth: unknown WebAuthn ceremony token")
	}
	delete(s.sessions, key)
	if !s.now().Before(ceremony.expiresAt) {
		return passkeyCeremony{}, errors.New("auth: WebAuthn ceremony expired")
	}
	if ceremony.kind != kind {
		return passkeyCeremony{}, errors.New("auth: wrong WebAuthn ceremony type")
	}
	return ceremony, nil
}

func (s *PasskeyStore) load() (bool, error) {
	data, err := os.ReadFile(s.path)
	if errors.Is(err, os.ErrNotExist) {
		return true, nil
	}
	if err != nil {
		return false, fmt.Errorf("auth: read WebAuthn credentials: %w", err)
	}
	if len(bytes.TrimSpace(data)) == 0 {
		return false, errors.New("auth: WebAuthn credentials file is empty")
	}

	var header struct {
		Version int `json:"version"`
	}
	if err = json.Unmarshal(data, &header); err == nil && header.Version == 3 {
		var file passkeyFileV3
		if err = json.Unmarshal(data, &file); err != nil {
			return false, fmt.Errorf("auth: decode WebAuthn credentials v3: %w", err)
		}
		if len(file.UserHandle) == 0 || len(file.UserHandle) > 64 {
			return false, errors.New("auth: invalid WebAuthn v3 user handle")
		}
		if err = validatePasskeys(file.Credentials); err != nil {
			return false, err
		}
		s.user.handle = append([]byte(nil), file.UserHandle...)
		s.user.passkeys = file.Credentials
		return false, nil
	}
	if header.Version > 3 {
		return false, fmt.Errorf("auth: unsupported WebAuthn credentials version %d", header.Version)
	}

	passkeys, err := migrateLegacyPasskeys(data)
	if err != nil {
		return false, err
	}
	s.user.passkeys = passkeys
	return true, nil
}

func validatePasskeys(passkeys []Passkey) error {
	ids := make(map[string]struct{}, len(passkeys))
	credentialIDs := make(map[string]struct{}, len(passkeys))
	for i, passkey := range passkeys {
		if passkey.ID == "" || strings.TrimSpace(passkey.Label) == "" {
			return fmt.Errorf("auth: invalid WebAuthn v3 credential entry %d", i)
		}
		if len(passkey.Credential.ID) == 0 || len(passkey.Credential.PublicKey) == 0 {
			return fmt.Errorf("auth: incomplete WebAuthn v3 credential entry %q", passkey.ID)
		}
		credentialID := base64.RawURLEncoding.EncodeToString(passkey.Credential.ID)
		if _, exists := ids[passkey.ID]; exists {
			return fmt.Errorf("auth: duplicate WebAuthn v3 entry ID %q", passkey.ID)
		}
		if _, exists := credentialIDs[credentialID]; exists {
			return fmt.Errorf("auth: duplicate WebAuthn v3 credential ID in entry %q", passkey.ID)
		}
		ids[passkey.ID] = struct{}{}
		credentialIDs[credentialID] = struct{}{}
	}
	return nil
}

func migrateLegacyPasskeys(data []byte) ([]Passkey, error) {
	var root json.RawMessage = data
	var object map[string]json.RawMessage
	if err := json.Unmarshal(data, &object); err == nil {
		for _, key := range []string{"credentials", "passkeys"} {
			if entries, exists := object[key]; exists {
				root = entries
				break
			}
		}
	}

	var entries []json.RawMessage
	if err := json.Unmarshal(root, &entries); err != nil {
		entries = []json.RawMessage{root}
	}
	passkeys := make([]Passkey, 0, len(entries))
	for i, entry := range entries {
		passkey, err := migrateLegacyPasskeyEntry(entry, i)
		if err != nil {
			return nil, err
		}
		passkeys = append(passkeys, passkey)
	}
	if err := validatePasskeys(passkeys); err != nil {
		return nil, err
	}
	return passkeys, nil
}

func migrateLegacyPasskeyEntry(data []byte, index int) (Passkey, error) {
	var entry struct {
		ID                 string          `json:"id"`
		Label              string          `json:"label"`
		PublicKey          json.RawMessage `json:"public_key"`
		SignCount          uint32          `json:"sign_count"`
		SignCountCamelCase uint32          `json:"signCount"`
		Counter            uint32          `json:"counter"`
	}
	if err := json.Unmarshal(data, &entry); err != nil {
		return Passkey{}, fmt.Errorf("auth: migrate legacy WebAuthn entry %d: %w", index, err)
	}
	name := entry.ID
	if name == "" {
		name = fmt.Sprintf("index %d", index)
	}
	fail := func(format string, args ...any) (Passkey, error) {
		return Passkey{}, fmt.Errorf("auth: migrate legacy WebAuthn entry %q: %s", name, fmt.Sprintf(format, args...))
	}
	if len(entry.PublicKey) == 0 {
		return fail("public_key is missing")
	}
	attestationBytes, err := decodeLegacyBytes(entry.PublicKey)
	if err != nil {
		return fail("decode public_key: %v", err)
	}
	var attestation protocol.AttestationObject
	attestationErr := webauthncbor.Unmarshal(attestationBytes, &attestation)
	if attestationErr == nil {
		attestationErr = attestation.AuthData.Unmarshal(attestation.RawAuthData)
	}
	attested := attestation.AuthData.AttData
	if attestationErr == nil && len(attested.CredentialID) != 0 && len(attested.CredentialPublicKey) != 0 && len(attested.AAGUID) == 16 {
		if entry.ID == "" {
			entry.ID = base64.RawURLEncoding.EncodeToString(attested.CredentialID)
		}
		if strings.TrimSpace(entry.Label) == "" {
			entry.Label = entry.ID
		}
		credential := webauthn.Credential{
			ID:                append([]byte(nil), attested.CredentialID...),
			PublicKey:         append([]byte(nil), attested.CredentialPublicKey...),
			AttestationFormat: attestation.Format,
			Flags:             webauthn.NewCredentialFlags(attestation.AuthData.Flags),
			Authenticator: webauthn.Authenticator{
				AAGUID:    append([]byte(nil), attested.AAGUID...),
				SignCount: legacySignCount(entry.SignCount, entry.SignCountCamelCase, entry.Counter, attestation.AuthData.Counter),
			},
			Attestation: webauthn.CredentialAttestation{
				AuthenticatorData:  append([]byte(nil), attestation.RawAuthData...),
				PublicKeyAlgorithm: credentialPublicKeyAlgorithm(attested.CredentialPublicKey),
				Object:             append([]byte(nil), attestationBytes...),
			},
		}
		if attestation.Format == string(protocol.AttestationFormatNone) {
			credential.AttestationType = "none"
		}
		return Passkey{ID: entry.ID, Label: entry.Label, Credential: credential, FlagsKnown: true}, nil
	}

	algorithm := credentialPublicKeyAlgorithm(attestationBytes)
	if _, known := webauthncose.COSESignatureAlgorithmDetails[webauthncose.COSEAlgorithmIdentifier(algorithm)]; !known {
		return fail("public_key is neither an attestation nor a COSE key with a known algorithm")
	}
	if _, err = webauthncose.ParsePublicKey(attestationBytes); err != nil {
		return fail("parse COSE public_key: %v", err)
	}
	credentialID, err := decodeLegacyID(entry.ID)
	if err != nil {
		return fail("decode id: %v", err)
	}
	if entry.ID == "" {
		return fail("id is missing")
	}
	if strings.TrimSpace(entry.Label) == "" {
		entry.Label = entry.ID
	}
	return Passkey{
		ID:         entry.ID,
		Label:      entry.Label,
		FlagsKnown: false,
		Credential: webauthn.Credential{
			ID:        credentialID,
			PublicKey: append([]byte(nil), attestationBytes...),
			Authenticator: webauthn.Authenticator{
				SignCount: legacySignCount(entry.SignCount, entry.SignCountCamelCase, entry.Counter, 0),
			},
			Attestation: webauthn.CredentialAttestation{
				PublicKeyAlgorithm: algorithm,
			},
		}}, nil
}

func legacySignCount(counts ...uint32) uint32 {
	for _, count := range counts {
		if count != 0 {
			return count
		}
	}
	return 0
}

func decodeLegacyID(id string) ([]byte, error) {
	for _, encoding := range []*base64.Encoding{
		base64.RawURLEncoding,
		base64.URLEncoding,
		base64.RawStdEncoding,
		base64.StdEncoding,
	} {
		if decoded, err := encoding.Strict().DecodeString(id); err == nil && len(decoded) != 0 {
			return decoded, nil
		}
	}
	return nil, errors.New("invalid base64")
}

func decodeLegacyBytes(raw json.RawMessage) ([]byte, error) {
	var encoded string
	if err := json.Unmarshal(raw, &encoded); err == nil {
		for _, encoding := range []*base64.Encoding{
			base64.RawURLEncoding,
			base64.URLEncoding,
			base64.RawStdEncoding,
			base64.StdEncoding,
		} {
			if decoded, decodeErr := encoding.Strict().DecodeString(encoded); decodeErr == nil {
				return decoded, nil
			}
		}
		return nil, errors.New("invalid base64")
	}
	var decoded []byte
	if err := json.Unmarshal(raw, &decoded); err != nil {
		return nil, err
	}
	return decoded, nil
}

func (s *PasskeyStore) saveLocked() error {
	data, err := json.MarshalIndent(passkeyFileV3{
		Version:     3,
		UserHandle:  s.user.handle,
		Credentials: s.user.passkeys,
	}, "", "  ")
	if err != nil {
		return fmt.Errorf("auth: encode WebAuthn credentials: %w", err)
	}
	data = append(data, '\n')
	directory := filepath.Dir(s.path)
	if err = os.MkdirAll(directory, 0o700); err != nil {
		return fmt.Errorf("auth: create WebAuthn credentials directory: %w", err)
	}
	temporary, err := os.CreateTemp(directory, ".passkeys-*")
	if err != nil {
		return fmt.Errorf("auth: create temporary WebAuthn credentials: %w", err)
	}
	temporaryName := temporary.Name()
	defer os.Remove(temporaryName)
	if err = temporary.Chmod(0o600); err == nil {
		_, err = temporary.Write(data)
	}
	if err == nil {
		err = temporary.Sync()
	}
	closeErr := temporary.Close()
	if err == nil {
		err = closeErr
	}
	if err != nil {
		return fmt.Errorf("auth: write WebAuthn credentials: %w", err)
	}
	if err = os.Rename(temporaryName, s.path); err != nil {
		return fmt.Errorf("auth: replace WebAuthn credentials: %w", err)
	}
	directoryHandle, err := os.Open(directory)
	if err != nil {
		return fmt.Errorf("auth: open WebAuthn credentials directory: %w", err)
	}
	defer directoryHandle.Close()
	if err = directoryHandle.Sync(); err != nil {
		return fmt.Errorf("auth: sync WebAuthn credentials directory: %w", err)
	}
	return nil
}

func credentialPublicKeyAlgorithm(publicKey []byte) int64 {
	var values map[int]any
	if err := webauthncbor.Unmarshal(publicKey, &values); err != nil {
		return 0
	}
	switch algorithm := values[3].(type) {
	case int64:
		return algorithm
	case uint64:
		return int64(algorithm)
	case int:
		return int64(algorithm)
	default:
		return 0
	}
}

func clonePasskeyUser(user passkeyUser) passkeyUser {
	user.handle = append([]byte(nil), user.handle...)
	user.passkeys = append([]Passkey(nil), user.passkeys...)
	for i := range user.passkeys {
		user.passkeys[i] = clonePasskey(user.passkeys[i])
	}
	return user
}

func clonePasskey(passkey Passkey) Passkey {
	passkey.Credential.ID = append([]byte(nil), passkey.Credential.ID...)
	passkey.Credential.PublicKey = append([]byte(nil), passkey.Credential.PublicKey...)
	passkey.Credential.Transport = append([]protocol.AuthenticatorTransport(nil), passkey.Credential.Transport...)
	passkey.Credential.Authenticator.AAGUID = append([]byte(nil), passkey.Credential.Authenticator.AAGUID...)
	passkey.Credential.Attestation.ClientDataJSON = append([]byte(nil), passkey.Credential.Attestation.ClientDataJSON...)
	passkey.Credential.Attestation.ClientDataHash = append([]byte(nil), passkey.Credential.Attestation.ClientDataHash...)
	passkey.Credential.Attestation.AuthenticatorData = append([]byte(nil), passkey.Credential.Attestation.AuthenticatorData...)
	passkey.Credential.Attestation.Object = append([]byte(nil), passkey.Credential.Attestation.Object...)
	return passkey
}
