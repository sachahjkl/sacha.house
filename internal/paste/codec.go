package paste

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"
	"unicode/utf8"

	"golang.org/x/crypto/chacha20poly1305"
)

const (
	Version          = 1
	Algorithm        = "xchacha20poly1305"
	TitleMaxBytes    = 200
	KeyIDMaxBytes    = 63
	KeyringMaxKeys   = 16
	SecretsMaxBytes  = 64 << 10
	plaintextHeader  = 28
	pastePurpose     = "sacha.house/paste"
	pasteAlgorithmID = byte(1)
	pidBytes         = 16
)

var (
	ErrInvalidInput         = errors.New("invalid paste input")
	ErrTooLarge             = errors.New("paste data exceeds the configured limit")
	ErrInvalidEnvelope      = errors.New("invalid paste envelope")
	ErrUnsupportedVersion   = errors.New("unsupported paste envelope version")
	ErrUnsupportedAlgorithm = errors.New("unsupported paste encryption algorithm")
	ErrKeyUnavailable       = errors.New("paste encryption key is unavailable")
	ErrAuthentication       = errors.New("encrypted paste could not be authenticated")
)

type KeyConfig struct {
	ID     string `json:"id"`
	KeyHex string `json:"key_hex"`
}

type Secrets struct {
	GitHubGistToken string      `json:"github_gist_token"`
	ActiveKeyID     string      `json:"active_key_id"`
	Keys            []KeyConfig `json:"keys"`
}

type Document struct {
	Title     string
	Body      string
	CreatedMS int64
	UpdatedMS int64
}

type Envelope struct {
	Version    int    `json:"v"`
	Algorithm  string `json:"alg"`
	KeyID      string `json:"kid"`
	PasteID    string `json:"pid"`
	Nonce      string `json:"nonce"`
	Ciphertext string `json:"ciphertext"`
	Tag        string `json:"tag"`
}

type Codec struct {
	activeID string
	keys     map[string][chacha20poly1305.KeySize]byte
	random   io.Reader
}

func NewCodec(secrets Secrets) (*Codec, error) {
	if err := ValidateSecrets(secrets); err != nil {
		return nil, err
	}
	codec := &Codec{activeID: secrets.ActiveKeyID, keys: make(map[string][chacha20poly1305.KeySize]byte), random: rand.Reader}
	for _, item := range secrets.Keys {
		material, _ := hex.DecodeString(item.KeyHex)
		var key [chacha20poly1305.KeySize]byte
		copy(key[:], material)
		codec.keys[item.ID] = key
		clear(material)
	}
	return codec, nil
}

func (codec *Codec) ActiveKeyID() string { return codec.activeID }

func ValidateSecrets(secrets Secrets) error {
	if secrets.GitHubGistToken == "" || !utf8.ValidString(secrets.GitHubGistToken) || strings.ContainsAny(secrets.GitHubGistToken, "\x00\r\n") {
		return fmt.Errorf("invalid GitHub Gist token: %w", ErrInvalidInput)
	}
	if len(secrets.Keys) < 1 || len(secrets.Keys) > KeyringMaxKeys || !validKeyID(secrets.ActiveKeyID) {
		return fmt.Errorf("invalid paste keyring: %w", ErrInvalidInput)
	}
	ids := make(map[string]struct{}, len(secrets.Keys))
	materials := make([]string, 0, len(secrets.Keys))
	active := false
	for _, key := range secrets.Keys {
		if !validKeyID(key.ID) || !lowerHex(key.KeyHex, chacha20poly1305.KeySize*2) {
			return fmt.Errorf("invalid paste key: %w", ErrInvalidInput)
		}
		if _, exists := ids[key.ID]; exists {
			return fmt.Errorf("duplicate paste key identifier: %w", ErrInvalidInput)
		}
		for _, material := range materials {
			if subtle.ConstantTimeCompare([]byte(material), []byte(key.KeyHex)) == 1 {
				return fmt.Errorf("duplicate paste key material: %w", ErrInvalidInput)
			}
		}
		ids[key.ID] = struct{}{}
		materials = append(materials, key.KeyHex)
		active = active || key.ID == secrets.ActiveKeyID
	}
	if !active {
		return fmt.Errorf("active paste key is missing: %w", ErrInvalidInput)
	}
	return nil
}

