package auth

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/go-webauthn/webauthn/protocol"
	"github.com/go-webauthn/webauthn/protocol/webauthncbor"
	"github.com/go-webauthn/webauthn/webauthn"
)

func TestPasskeyStoreV3RoundTrip(t *testing.T) {
	path := filepath.Join(t.TempDir(), "passkeys.json")
	handle := bytes.Repeat([]byte{0x42}, 32)
	want := testPasskey("credential-1", "Laptop")
	writePasskeyV3(t, path, handle, []Passkey{want})

	store := newTestPasskeyStore(t, path, nil, nil)
	got := store.List()
	if len(got) != 1 || got[0].ID != want.ID || got[0].Label != want.Label {
		t.Fatalf("List() = %#v", got)
	}
	if !bytes.Equal(got[0].Credential.PublicKey, want.Credential.PublicKey) {
		t.Fatal("credential public key changed")
	}

	reloaded := newTestPasskeyStore(t, path, nil, nil)
	if !bytes.Equal(reloaded.user.handle, handle) {
		t.Fatalf("user handle changed: %x", reloaded.user.handle)
	}
	if reloaded.List()[0].Credential.Authenticator.SignCount != 7 {
		t.Fatal("credential state did not round-trip")
	}
}

func TestPasskeyStoreCreatesStableUserHandle(t *testing.T) {
	path := filepath.Join(t.TempDir(), "passkeys.json")
	random := bytes.NewReader(bytes.Repeat([]byte{0x5a}, 32))
	store := newTestPasskeyStore(t, path, nil, random)
	first := append([]byte(nil), store.user.handle...)
	if len(first) != 32 {
		t.Fatalf("user handle length = %d", len(first))
	}

	reloaded := newTestPasskeyStore(t, path, nil, bytes.NewReader(bytes.Repeat([]byte{0x11}, 32)))
	if !bytes.Equal(reloaded.user.handle, first) {
		t.Fatalf("stable handle changed from %x to %x", first, reloaded.user.handle)
	}
}

func TestPasskeyStoreBoundsPendingCeremonies(t *testing.T) {
	store := newTestPasskeyStore(t, filepath.Join(t.TempDir(), "passkeys.json"), nil, nil)
	for range maxPasskeyCeremonies {
		if _, _, err := store.BeginDiscoverableLogin(); err != nil {
			t.Fatal(err)
		}
	}
	if _, _, err := store.BeginDiscoverableLogin(); err == nil {
		t.Fatal("expected pending ceremony limit error")
	}
	if got := len(store.sessions); got != maxPasskeyCeremonies {
		t.Fatalf("pending ceremony count = %d", got)
	}
}

func TestPasskeyStoreMigratesV1AttestationCBOR(t *testing.T) {
	path := filepath.Join(t.TempDir(), "passkeys.json")
	credentialID := []byte("realistic-credential-id")
	aaguid := []byte{0x08, 0x98, 0x70, 0x58, 0xca, 0x93, 0x49, 0xb8, 0x8f, 0x5e, 0x38, 0xf9, 0x7d, 0x25, 0x5f, 0x5e}
	publicKey := realisticCOSEKey(t)
	attestation := realisticAttestation(t, credentialID, aaguid, publicKey, 3)
	legacy := map[string]any{
		"version": 1,
		"credentials": []map[string]any{{
			"id":         "legacy-id",
			"label":      "Security key",
			"public_key": base64.RawURLEncoding.EncodeToString(attestation),
			"sign_count": 9,
		}},
	}
	writeJSON(t, path, legacy)

	store := newTestPasskeyStore(t, path, nil, bytes.NewReader(bytes.Repeat([]byte{0x33}, 32)))
	passkeys := store.List()
	if len(passkeys) != 1 {
		t.Fatalf("List() length = %d", len(passkeys))
	}
	got := passkeys[0]
	if got.ID != "legacy-id" || got.Label != "Security key" {
		t.Fatalf("migrated identity = %q, %q", got.ID, got.Label)
	}
	if !bytes.Equal(got.Credential.ID, credentialID) || !bytes.Equal(got.Credential.PublicKey, publicKey) {
		t.Fatal("migrated credential data differs from the attestation")
	}
	if !bytes.Equal(got.Credential.Authenticator.AAGUID, aaguid) || got.Credential.Authenticator.SignCount != 9 {
		t.Fatalf("migrated authenticator = %#v", got.Credential.Authenticator)
	}
	if !bytes.Equal(got.Credential.Attestation.Object, attestation) {
		t.Fatal("migration did not retain the attestation object")
	}
	if got.Credential.Attestation.PublicKeyAlgorithm != -7 {
		t.Fatalf("public key algorithm = %d", got.Credential.Attestation.PublicKeyAlgorithm)
	}
	if !got.FlagsKnown {
		t.Fatal("attestation migration did not mark flags as known")
	}

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var file passkeyFileV3
	if err = json.Unmarshal(data, &file); err != nil {
		t.Fatal(err)
	}
	if file.Version != 3 || len(file.UserHandle) != 32 {
		t.Fatalf("migrated file header = version %d, handle %x", file.Version, file.UserHandle)
	}
}

