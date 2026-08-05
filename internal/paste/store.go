package paste

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"
)

const (
	GistFilename      = "sacha-house-paste.json"
	DescriptionPrefix = "sacha.house encrypted paste pid="
	MinBodyBytes      = 1024
	MaxBodyBytes      = 1024 * 1024
	MinListItems      = 1
	MaxListItems      = 500
	maxRevisionBytes  = 128
	gistPageSize      = 100
)

type ErrorKind int

const (
	ErrorInvalidInput ErrorKind = iota + 1
	ErrorNotFound
	ErrorNotOurs
	ErrorConflict
	ErrorUnknownKey
	ErrorCorrupt
	ErrorRateLimited
	ErrorUpstreamUnavailable
	ErrorTooLarge
	ErrorOutcomeUnknown
)

type Error struct {
	Kind              ErrorKind
	RetryAfterSeconds int
	Message           string
}

func (err *Error) Error() string { return err.Message }

type Input struct {
	Title string
	Body  string
}

type Loaded struct {
	GistID        string
	Revision      string
	KeyID         string
	PasteID       string
	Document      Document
	NeedsRotation bool
}

type ListStatus int

const (
	StatusReady ListStatus = iota
	StatusNeedsRotation
	StatusUnknownKey
	StatusCorrupt
)

type Summary struct {
	GistID    string
	Revision  string
	KeyID     string
	PasteID   string
	Title     string
	CreatedAt string
	UpdatedAt string
	Status    ListStatus
}

type GistAPI interface {
	List(context.Context, int, int) ([]Gist, bool, error)
	Get(context.Context, string) (Gist, error)
	Create(context.Context, GistCreate) (Gist, error)
	Update(context.Context, string, GistUpdate) (Gist, error)
	Delete(context.Context, string) error
}

type Store struct {
	gist         GistAPI
	codec        *Codec
	maxBodyBytes int
	maxListItems int
	mutations    sync.Mutex
}

func NewStore(gist GistAPI, codec *Codec, maxBodyBytes, maxListItems int) (*Store, error) {
	if gist == nil || codec == nil || maxBodyBytes < MinBodyBytes || maxBodyBytes > MaxBodyBytes || maxListItems < MinListItems || maxListItems > MaxListItems {
		return nil, pasteError(ErrorInvalidInput)
	}
	return &Store{gist: gist, codec: codec, maxBodyBytes: maxBodyBytes, maxListItems: maxListItems}, nil
}

func (store *Store) Validate(input Input, nowMS int64) error {
	return codecError(validateDocument(Document{Title: input.Title, Body: input.Body, CreatedMS: nowMS, UpdatedMS: nowMS}, store.maxBodyBytes))
}

func (store *Store) List(ctx context.Context) ([]Summary, bool, error) {
	result := make([]Summary, 0)
	examined := 0
	perPage := min(gistPageSize, store.maxListItems)
	for page := 1; examined < store.maxListItems; page++ {
		gists, hasNext, err := store.gist.List(ctx, page, perPage)
		if err != nil {
			return result, true, gistError(err)
		}
		count := min(len(gists), store.maxListItems-examined)
		for index := range count {
			examined++
			summary, include, err := store.summarize(ctx, gists[index])
			if err != nil {
				return result, true, err
			}
			if include {
				result = append(result, summary)
			}
		}
		if examined >= store.maxListItems {
			return result, count < len(gists) || hasNext, nil
		}
		if !hasNext {
			return result, false, nil
		}
	}
	return result, true, nil
}

func (store *Store) Get(ctx context.Context, gistID string) (Loaded, error) {
	if !validGistID(gistID) {
		return Loaded{}, pasteError(ErrorNotFound)
	}
	gist, err := store.gist.Get(ctx, gistID)
	if err != nil {
		return Loaded{}, gistError(err)
	}
	if !sameGistID(gist.ID, gistID) {
		return Loaded{}, pasteError(ErrorUpstreamUnavailable)
	}
	return store.loadedFromGist(gist)
}