func (codec *Codec) EncryptNew(title, body string, nowMS int64, maxBody int) (string, string, error) {
	random := make([]byte, pidBytes+chacha20poly1305.NonceSizeX)
	if _, err := io.ReadFull(codec.random, random); err != nil {
		return "", "", fmt.Errorf("generate paste nonce: %w", err)
	}
	defer clear(random)
	pid := hex.EncodeToString(random[:pidBytes])
	envelope, err := codec.encrypt(codec.activeID, random[:pidBytes], random[pidBytes:], Document{
		Title: title, Body: body, CreatedMS: nowMS, UpdatedMS: nowMS,
	}, maxBody)
	return envelope, pid, err
}

func (codec *Codec) EncryptExisting(pid string, document Document, maxBody int) (string, error) {
	if !lowerHex(pid, pidBytes*2) {
		return "", ErrInvalidInput
	}
	pidValue, _ := hex.DecodeString(pid)
	defer clear(pidValue)
	nonce := make([]byte, chacha20poly1305.NonceSizeX)
	if _, err := io.ReadFull(codec.random, nonce); err != nil {
		return "", fmt.Errorf("generate paste nonce: %w", err)
	}
	defer clear(nonce)
	return codec.encrypt(codec.activeID, pidValue, nonce, document, maxBody)
}

func (codec *Codec) encrypt(keyID string, pid, nonce []byte, document Document, maxBody int) (string, error) {
	plaintext, err := encodePlaintext(document, maxBody)
	if err != nil {
		return "", err
	}
	defer clear(plaintext)
	key, found := codec.keys[keyID]
	if !found || len(pid) != pidBytes || len(nonce) != chacha20poly1305.NonceSizeX {
		return "", ErrInvalidInput
	}
	aead, err := chacha20poly1305.NewX(key[:])
	if err != nil {
		return "", err
	}
	sealed := aead.Seal(nil, nonce, plaintext, aad(keyID, pid))
	ciphertext := sealed[:len(plaintext)]
	tag := sealed[len(plaintext):]
	// Keep this field order and compact representation compatible with Odin.
	return `{"v":1,"alg":"xchacha20poly1305","kid":"` + keyID + `","pid":"` + hex.EncodeToString(pid) +
		`","nonce":"` + hex.EncodeToString(nonce) + `","ciphertext":"` + hex.EncodeToString(ciphertext) +
		`","tag":"` + hex.EncodeToString(tag) + `"}`, nil
}

func (codec *Codec) Decrypt(input string, maxBody int) (Document, Envelope, error) {
	envelope, err := parseEnvelope(input, maxBody)
	if err != nil {
		return Document{}, envelope, err
	}
	key, found := codec.keys[envelope.KeyID]
	if !found {
		return Document{}, envelope, ErrKeyUnavailable
	}
	pid, _ := hex.DecodeString(envelope.PasteID)
	nonce, _ := hex.DecodeString(envelope.Nonce)
	ciphertext, _ := hex.DecodeString(envelope.Ciphertext)
	tag, _ := hex.DecodeString(envelope.Tag)
	defer clear(pid)
	defer clear(nonce)
	defer clear(ciphertext)
	defer clear(tag)
	aead, _ := chacha20poly1305.NewX(key[:])
	sealed := append(ciphertext, tag...)
	plaintext, err := aead.Open(nil, nonce, sealed, aad(envelope.KeyID, pid))
	clear(sealed)
	if err != nil {
		return Document{}, envelope, ErrAuthentication
	}
	defer clear(plaintext)
	document, err := decodePlaintext(plaintext, maxBody)
	return document, envelope, err
}

func (codec *Codec) Rotate(input string, maxBody int) (string, error) {
	document, envelope, err := codec.Decrypt(input, maxBody)
	if err != nil {
		return "", err
	}
	return codec.EncryptExisting(envelope.PasteID, document, maxBody)
}

func encodePlaintext(document Document, maxBody int) ([]byte, error) {
	if err := validateDocument(document, maxBody); err != nil {
		return nil, err
	}
	value := make([]byte, plaintextHeader+len(document.Title)+len(document.Body))
	copy(value, "SHP1")
	binary.BigEndian.PutUint32(value[4:8], uint32(len(document.Title)))
	binary.BigEndian.PutUint32(value[8:12], uint32(len(document.Body)))
	binary.BigEndian.PutUint64(value[12:20], uint64(document.CreatedMS))
	binary.BigEndian.PutUint64(value[20:28], uint64(document.UpdatedMS))
	copy(value[plaintextHeader:], document.Title)
	copy(value[plaintextHeader+len(document.Title):], document.Body)
	return value, nil
}