func TestPasskeyStoreMigratesV2COSEPublicKey(t *testing.T) {
	path := filepath.Join(t.TempDir(), "passkeys.json")
	credentialID := []byte{0xfb, 0xff, 0x01}
	publicKey := realisticCOSEKey(t)
	writeJSON(t, path, map[string]any{
		"version": 2,
		"credentials": []map[string]any{{
			"id":         base64.StdEncoding.EncodeToString(credentialID),
			"label":      "Production key",
			"public_key": base64.StdEncoding.EncodeToString(publicKey),
			"counter":    12,
		}},
	})

	store := newTestPasskeyStore(t, path, nil, bytes.NewReader(bytes.Repeat([]byte{0x35}, 32)))
	passkeys := store.List()
	if len(passkeys) != 1 {
		t.Fatalf("List() length = %d", len(passkeys))
	}
	got := passkeys[0]
	if !bytes.Equal(got.Credential.ID, credentialID) || !bytes.Equal(got.Credential.PublicKey, publicKey) {
		t.Fatal("direct COSE migration changed credential data")
	}
	if got.Credential.Authenticator.SignCount != 12 || got.FlagsKnown {
		t.Fatalf("migrated state = counter %d, flags known %t", got.Credential.Authenticator.SignCount, got.FlagsKnown)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var file passkeyFileV3
	if err = json.Unmarshal(data, &file); err != nil {
		t.Fatal(err)
	}
	if file.Version != 3 || file.Credentials[0].FlagsKnown {
		t.Fatalf("migrated file = %#v", file)
	}
}

func TestPasskeyStoreMigratesHistoricalSingleCredential(t *testing.T) {
	path := filepath.Join(t.TempDir(), "passkeys.json")
	attestation := realisticAttestation(
		t,
		[]byte("single-id"),
		bytes.Repeat([]byte{0x01}, 16),
		realisticCOSEKey(t),
		4,
	)
	writeJSON(t, path, map[string]any{
		"id":         "single",
		"label":      "Phone",
		"public_key": base64.StdEncoding.EncodeToString(attestation),
	})

	store := newTestPasskeyStore(t, path, nil, bytes.NewReader(bytes.Repeat([]byte{0x44}, 32)))
	passkeys := store.List()
	if len(passkeys) != 1 || passkeys[0].ID != "single" || passkeys[0].Label != "Phone" {
		t.Fatalf("List() = %#v", passkeys)
	}
	if passkeys[0].Credential.Authenticator.SignCount != 4 {
		t.Fatalf("attestation sign count = %d", passkeys[0].Credential.Authenticator.SignCount)
	}
}

func TestPasskeyMigrationFailureDoesNotOverwriteFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "passkeys.json")
	original := []byte(`{"version":2,"credentials":[{"id":"broken-key","label":"Broken","public_key":"not cbor"}]}`)
	if err := os.WriteFile(path, original, 0o600); err != nil {
		t.Fatal(err)
	}

	_, err := NewPasskeyStore(testPasskeyConfig(path, nil, bytes.NewReader(bytes.Repeat([]byte{1}, 32))))
	if err == nil || !strings.Contains(err.Error(), "broken-key") {
		t.Fatalf("NewPasskeyStore() error = %v", err)
	}
	got, readErr := os.ReadFile(path)
	if readErr != nil {
		t.Fatal(readErr)
	}
	if !bytes.Equal(got, original) {
		t.Fatalf("failed migration changed file to %q", got)
	}
}

