package auth

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"strconv"
	"strings"

	"golang.org/x/crypto/argon2"
)

const (
	argonVersion = 19
	argonMemory  = 64 * 1024
	argonTime    = 3
	argonThreads = 1
	saltLength   = 16
	hashLength   = 32
)

var ErrInvalidPasswordHash = errors.New("auth: invalid password hash")

func ValidatePasswordHash(encoded string) error {
	_, _, _, err := parsePasswordHash(encoded)
	return err
}

// HashPassword applies the pepper with HMAC-SHA256, then hashes the result with Argon2id.
func HashPassword(password string, pepper []byte) (string, error) {
	if len(pepper) == 0 {
		return "", errors.New("auth: pepper is empty")
	}

	salt := make([]byte, saltLength)
	if _, err := rand.Read(salt); err != nil {
		return "", fmt.Errorf("auth: generate password salt: %w", err)
	}

	digest := pepperPassword(password, pepper)
	hash := argon2.IDKey(digest, salt, argonTime, argonMemory, argonThreads, hashLength)
	return fmt.Sprintf(
		"$argon2id$v=%d$pv=1,h=hmac-sha256,m=%d,t=%d,p=%d$%s$%s",
		argonVersion,
		argonMemory,
		argonTime,
		argonThreads,
		base64.RawStdEncoding.EncodeToString(salt),
		base64.RawStdEncoding.EncodeToString(hash),
	), nil
}

// VerifyPassword accepts only the current HMAC-SHA256 and Argon2id PHC format.
func VerifyPassword(password string, pepper []byte, encoded string) (bool, error) {
	if len(pepper) == 0 {
		return false, errors.New("auth: pepper is empty")
	}

	params, salt, expected, err := parsePasswordHash(encoded)
	if err != nil {
		return false, err
	}

	digest := pepperPassword(password, pepper)
	actual := argon2.IDKey(digest, salt, params.time, params.memory, params.threads, uint32(len(expected)))
	return subtle.ConstantTimeCompare(actual, expected) == 1, nil
}

func pepperPassword(password string, pepper []byte) []byte {
	mac := hmac.New(sha256.New, pepper)
	_, _ = mac.Write([]byte(password))
	return mac.Sum(nil)
}

type passwordParams struct {
	memory  uint32
	time    uint32
	threads uint8
}

func parsePasswordHash(encoded string) (passwordParams, []byte, []byte, error) {
	parts := strings.Split(encoded, "$")
	if len(parts) != 6 || parts[0] != "" || parts[1] != "argon2id" || parts[2] != "v=19" {
		return passwordParams{}, nil, nil, ErrInvalidPasswordHash
	}

	values := make(map[string]string, 5)
	for _, parameter := range strings.Split(parts[3], ",") {
		pair := strings.SplitN(parameter, "=", 2)
		if len(pair) != 2 {
			return passwordParams{}, nil, nil, ErrInvalidPasswordHash
		}
		if _, exists := values[pair[0]]; exists {
			return passwordParams{}, nil, nil, ErrInvalidPasswordHash
		}
		values[pair[0]] = pair[1]
	}
	if len(values) != 5 || values["pv"] != "1" || values["h"] != "hmac-sha256" {
		return passwordParams{}, nil, nil, ErrInvalidPasswordHash
	}

	memory, err := parseUint32(values["m"])
	if err != nil || memory < 8*1024 || memory > 256*1024 {
		return passwordParams{}, nil, nil, ErrInvalidPasswordHash
	}
	timeCost, err := parseUint32(values["t"])
	if err != nil || timeCost < 1 || timeCost > 10 {
		return passwordParams{}, nil, nil, ErrInvalidPasswordHash
	}
	threads, err := strconv.ParseUint(values["p"], 10, 8)
	if err != nil || threads < 1 || threads > 16 {
		return passwordParams{}, nil, nil, ErrInvalidPasswordHash
	}

	salt, err := base64.RawStdEncoding.Strict().DecodeString(parts[4])
	if err != nil || len(salt) < 16 || len(salt) > 64 {
		return passwordParams{}, nil, nil, ErrInvalidPasswordHash
	}
	hash, err := base64.RawStdEncoding.Strict().DecodeString(parts[5])
	if err != nil || len(hash) < 16 || len(hash) > 64 {
		return passwordParams{}, nil, nil, ErrInvalidPasswordHash
	}

	return passwordParams{memory: memory, time: timeCost, threads: uint8(threads)}, salt, hash, nil
}

func parseUint32(value string) (uint32, error) {
	parsed, err := strconv.ParseUint(value, 10, 32)
	return uint32(parsed), err
}