func decodePlaintext(value []byte, maxBody int) (Document, error) {
	if len(value) < plaintextHeader+1 || string(value[:4]) != "SHP1" {
		return Document{}, ErrInvalidEnvelope
	}
	titleLength := uint64(binary.BigEndian.Uint32(value[4:8]))
	bodyLength := uint64(binary.BigEndian.Uint32(value[8:12]))
	if plaintextHeader+titleLength+bodyLength != uint64(len(value)) || titleLength < 1 || titleLength > TitleMaxBytes || bodyLength > uint64(maxBody) {
		return Document{}, ErrInvalidEnvelope
	}
	titleEnd := plaintextHeader + int(titleLength)
	document := Document{
		Title: string(value[plaintextHeader:titleEnd]), Body: string(value[titleEnd:]),
		CreatedMS: int64(binary.BigEndian.Uint64(value[12:20])), UpdatedMS: int64(binary.BigEndian.Uint64(value[20:28])),
	}
	if err := validateDocument(document, maxBody); err != nil {
		if errors.Is(err, ErrTooLarge) {
			return Document{}, err
		}
		return Document{}, ErrInvalidEnvelope
	}
	return document, nil
}

func parseEnvelope(input string, maxBody int) (Envelope, error) {
	maxClear := plaintextHeader + TitleMaxBytes + maxBody
	maxEnvelope := len(`{"v":1,"alg":"xchacha20poly1305","kid":"`) + KeyIDMaxBytes +
		len(`","pid":"`) + pidBytes*2 + len(`","nonce":"`) + chacha20poly1305.NonceSizeX*2 +
		len(`","ciphertext":"`) + maxClear*2 + len(`","tag":"`) + chacha20poly1305.Overhead*2 + len(`"}`)
	if maxBody < 0 || len(input) > maxEnvelope {
		return Envelope{}, ErrTooLarge
	}
	if err := validateUniqueJSON([]byte(input)); err != nil {
		return Envelope{}, ErrInvalidEnvelope
	}
	var envelope Envelope
	decoder := json.NewDecoder(strings.NewReader(input))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&envelope); err != nil {
		return envelope, ErrInvalidEnvelope
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return envelope, ErrInvalidEnvelope
	}
	if envelope.Version != Version {
		return envelope, ErrUnsupportedVersion
	}
	if envelope.Algorithm != Algorithm {
		return envelope, ErrUnsupportedAlgorithm
	}
	if !validKeyID(envelope.KeyID) || !lowerHex(envelope.PasteID, pidBytes*2) ||
		!lowerHex(envelope.Nonce, chacha20poly1305.NonceSizeX*2) || !lowerHex(envelope.Tag, chacha20poly1305.Overhead*2) ||
		len(envelope.Ciphertext)%2 != 0 || !lowerHex(envelope.Ciphertext, len(envelope.Ciphertext)) {
		return envelope, ErrInvalidEnvelope
	}
	clearLength := len(envelope.Ciphertext) / 2
	if clearLength < plaintextHeader+1 {
		return envelope, ErrInvalidEnvelope
	}
	if clearLength > maxClear {
		return envelope, ErrTooLarge
	}
	return envelope, nil
}

func validateDocument(document Document, maxBody int) error {
	if maxBody < 0 || len(document.Title) < 1 || len(document.Title) > TitleMaxBytes || !utf8.ValidString(document.Title) || strings.ContainsAny(document.Title, "\x00\r\n") || !utf8.ValidString(document.Body) || document.CreatedMS < 0 || document.UpdatedMS < document.CreatedMS {
		return ErrInvalidInput
	}
	if len(document.Body) > maxBody {
		return ErrTooLarge
	}
	return nil
}

func aad(keyID string, pid []byte) []byte {
	value := make([]byte, 0, len(pastePurpose)+4+len(keyID)+len(pid))
	value = append(value, pastePurpose...)
	value = append(value, 0, Version, pasteAlgorithmID, byte(len(keyID)))
	value = append(value, keyID...)
	return append(value, pid...)
}

func validKeyID(value string) bool {
	if len(value) < 1 || len(value) > KeyIDMaxBytes {
		return false
	}
	for _, character := range value {
		if !(character >= 'A' && character <= 'Z') && !(character >= 'a' && character <= 'z') && !(character >= '0' && character <= '9') && character != '.' && character != '_' && character != '-' {
			return false
		}
	}
	return true
}

func lowerHex(value string, length int) bool {
	if len(value) != length {
		return false
	}
	for _, character := range value {
		if !(character >= '0' && character <= '9') && !(character >= 'a' && character <= 'f') {
			return false
		}
	}
	return true
}
