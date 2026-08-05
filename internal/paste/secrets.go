package paste

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
)

func LoadSecrets(path string) (Secrets, error) {
	if path == "" {
		return Secrets{}, fmt.Errorf("paste secrets path is empty")
	}
	file, err := os.Open(path)
	if err != nil {
		return Secrets{}, fmt.Errorf("open paste secrets: %w", err)
	}
	defer file.Close()
	data, err := io.ReadAll(io.LimitReader(file, SecretsMaxBytes+1))
	if err != nil {
		return Secrets{}, fmt.Errorf("read paste secrets: %w", err)
	}
	defer clear(data)
	if len(data) > SecretsMaxBytes {
		return Secrets{}, fmt.Errorf("paste secrets exceed %d bytes", SecretsMaxBytes)
	}
	if err := validateUniqueJSON(data); err != nil {
		return Secrets{}, fmt.Errorf("decode paste secrets: %w", err)
	}
	var secrets Secrets
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&secrets); err != nil {
		return Secrets{}, fmt.Errorf("decode paste secrets: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return Secrets{}, fmt.Errorf("decode paste secrets: trailing JSON")
	}
	if err := ValidateSecrets(secrets); err != nil {
		return Secrets{}, err
	}
	return secrets, nil
}

func validateUniqueJSON(data []byte) error {
	decoder := json.NewDecoder(bytes.NewReader(data))
	var walk func() error
	walk = func() error {
		token, err := decoder.Token()
		if err != nil {
			return err
		}
		delimiter, ok := token.(json.Delim)
		if !ok {
			return nil
		}
		switch delimiter {
		case '{':
			seen := map[string]struct{}{}
			for decoder.More() {
				keyToken, err := decoder.Token()
				if err != nil {
					return err
				}
				key, ok := keyToken.(string)
				if !ok {
					return errors.New("object key is not a string")
				}
				if _, exists := seen[key]; exists {
					return fmt.Errorf("duplicate field %q", key)
				}
				seen[key] = struct{}{}
				if err := walk(); err != nil {
					return err
				}
			}
		case '[':
			for decoder.More() {
				if err := walk(); err != nil {
					return err
				}
			}
		default:
			return errors.New("unexpected JSON delimiter")
		}
		_, err = decoder.Token()
		return err
	}
	if err := walk(); err != nil {
		return err
	}
	if _, err := decoder.Token(); !errors.Is(err, io.EOF) {
		return errors.New("trailing JSON")
	}
	return nil
}
