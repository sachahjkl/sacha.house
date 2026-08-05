package paste

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

const (
	gistAPIVersion       = "2022-11-28"
	gistUserAgent        = "sacha.house-paste/1.0"
	gistMaxResponseBytes = 4 << 20
	gistErrorBodyBytes   = 16 << 10
	gistMaxRetryAfter    = 24 * time.Hour
	gistMaxIDBytes       = 64
)

type GistErrorKind int

const (
	GistNetwork GistErrorKind = iota + 1
	GistTimeout
	GistUnauthorized
	GistForbidden
	GistNotFound
	GistRateLimited
	GistValidation
	GistResponseTooLarge
	GistMalformedResponse
	GistUpstream
	GistOutcomeUnknown
)

type GistError struct {
	Kind       GistErrorKind
	Status     int
	RetryAfter time.Duration
	Message    string
}

func (err *GistError) Error() string { return err.Message }

type GistFile struct {
	Filename  string `json:"filename"`
	Content   string `json:"content"`
	Truncated bool   `json:"truncated"`
}

type GistHistory struct {
	Version string `json:"version"`
}

type Gist struct {
	ID          string              `json:"id"`
	Description string              `json:"description"`
	CreatedAt   string              `json:"created_at"`
	UpdatedAt   string              `json:"updated_at"`
	Files       map[string]GistFile `json:"files"`
	History     []GistHistory       `json:"history"`
}

type GistWriteFile struct {
	Content string `json:"content"`
}

type GistCreate struct {
	Description string                   `json:"description"`
	Public      bool                     `json:"public"`
	Files       map[string]GistWriteFile `json:"files"`
}

type GistUpdate struct {
	Files map[string]GistWriteFile `json:"files"`
}

type GistClient struct {
	baseURL string
	token   string
	client  *http.Client
}

func NewGistClient(baseURL, token string, client *http.Client) (*GistClient, error) {
	parsed, err := url.Parse(baseURL)
	if err != nil || parsed.Scheme != "https" || parsed.Host == "" || parsed.User != nil || parsed.RawQuery != "" || parsed.Fragment != "" {
		return nil, &GistError{Kind: GistValidation, Message: "invalid GitHub Gist client configuration"}
	}
	if token == "" || strings.ContainsAny(token, "\x00\r\n \t") {
		return nil, &GistError{Kind: GistValidation, Message: "invalid GitHub Gist client configuration"}
	}
	if client == nil {
		client = &http.Client{Timeout: 20 * time.Second}
	}
	return &GistClient{baseURL: strings.TrimRight(baseURL, "/"), token: token, client: client}, nil
}

func (client *GistClient) List(ctx context.Context, page, perPage int) ([]Gist, bool, error) {
	if page < 1 || perPage < 1 || perPage > 100 {
		return nil, false, &GistError{Kind: GistValidation, Message: "invalid GitHub Gist page request"}
	}
	var result []Gist
	header, err := client.request(ctx, http.MethodGet, fmt.Sprintf("%s/gists?per_page=%d&page=%d", client.baseURL, perPage, page), nil, http.StatusOK, false, &result)
	return result, hasNextLink(header.Get("Link")), err
}

func (client *GistClient) Get(ctx context.Context, id string) (Gist, error) {
	if !validGistID(id) {
		return Gist{}, &GistError{Kind: GistValidation, Message: "invalid GitHub Gist identifier"}
	}
	var result Gist
	_, err := client.request(ctx, http.MethodGet, client.baseURL+"/gists/"+id, nil, http.StatusOK, false, &result)
	return result, err
}

func (client *GistClient) Create(ctx context.Context, input GistCreate) (Gist, error) {
	var result Gist
	_, err := client.request(ctx, http.MethodPost, client.baseURL+"/gists", input, http.StatusCreated, true, &result)
	return result, err
}

func (client *GistClient) Update(ctx context.Context, id string, input GistUpdate) (Gist, error) {
	if !validGistID(id) {
		return Gist{}, &GistError{Kind: GistValidation, Message: "invalid GitHub Gist update request"}
	}
	var result Gist
	_, err := client.request(ctx, http.MethodPatch, client.baseURL+"/gists/"+id, input, http.StatusOK, true, &result)
	return result, err
}

func (client *GistClient) Delete(ctx context.Context, id string) error {
	if !validGistID(id) {
		return &GistError{Kind: GistValidation, Message: "invalid GitHub Gist identifier"}
	}
	_, err := client.request(ctx, http.MethodDelete, client.baseURL+"/gists/"+id, nil, http.StatusNoContent, true, nil)
	return err
}

