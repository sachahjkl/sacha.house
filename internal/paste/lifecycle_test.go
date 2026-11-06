package paste

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"testing"
)

type failingTransport struct{ err error }

func (transport failingTransport) RoundTrip(*http.Request) (*http.Response, error) {
	return nil, transport.err
}

func TestGistTimeoutOfAMutationHasAnUnknownOutcome(t *testing.T) {
	client := &GistClient{baseURL: "https://example.test", token: "token", client: &http.Client{Transport: failingTransport{context.DeadlineExceeded}}}
	if _, err := client.request(context.Background(), http.MethodPost, "https://example.test/gists", nil, http.StatusCreated, true, nil); gistKind(err) != GistOutcomeUnknown {
		t.Fatalf("mutation kind = %v", gistKind(err))
	}
	if _, err := client.request(context.Background(), http.MethodGet, "https://example.test/gists", nil, http.StatusOK, false, nil); gistKind(err) != GistTimeout {
		t.Fatalf("read kind = %v", gistKind(err))
	}
}

type unreadableGistAPI struct {
	GistAPI
	gist    Gist
	deleted bool
}

func (api *unreadableGistAPI) Get(context.Context, string) (Gist, error) { return api.gist, nil }
func (api *unreadableGistAPI) Delete(context.Context, string) error {
	api.deleted = true
	return nil
}

func TestUnreadablePasteCanBeDeleted(t *testing.T) {
	api := &unreadableGistAPI{gist: Gist{
		ID: "aabbcc", Description: DescriptionPrefix + strings.Repeat("ab", pidBytes),
		Files:   map[string]GistFile{GistFilename: {Filename: GistFilename, Content: "not an envelope"}},
		History: []GistHistory{{Version: "01"}},
	}}
	codec, err := NewCodec(testSecrets("old"))
	if err != nil {
		t.Fatal(err)
	}
	store, err := NewStore(api, codec, MinBodyBytes, MinListItems)
	if err != nil {
		t.Fatal(err)
	}
	if err := store.Delete(context.Background(), "aabbcc", "02"); ErrorKindOf(err) != ErrorConflict {
		t.Fatalf("stale revision: %v", err)
	}
	if api.deleted {
		t.Fatal("a stale revision deleted the paste")
	}
	if err := store.Delete(context.Background(), "aabbcc", "01"); err != nil {
		t.Fatalf("Delete() = %v", err)
	}
	if !api.deleted {
		t.Fatal("the paste was not deleted")
	}
}

func TestDeleteRefusesAGistThatIsNotOurs(t *testing.T) {
	api := &unreadableGistAPI{gist: Gist{ID: "aabbcc", Description: "my notes", History: []GistHistory{{Version: "01"}}}}
	codec, err := NewCodec(testSecrets("old"))
	if err != nil {
		t.Fatal(err)
	}
	store, err := NewStore(api, codec, MinBodyBytes, MinListItems)
	if err != nil {
		t.Fatal(err)
	}
	err = store.Delete(context.Background(), "aabbcc", "01")
	if ErrorKindOf(err) != ErrorNotOurs || api.deleted || errors.Is(err, context.Canceled) {
		t.Fatalf("Delete() = %v, deleted = %t", err, api.deleted)
	}
}