func (store *Store) Create(ctx context.Context, input Input, nowMS int64) (Loaded, error) {
	if err := store.Validate(input, nowMS); err != nil {
		return Loaded{}, err
	}
	envelope, pid, err := store.codec.EncryptNew(input.Title, input.Body, nowMS, store.maxBodyBytes)
	if err != nil {
		return Loaded{}, codecError(err)
	}
	created, err := store.gist.Create(ctx, GistCreate{
		Description: DescriptionPrefix + pid,
		Public:      false,
		Files:       map[string]GistWriteFile{GistFilename: {Content: envelope}},
	})
	if err != nil {
		return Loaded{}, gistError(err)
	}
	loaded, err := store.loadedAfterMutation(ctx, created)
	if err != nil {
		return Loaded{}, err
	}
	if loaded.PasteID != pid {
		return Loaded{}, pasteError(ErrorUpstreamUnavailable)
	}
	return loaded, nil
}

func (store *Store) Update(ctx context.Context, gistID, expectedRevision string, input Input, nowMS int64) (Loaded, error) {
	if !validRevision(expectedRevision) {
		return Loaded{}, pasteError(ErrorInvalidInput)
	}
	if !validGistID(gistID) {
		return Loaded{}, pasteError(ErrorNotFound)
	}
	if err := store.Validate(input, nowMS); err != nil {
		return Loaded{}, err
	}
	store.mutations.Lock()
	defer store.mutations.Unlock()
	current, err := store.Get(ctx, gistID)
	if err != nil {
		return Loaded{}, err
	}
	if current.Revision != expectedRevision {
		return Loaded{}, pasteError(ErrorConflict)
	}
	if nowMS < current.Document.CreatedMS {
		return Loaded{}, pasteError(ErrorInvalidInput)
	}
	current.Document.Title = input.Title
	current.Document.Body = input.Body
	current.Document.UpdatedMS = nowMS
	envelope, err := store.codec.EncryptExisting(current.PasteID, current.Document, store.maxBodyBytes)
	if err != nil {
		return Loaded{}, codecError(err)
	}
	return store.writeEnvelope(ctx, gistID, envelope)
}

func (store *Store) Rotate(ctx context.Context, gistID, expectedRevision string) (Loaded, error) {
	if !validRevision(expectedRevision) {
		return Loaded{}, pasteError(ErrorInvalidInput)
	}
	if !validGistID(gistID) {
		return Loaded{}, pasteError(ErrorNotFound)
	}
	store.mutations.Lock()
	defer store.mutations.Unlock()
	current, err := store.Get(ctx, gistID)
	if err != nil {
		return Loaded{}, err
	}
	if current.Revision != expectedRevision {
		return Loaded{}, pasteError(ErrorConflict)
	}
	envelope, err := store.codec.EncryptExisting(current.PasteID, current.Document, store.maxBodyBytes)
	if err != nil {
		return Loaded{}, codecError(err)
	}
	return store.writeEnvelope(ctx, gistID, envelope)
}

func (store *Store) Delete(ctx context.Context, gistID, expectedRevision string) error {
	if !validRevision(expectedRevision) {
		return pasteError(ErrorInvalidInput)
	}
	if !validGistID(gistID) {
		return pasteError(ErrorNotFound)
	}
	store.mutations.Lock()
	defer store.mutations.Unlock()
	current, err := store.Get(ctx, gistID)
	if err != nil {
		return err
	}
	if current.Revision != expectedRevision {
		return pasteError(ErrorConflict)
	}
	return gistError(store.gist.Delete(ctx, gistID))
}

func (store *Store) writeEnvelope(ctx context.Context, gistID, envelope string) (Loaded, error) {
	updated, err := store.gist.Update(ctx, gistID, GistUpdate{Files: map[string]GistWriteFile{GistFilename: {Content: envelope}}})
	if err != nil {
		return Loaded{}, gistError(err)
	}
	if !sameGistID(updated.ID, gistID) {
		return Loaded{}, pasteError(ErrorUpstreamUnavailable)
	}
	return store.loadedAfterMutation(ctx, updated)
}