func TestPasskeyLabelsAndRemoval(t *testing.T) {
	path := filepath.Join(t.TempDir(), "passkeys.json")
	writePasskeyV3(t, path, bytes.Repeat([]byte{0x21}, 32), []Passkey{
		testPasskey("first", "Work laptop"),
		testPasskey("second", "Security key"),
	})
	store := newTestPasskeyStore(t, path, nil, nil)

	if err := store.Remove("first"); err != nil {
		t.Fatal(err)
	}
	got := store.List()
	if len(got) != 1 || got[0].ID != "second" || got[0].Label != "Security key" {
		t.Fatalf("List() after Remove() = %#v", got)
	}
	if err := store.Remove("missing"); err == nil {
		t.Fatal("Remove() accepted an unknown ID")
	}

	reloaded := newTestPasskeyStore(t, path, nil, nil)
	if got = reloaded.List(); len(got) != 1 || got[0].ID != "second" {
		t.Fatalf("persisted List() = %#v", got)
	}
}

func TestPasskeyStoreCanKeepLastCredential(t *testing.T) {
	path := filepath.Join(t.TempDir(), "passkeys.json")
	writePasskeyV3(t, path, bytes.Repeat([]byte{0x42}, 32), []Passkey{testPasskey("only", "Only key")})
	store := newTestPasskeyStore(t, path, nil, nil)
	if err := store.RemoveUnlessLast("only"); err == nil {
		t.Fatal("RemoveUnlessLast() removed the final credential")
	}
	if len(store.List()) != 1 {
		t.Fatal("final credential was removed")
	}
}

func TestPasskeyCeremonyExpiresAndIsSingleUse(t *testing.T) {
	path := filepath.Join(t.TempDir(), "passkeys.json")
	now := time.Date(2026, 8, 5, 12, 0, 0, 0, time.UTC)
	store := newTestPasskeyStore(t, path, func() time.Time { return now }, bytes.NewReader(bytes.Repeat([]byte{0x77}, 64)))
	assertion, token, err := store.BeginDiscoverableLogin()
	if err != nil {
		t.Fatal(err)
	}
	if assertion.Response.UserVerification != protocol.VerificationRequired {
		t.Fatalf("user verification = %q", assertion.Response.UserVerification)
	}
	if len(assertion.Response.AllowedCredentials) != 0 {
		t.Fatal("discoverable login contains an allow list")
	}
	if len(token) != 43 {
		t.Fatalf("opaque token length = %d", len(token))
	}

	now = now.Add(PasskeyCeremonyLifetime)
	request := httptest.NewRequest(http.MethodPost, "/", strings.NewReader(`{}`))
	request.Header.Set("Content-Type", "application/json")
	if _, err = store.FinishPasskeyLogin(token, request); err == nil || !strings.Contains(err.Error(), "expired") {
		t.Fatalf("expired FinishPasskeyLogin() error = %v", err)
	}
	if _, err = store.FinishPasskeyLogin(token, request); err == nil || !strings.Contains(err.Error(), "unknown") {
		t.Fatalf("reused FinishPasskeyLogin() error = %v", err)
	}
}

