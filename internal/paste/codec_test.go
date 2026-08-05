package paste

import (
	"strings"
	"testing"
)

func testSecrets(active string) Secrets {
	return Secrets{
		GitHubGistToken: "test-token",
		ActiveKeyID:     active,
		Keys: []KeyConfig{
			{ID: "old", KeyHex: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"},
			{ID: "new", KeyHex: "202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f"},
		},
	}
}

func TestCodecVector(t *testing.T) {
	codec, err := NewCodec(testSecrets("old"))
	if err != nil {
		t.Fatal(err)
	}
	random := make([]byte, pidBytes+chachaNonceSize())
	for index := range random {
		random[index] = byte(index)
	}
	codec.random = strings.NewReader(string(random))
	envelope, pid, err := codec.EncryptNew("Vector", "hello", 1700000000000, 1024)
	if err != nil {
		t.Fatal(err)
	}
	const expected = `{"v":1,"alg":"xchacha20poly1305","kid":"old","pid":"000102030405060708090a0b0c0d0e0f","nonce":"101112131415161718191a1b1c1d1e1f2021222324252627","ciphertext":"77b453c7548821d5968222c8fd902287c06e9feff96d215829a191764c40c3e1c5a59452648e48","tag":"d8a69cc1fee5ee66689a144c55999620"}`
	if envelope != expected {
		t.Fatalf("envelope vector = %q", envelope)
	}
	if pid != "000102030405060708090a0b0c0d0e0f" {
		t.Fatalf("pid = %q", pid)
	}
	document, parsed, err := codec.Decrypt(envelope, 1024)
	if err != nil {
		t.Fatal(err)
	}
	if parsed.KeyID != "old" || document.Title != "Vector" || document.Body != "hello" || document.CreatedMS != 1700000000000 || document.UpdatedMS != 1700000000000 {
		t.Fatalf("decoded vector = %#v, %#v", parsed, document)
	}
}

func TestCodecRotationPreservesDocumentAndPasteID(t *testing.T) {
	oldCodec, _ := NewCodec(testSecrets("old"))
	envelope, pid, err := oldCodec.EncryptNew("Title", "body", 42, 1024)
	if err != nil {
		t.Fatal(err)
	}
	newCodec, _ := NewCodec(testSecrets("new"))
	rotated, err := newCodec.Rotate(envelope, 1024)
	if err != nil {
		t.Fatal(err)
	}
	document, parsed, err := newCodec.Decrypt(rotated, 1024)
	if err != nil {
		t.Fatal(err)
	}
	if parsed.KeyID != "new" || parsed.PasteID != pid || document.Title != "Title" || document.Body != "body" || document.CreatedMS != 42 || document.UpdatedMS != 42 {
		t.Fatalf("rotated = %#v, %#v", parsed, document)
	}
}

func TestCodecRejectsTamperingAndUnknownKeys(t *testing.T) {
	codec, _ := NewCodec(testSecrets("old"))
	envelope, _, _ := codec.EncryptNew("Title", "body", 42, 1024)
	tampered := strings.Replace(envelope, `"ciphertext":"`, `"ciphertext":"0`, 1)
	if _, _, err := codec.Decrypt(tampered, 1024); err == nil {
		t.Fatal("tampered envelope was accepted")
	}
	unknownSecrets := testSecrets("new")
	unknownSecrets.Keys = unknownSecrets.Keys[1:]
	unknown, _ := NewCodec(unknownSecrets)
	if _, _, err := unknown.Decrypt(envelope, 1024); err != ErrKeyUnavailable {
		t.Fatalf("unknown key error = %v", err)
	}
}

func chachaNonceSize() int { return 24 }