func (store *Store) loadedAfterMutation(ctx context.Context, gist Gist) (Loaded, error) {
	_, file, ours := gistOwner(gist)
	if !ours {
		return Loaded{}, pasteError(ErrorUpstreamUnavailable)
	}
	if file.Truncated || file.Content == "" || len(gist.History) == 0 {
		fetched, err := store.gist.Get(ctx, gist.ID)
		if err != nil {
			return Loaded{}, gistError(err)
		}
		if !sameGistID(fetched.ID, gist.ID) {
			return Loaded{}, pasteError(ErrorUpstreamUnavailable)
		}
		gist = fetched
	}
	return store.loadedFromGist(gist)
}

func (store *Store) loadedFromGist(gist Gist) (Loaded, error) {
	markerPID, file, ours := gistOwner(gist)
	if !ours {
		return Loaded{}, pasteError(ErrorNotOurs)
	}
	if file.Truncated {
		return Loaded{}, pasteError(ErrorTooLarge)
	}
	if file.Content == "" || len(gist.History) == 0 || !validRevision(gist.History[0].Version) {
		return Loaded{}, pasteError(ErrorCorrupt)
	}
	document, envelope, err := store.codec.Decrypt(file.Content, store.maxBodyBytes)
	if envelope.PasteID != "" && envelope.PasteID != markerPID {
		return Loaded{}, pasteError(ErrorNotOurs)
	}
	if err != nil {
		return Loaded{}, codecError(err)
	}
	if envelope.PasteID != markerPID {
		return Loaded{}, pasteError(ErrorNotOurs)
	}
	return Loaded{
		GistID: gist.ID, Revision: gist.History[0].Version, KeyID: envelope.KeyID,
		PasteID: envelope.PasteID, Document: document, NeedsRotation: envelope.KeyID != store.codec.ActiveKeyID(),
	}, nil
}

func (store *Store) summarize(ctx context.Context, listed Gist) (Summary, bool, error) {
	listedPID, listedFile, ours := gistOwner(listed)
	if !ours {
		return Summary{}, false, nil
	}
	source := listed
	if listedFile.Truncated || listedFile.Content == "" || len(listed.History) == 0 {
		fetched, err := store.gist.Get(ctx, listed.ID)
		if err != nil {
			return Summary{}, false, gistError(err)
		}
		fetchedPID, _, fetchedOurs := gistOwner(fetched)
		if !sameGistID(fetched.ID, listed.ID) || !fetchedOurs || fetchedPID != listedPID {
			return Summary{}, false, nil
		}
		source = fetched
	}
	markerPID, file, ours := gistOwner(source)
	if !ours {
		return Summary{}, false, nil
	}
	summary := Summary{GistID: source.ID, PasteID: markerPID, CreatedAt: source.CreatedAt, UpdatedAt: source.UpdatedAt, Status: StatusCorrupt}
	if len(source.History) == 0 || !validRevision(source.History[0].Version) || file.Truncated || file.Content == "" {
		return summary, true, nil
	}
	summary.Revision = source.History[0].Version
	document, envelope, err := store.codec.Decrypt(file.Content, store.maxBodyBytes)
	if validKeyID(envelope.KeyID) {
		summary.KeyID = envelope.KeyID
	}
	if errors.Is(err, ErrKeyUnavailable) && envelope.PasteID == markerPID {
		summary.Status = StatusUnknownKey
	} else if err == nil && envelope.PasteID == markerPID {
		summary.Title = document.Title
		summary.Status = StatusReady
		if envelope.KeyID != store.codec.ActiveKeyID() {
			summary.Status = StatusNeedsRotation
		}
	}
	return summary, true, nil
}