func (client *GistClient) request(ctx context.Context, method, target string, payload any, expected int, mutation bool, output any) (http.Header, error) {
	var body io.Reader
	if payload != nil {
		encoded, err := json.Marshal(payload)
		if err != nil {
			return nil, &GistError{Kind: GistValidation, Message: "could not encode GitHub Gist request"}
		}
		body = bytes.NewReader(encoded)
	}
	request, err := http.NewRequestWithContext(ctx, method, target, body)
	if err != nil {
		return nil, &GistError{Kind: GistValidation, Message: "could not prepare GitHub request"}
	}
	request.Header.Set("Accept", "application/vnd.github+json")
	request.Header.Set("Authorization", "Bearer "+client.token)
	request.Header.Set("X-GitHub-Api-Version", gistAPIVersion)
	request.Header.Set("User-Agent", gistUserAgent)
	if payload != nil {
		request.Header.Set("Content-Type", "application/json")
	}
	response, err := client.client.Do(request)
	if err != nil {
		if errors.Is(err, context.DeadlineExceeded) || errors.Is(ctx.Err(), context.DeadlineExceeded) {
			return nil, &GistError{Kind: GistTimeout, Message: "GitHub request timed out"}
		}
		kind := GistNetwork
		message := "GitHub network request failed"
		if mutation {
			kind = GistOutcomeUnknown
			message = "GitHub mutation outcome is unknown"
		}
		return nil, &GistError{Kind: kind, Message: message}
	}
	defer response.Body.Close()
	if response.StatusCode != expected {
		_, _ = io.Copy(io.Discard, io.LimitReader(response.Body, gistErrorBodyBytes))
		if mutation && (response.StatusCode == http.StatusRequestTimeout || response.StatusCode >= http.StatusInternalServerError) {
			return response.Header, &GistError{Kind: GistOutcomeUnknown, Status: response.StatusCode, Message: "GitHub mutation outcome is unknown"}
		}
		return response.Header, gistStatusError(response)
	}
	if output == nil {
		_, _ = io.Copy(io.Discard, io.LimitReader(response.Body, gistErrorBodyBytes))
		return response.Header, nil
	}
	limited := &io.LimitedReader{R: response.Body, N: gistMaxResponseBytes + 1}
	data, err := io.ReadAll(limited)
	if err != nil {
		kind := GistNetwork
		message := "GitHub response could not be read"
		if mutation {
			kind = GistOutcomeUnknown
			message = "GitHub mutation outcome is unknown"
		}
		return response.Header, &GistError{Kind: kind, Status: response.StatusCode, Message: message}
	}
	if len(data) > gistMaxResponseBytes {
		if mutation {
			return response.Header, &GistError{Kind: GistOutcomeUnknown, Status: response.StatusCode, Message: "GitHub mutation outcome is unknown"}
		}
		return response.Header, &GistError{Kind: GistResponseTooLarge, Status: response.StatusCode, Message: "GitHub response exceeded the configured limit"}
	}
	if err := json.Unmarshal(data, output); err != nil {
		if mutation {
			return response.Header, &GistError{Kind: GistOutcomeUnknown, Status: response.StatusCode, Message: "GitHub mutation outcome is unknown"}
		}
		return response.Header, &GistError{Kind: GistMalformedResponse, Status: response.StatusCode, Message: "GitHub returned malformed JSON"}
	}
	return response.Header, nil
}

func hasNextLink(value string) bool {
	for part := range strings.SplitSeq(value, ",") {
		if strings.Contains(part, `rel="next"`) {
			return true
		}
	}
	return false
}

func gistStatusError(response *http.Response) error {
	errorValue := &GistError{Status: response.StatusCode}
	switch response.StatusCode {
	case http.StatusUnauthorized:
		errorValue.Kind, errorValue.Message = GistUnauthorized, "GitHub authentication was rejected"
	case http.StatusForbidden:
		if response.Header.Get("X-Ratelimit-Remaining") == "0" || response.Header.Get("Retry-After") != "" {
			errorValue.Kind, errorValue.Message = GistRateLimited, "GitHub rate limit is exhausted"
			errorValue.RetryAfter = retryAfter(response.Header)
		} else {
			errorValue.Kind, errorValue.Message = GistForbidden, "GitHub denied the Gist request"
		}
	case http.StatusNotFound:
		errorValue.Kind, errorValue.Message = GistNotFound, "GitHub Gist was not found"
	case http.StatusRequestTimeout, http.StatusGatewayTimeout:
		errorValue.Kind, errorValue.Message = GistTimeout, "GitHub request timed out"
	case http.StatusUnprocessableEntity:
		errorValue.Kind, errorValue.Message = GistValidation, "GitHub rejected the Gist request"
	case http.StatusTooManyRequests:
		errorValue.Kind, errorValue.Message = GistRateLimited, "GitHub rate limit is exhausted"
		errorValue.RetryAfter = retryAfter(response.Header)
	default:
		errorValue.Kind, errorValue.Message = GistUpstream, "GitHub returned an unexpected status"
	}
	return errorValue
}

func retryAfter(header http.Header) time.Duration {
	if seconds, err := strconv.ParseInt(header.Get("Retry-After"), 10, 64); err == nil && seconds > 0 {
		return min(time.Duration(seconds)*time.Second, gistMaxRetryAfter)
	}
	if reset, err := strconv.ParseInt(header.Get("X-Ratelimit-Reset"), 10, 64); err == nil {
		return min(max(time.Until(time.Unix(reset, 0)), 0), gistMaxRetryAfter)
	}
	return 0
}

func validGistID(value string) bool {
	if len(value) < 1 || len(value) > gistMaxIDBytes {
		return false
	}
	for _, character := range value {
		if !(character >= '0' && character <= '9') && !(character >= 'a' && character <= 'f') && !(character >= 'A' && character <= 'F') {
			return false
		}
	}
	return true
}