func TestPasskeyLoginLearnsUnknownBackupEligibleFlag(t *testing.T) {
	path := filepath.Join(t.TempDir(), "passkeys.json")
	handle := bytes.Repeat([]byte{0x61}, 32)
	credentialID := []byte("migrated-credential")
	privateKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	publicKey, err := webauthncbor.Marshal(map[int]any{
		1:  2,
		3:  -7,
		-1: 1,
		-2: privateKey.X.FillBytes(make([]byte, 32)),
		-3: privateKey.Y.FillBytes(make([]byte, 32)),
	})
	if err != nil {
		t.Fatal(err)
	}
	writePasskeyV3(t, path, handle, []Passkey{{
		ID:    base64.RawURLEncoding.EncodeToString(credentialID),
		Label: "Migrated key",
		Credential: webauthn.Credential{
			ID:        credentialID,
			PublicKey: publicKey,
		},
	}})
	store := newTestPasskeyStore(t, path, nil, nil)
	assertion, token, err := store.BeginDiscoverableLogin()
	if err != nil {
		t.Fatal(err)
	}

	clientData, err := json.Marshal(map[string]any{
		"type":      "webauthn.get",
		"challenge": assertion.Response.Challenge.String(),
		"origin":    "https://example.com",
	})
	if err != nil {
		t.Fatal(err)
	}
	rpIDHash := sha256.Sum256([]byte("example.com"))
	authenticatorData := append([]byte(nil), rpIDHash[:]...)
	authenticatorData = append(authenticatorData, byte(
		protocol.FlagUserPresent|protocol.FlagUserVerified|protocol.FlagBackupEligible,
	))
	authenticatorData = append(authenticatorData, 0, 0, 0, 1)
	clientDataHash := sha256.Sum256(clientData)
	signedData := append(append([]byte(nil), authenticatorData...), clientDataHash[:]...)
	digest := sha256.Sum256(signedData)
	signature, err := ecdsa.SignASN1(rand.Reader, privateKey, digest[:])
	if err != nil {
		t.Fatal(err)
	}
	body, err := json.Marshal(map[string]any{
		"id":    base64.RawURLEncoding.EncodeToString(credentialID),
		"rawId": base64.RawURLEncoding.EncodeToString(credentialID),
		"type":  "public-key",
		"response": map[string]any{
			"clientDataJSON":    base64.RawURLEncoding.EncodeToString(clientData),
			"authenticatorData": base64.RawURLEncoding.EncodeToString(authenticatorData),
			"signature":         base64.RawURLEncoding.EncodeToString(signature),
			"userHandle":        base64.RawURLEncoding.EncodeToString(handle),
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	request := httptest.NewRequest(http.MethodPost, "/", bytes.NewReader(body))
	request.Header.Set("Content-Type", "application/json")
	got, err := store.FinishPasskeyLogin(token, request)
	if err != nil {
		t.Fatal(err)
	}
	if !got.FlagsKnown || !got.Credential.Flags.BackupEligible {
		t.Fatalf("learned flags = %#v, known %t", got.Credential.Flags, got.FlagsKnown)
	}

	reloaded := newTestPasskeyStore(t, path, nil, nil).List()[0]
	if !reloaded.FlagsKnown || !reloaded.Credential.Flags.BackupEligible {
		t.Fatalf("persisted flags = %#v, known %t", reloaded.Credential.Flags, reloaded.FlagsKnown)
	}
}

func TestPasskeyRegistrationRequiresLabelAndDiscoverableCredential(t *testing.T) {
	path := filepath.Join(t.TempDir(), "passkeys.json")
	store := newTestPasskeyStore(t, path, nil, nil)
	if _, _, err := store.BeginRegistration("  "); err == nil {
		t.Fatal("BeginRegistration() accepted an empty label")
	}
	creation, _, err := store.BeginRegistration("  Main key  ")
	if err != nil {
		t.Fatal(err)
	}
	selection := creation.Response.AuthenticatorSelection
	if selection.ResidentKey != protocol.ResidentKeyRequirementRequired {
		t.Fatalf("resident key requirement = %q", selection.ResidentKey)
	}
	if selection.UserVerification != protocol.VerificationRequired {
		t.Fatalf("registration user verification = %q", selection.UserVerification)
	}
}

func TestBackupEligibleMismatchDetection(t *testing.T) {
	matching := protocol.ErrBadRequest.WithDetails("Backup Eligible flag inconsistency detected during login validation")
	if !isBackupEligibleMismatch(matching) {
		t.Fatal("backup eligibility mismatch was not detected")
	}
	if isBackupEligibleMismatch(protocol.ErrBadRequest.WithDetails("Stored challenge and received challenge do not match")) {
		t.Fatal("challenge failure was detected as a backup eligibility mismatch")
	}
	if isBackupEligibleMismatch(errors.New("Backup Eligible flag inconsistency detected during login validation")) {
		t.Fatal("untyped error was detected as a backup eligibility mismatch")
	}
}

func newTestPasskeyStore(t *testing.T, path string, now Clock, random io.Reader) *PasskeyStore {
	t.Helper()
	var source = testPasskeyConfig(path, now, random)
	store, err := NewPasskeyStore(source)
	if err != nil {
		t.Fatal(err)
	}
	return store
}

func testPasskeyConfig(path string, now Clock, random io.Reader) PasskeyConfig {
	return PasskeyConfig{
		CredentialsFile:  path,
		RPID:             "example.com",
		RPDisplayName:    "Example",
		RPOrigins:        []string{"https://example.com"},
		AdminName:        "admin",
		AdminDisplayName: "Site administrator",
		Now:              now,
		Random:           random,
	}
}

func testPasskey(id, label string) Passkey {
	credentialID := []byte(id)
	return Passkey{
		ID:         id,
		Label:      label,
		FlagsKnown: true,
		Credential: webauthn.Credential{
			ID:                credentialID,
			PublicKey:         []byte{0xa5, 0x01, 0x02, 0x03},
			AttestationType:   "none",
			AttestationFormat: "none",
			Flags: webauthn.NewCredentialFlags(
				protocol.FlagUserPresent | protocol.FlagUserVerified | protocol.FlagBackupEligible,
			),
			Authenticator: webauthn.Authenticator{
				AAGUID:    bytes.Repeat([]byte{0x10}, 16),
				SignCount: 7,
			},
		},
	}
}

func writePasskeyV3(t *testing.T, path string, handle []byte, passkeys []Passkey) {
	t.Helper()
	writeJSON(t, path, passkeyFileV3{Version: 3, UserHandle: handle, Credentials: passkeys})
}

func writeJSON(t *testing.T, path string, value any) {
	t.Helper()
	data, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(path, data, 0o600); err != nil {
		t.Fatal(err)
	}
}

func realisticCOSEKey(t *testing.T) []byte {
	t.Helper()
	x, y := elliptic.P256().ScalarBaseMult(bytes.Repeat([]byte{0x12}, 32))
	key, err := webauthncbor.Marshal(map[int]any{
		1:  2,
		3:  -7,
		-1: 1,
		-2: x.FillBytes(make([]byte, 32)),
		-3: y.FillBytes(make([]byte, 32)),
	})
	if err != nil {
		t.Fatal(err)
	}
	return key
}

func realisticAttestation(t *testing.T, credentialID, aaguid, publicKey []byte, counter uint32) []byte {
	t.Helper()
	rpIDHash := sha256.Sum256([]byte("example.com"))
	authenticatorData := append([]byte(nil), rpIDHash[:]...)
	authenticatorData = append(authenticatorData, byte(
		protocol.FlagUserPresent|protocol.FlagUserVerified|protocol.FlagAttestedCredentialData,
	))
	counterBytes := make([]byte, 4)
	binary.BigEndian.PutUint32(counterBytes, counter)
	authenticatorData = append(authenticatorData, counterBytes...)
	authenticatorData = append(authenticatorData, aaguid...)
	idLength := make([]byte, 2)
	binary.BigEndian.PutUint16(idLength, uint16(len(credentialID)))
	authenticatorData = append(authenticatorData, idLength...)
	authenticatorData = append(authenticatorData, credentialID...)
	authenticatorData = append(authenticatorData, publicKey...)

	attestation, err := webauthncbor.Marshal(map[string]any{
		"fmt":      "none",
		"attStmt":  map[string]any{},
		"authData": authenticatorData,
	})
	if err != nil {
		t.Fatal(err)
	}
	return attestation
}