func gistOwner(gist Gist) (string, GistFile, bool) {
	if !validGistID(gist.ID) || len(gist.Files) != 1 || !strings.HasPrefix(gist.Description, DescriptionPrefix) {
		return "", GistFile{}, false
	}
	pid := strings.TrimPrefix(gist.Description, DescriptionPrefix)
	if len(gist.Description) != len(DescriptionPrefix)+pidBytes*2 || !lowerHex(pid, pidBytes*2) {
		return "", GistFile{}, false
	}
	file, found := gist.Files[GistFilename]
	if !found || file.Filename != GistFilename {
		return "", GistFile{}, false
	}
	return pid, file, true
}

func validRevision(value string) bool {
	if len(value) < 1 || len(value) > maxRevisionBytes {
		return false
	}
	for _, character := range value {
		if !(character >= '0' && character <= '9') && !(character >= 'a' && character <= 'f') && !(character >= 'A' && character <= 'F') {
			return false
		}
	}
	return true
}

func sameGistID(first, second string) bool {
	return validGistID(first) && validGistID(second) && strings.EqualFold(first, second)
}

func codecError(err error) error {
	if err == nil {
		return nil
	}
	switch {
	case errors.Is(err, ErrInvalidInput):
		return pasteError(ErrorInvalidInput)
	case errors.Is(err, ErrTooLarge):
		return pasteError(ErrorTooLarge)
	case errors.Is(err, ErrKeyUnavailable):
		return pasteError(ErrorUnknownKey)
	case errors.Is(err, ErrInvalidEnvelope), errors.Is(err, ErrUnsupportedVersion), errors.Is(err, ErrUnsupportedAlgorithm), errors.Is(err, ErrAuthentication):
		return pasteError(ErrorCorrupt)
	default:
		return pasteError(ErrorUpstreamUnavailable)
	}
}

func gistError(err error) error {
	if err == nil {
		return nil
	}
	var remote *GistError
	if !errors.As(err, &remote) {
		return pasteError(ErrorUpstreamUnavailable)
	}
	switch remote.Kind {
	case GistNotFound:
		return pasteError(ErrorNotFound)
	case GistRateLimited:
		value := pasteError(ErrorRateLimited)
		value.RetryAfterSeconds = int(remote.RetryAfter.Seconds())
		return value
	case GistResponseTooLarge:
		return pasteError(ErrorTooLarge)
	case GistOutcomeUnknown:
		return pasteError(ErrorOutcomeUnknown)
	default:
		return pasteError(ErrorUpstreamUnavailable)
	}
}

func pasteError(kind ErrorKind) *Error {
	messages := map[ErrorKind]string{
		ErrorInvalidInput: "invalid paste input",
		ErrorNotFound:     "paste not found", ErrorNotOurs: "Gist is not an encrypted paste",
		ErrorConflict: "remote revision changed; reload before saving", ErrorUnknownKey: "paste encryption key is unavailable",
		ErrorCorrupt: "encrypted paste could not be authenticated", ErrorRateLimited: "paste storage is rate limited",
		ErrorUpstreamUnavailable: "paste storage is unavailable", ErrorTooLarge: "paste data exceeds the configured limit",
		ErrorOutcomeUnknown: "the remote mutation outcome is unknown; refresh before retrying",
	}
	return &Error{Kind: kind, Message: messages[kind]}
}

func ErrorKindOf(err error) ErrorKind {
	var pasteErr *Error
	if errors.As(err, &pasteErr) {
		return pasteErr.Kind
	}
	return ErrorUpstreamUnavailable
}

func RetryAfterSeconds(err error) int {
	var pasteErr *Error
	if errors.As(err, &pasteErr) {
		return pasteErr.RetryAfterSeconds
	}
	return 0
}

func ValidateGistID(value string) bool   { return validGistID(value) }
func ValidateRevision(value string) bool { return validRevision(value) }

func (status ListStatus) String() string {
	switch status {
	case StatusReady:
		return "ready"
	case StatusNeedsRotation:
		return "needs rotation"
	case StatusUnknownKey:
		return "key unavailable"
	case StatusCorrupt:
		return "corrupt or unauthenticated"
	default:
		return fmt.Sprintf("status %d", status)
	}
}
