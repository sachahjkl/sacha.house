package projects

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"image/png"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/issue9/identicon/v2"
	"gopkg.in/yaml.v3"
)

const (
	maxResponseSize = 8 << 20
	cacheVersion    = 2
	cacheSource     = "github"
	maxRetries      = 2
	maxRetryDelay   = 30 * time.Second
)

// Project keeps the field names used by projects_cache.json and the templates.
type Project struct {
	Name            string    `json:"name"`
	URL             string    `json:"url"`
	DescriptionHTML string    `json:"descriptionHtml"`
	AvatarURL       string    `json:"avatarUrl"`
	FirstLetter     string    `json:"first_letter"`
	HSLColor        string    `json:"hslColor"`
	HasAvatar       bool      `json:"hasAvatar"`
	LastCommitDate  time.Time `json:"lastCommitDate"`
	LastCommitHash  string    `json:"lastCommitHash"`
	LastCommitURL   string    `json:"lastCommitUrl"`
}

// Cache is the on-disk projects_cache.json format.
type Cache struct {
	Version     int       `json:"version"`
	Source      string    `json:"source"`
	RefreshedAt time.Time `json:"refreshedAt"`
	Projects    []Project `json:"projects"`
}

type ClientConfig struct {
	GitHubEndpoint string
	GitHubToken    string
	Username       string
}

// Client fetches projects from the GitHub GraphQL API.
type Client struct {
	httpClient *http.Client
	config     ClientConfig
}

func NewClient(httpClient *http.Client, config ClientConfig) *Client {
	if httpClient == nil {
		httpClient = http.DefaultClient
	}
	return &Client{httpClient: httpClient, config: config}
}

func (c *Client) Fetch(ctx context.Context) (Cache, error) {
	projects, err := c.fetchGitHub(ctx)
	if err != nil {
		return Cache{}, fmt.Errorf("fetch GitHub projects: %w", err)
	}
	return Cache{Version: cacheVersion, Source: cacheSource, RefreshedAt: time.Now().UTC(), Projects: projects}, nil
}

type graphQLRequest struct {
	Query     string         `json:"query"`
	Variables map[string]any `json:"variables"`
}

type graphQLError struct {
	Message string `json:"message"`
}

type projectEntry struct {
	Name   string `json:"name"`
	Type   string `json:"type"`
	Object struct {
		Text *string `json:"text"`
	} `json:"object"`
}

func (c *Client) request(ctx context.Context, endpoint, token string, request graphQLRequest, response any) error {
	if endpoint == "" {
		return errors.New("GraphQL endpoint is not set")
	}
	if token == "" {
		return errors.New("bearer token is not set")
	}

	body, err := json.Marshal(request)
	if err != nil {
		return fmt.Errorf("encode GraphQL request: %w", err)
	}
	for attempt := 0; ; attempt++ {
		req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, strings.NewReader(string(body)))
		if err != nil {
			return fmt.Errorf("create GraphQL request: %w", err)
		}
		req.Header.Set("Authorization", "Bearer "+token)
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Accept", "application/vnd.github+json")
		req.Header.Set("X-GitHub-Api-Version", "2022-11-28")

		res, requestErr := c.httpClient.Do(req)
		if requestErr != nil {
			if attempt < maxRetries && ctx.Err() == nil {
				if err := waitForRetry(ctx, time.Duration(1<<attempt)*250*time.Millisecond); err != nil {
					return fmt.Errorf("send GraphQL request: %w", err)
				}
				continue
			}
			return fmt.Errorf("send GraphQL request: %w", requestErr)
		}

		data, readErr := io.ReadAll(io.LimitReader(res.Body, maxResponseSize+1))
		res.Body.Close()
		if readErr != nil {
			return fmt.Errorf("read GraphQL response: %w", readErr)
		}
		if len(data) > maxResponseSize {
			return errors.New("GraphQL response exceeds 8 MiB")
		}
		if retryableGitHubResponse(res) && attempt < maxRetries {
			if err := waitForRetry(ctx, githubRetryDelay(res.Header, attempt)); err != nil {
				return fmt.Errorf("wait to retry GraphQL request: %w", err)
			}
			continue
		}
		if res.StatusCode < http.StatusOK || res.StatusCode >= http.StatusMultipleChoices {
			return fmt.Errorf("GraphQL response status %s: %s", res.Status, strings.TrimSpace(string(data)))
		}

		var envelope struct {
			Errors []graphQLError `json:"errors"`
		}
		if err := json.Unmarshal(data, &envelope); err != nil {
			return fmt.Errorf("decode GraphQL response: %w", err)
		}
		if len(envelope.Errors) != 0 {
			return fmt.Errorf("GraphQL error: %s", envelope.Errors[0].Message)
		}
		if err := json.Unmarshal(data, response); err != nil {
			return fmt.Errorf("decode GraphQL response: %w", err)
		}
		return nil
	}
}

func retryableGitHubResponse(response *http.Response) bool {
	if response.StatusCode == http.StatusTooManyRequests || response.StatusCode == http.StatusBadGateway ||
		response.StatusCode == http.StatusServiceUnavailable || response.StatusCode == http.StatusGatewayTimeout {
		return true
	}
	return response.StatusCode == http.StatusForbidden &&
		(response.Header.Get("X-RateLimit-Remaining") == "0" || response.Header.Get("Retry-After") != "")
}

func githubRetryDelay(header http.Header, attempt int) time.Duration {
	if seconds, err := strconv.ParseInt(header.Get("Retry-After"), 10, 64); err == nil && seconds >= 0 {
		return min(time.Duration(seconds)*time.Second, maxRetryDelay)
	}
	if reset, err := strconv.ParseInt(header.Get("X-RateLimit-Reset"), 10, 64); err == nil {
		return min(max(time.Until(time.Unix(reset, 0)), 0), maxRetryDelay)
	}
	return time.Duration(1<<attempt) * 250 * time.Millisecond
}

func waitForRetry(ctx context.Context, delay time.Duration) error {
	timer := time.NewTimer(delay)
	defer timer.Stop()
	select {
	case <-timer.C:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func (c *Client) fetchGitHub(ctx context.Context) ([]Project, error) {
	const query = `query GET_PROJECTS_GITHUB($username: String!, $cursor: String) {
			user(login: $username) {
				projects: repositories(first: 50, after: $cursor) {
					pageInfo { hasNextPage endCursor }
					nodes {
						name nameWithOwner url descriptionHtml: descriptionHTML visibility
						defaultBranchRef { target { ... on Commit { committedDate abbreviatedOid oid url } } }
						project: object(expression: "HEAD:.project") {
							... on Tree { entries { name type object { ... on Blob { text } } } }
						}
					}
				}
			}
		}`
	type repository struct {
		Name             string `json:"name"`
		NameWithOwner    string `json:"nameWithOwner"`
		URL              string `json:"url"`
		DescriptionHTML  string `json:"descriptionHtml"`
		Visibility       string `json:"visibility"`
		DefaultBranchRef struct {
			Target struct {
				CommittedDate  time.Time `json:"committedDate"`
				AbbreviatedOID string    `json:"abbreviatedOid"`
				OID            string    `json:"oid"`
				URL            string    `json:"url"`
			} `json:"target"`
		} `json:"defaultBranchRef"`
		Project struct {
			Entries []projectEntry `json:"entries"`
		} `json:"project"`
	}

	var projects []Project
	var cursor any
	previousCursor := ""
	for {
		var response struct {
			Data struct {
				User struct {
					Projects struct {
						Nodes    []repository `json:"nodes"`
						PageInfo struct {
							HasNextPage bool   `json:"hasNextPage"`
							EndCursor   string `json:"endCursor"`
						} `json:"pageInfo"`
					} `json:"projects"`
				} `json:"user"`
			} `json:"data"`
		}
		request := graphQLRequest{Query: query, Variables: map[string]any{"username": c.config.Username, "cursor": cursor}}
		if err := c.request(ctx, c.config.GitHubEndpoint, c.config.GitHubToken, request, &response); err != nil {
			return nil, err
		}
		for _, raw := range response.Data.User.Projects.Nodes {
			if !strings.EqualFold(raw.Visibility, "public") {
				continue
			}
			project := newProject(raw.Name, raw.URL, raw.DescriptionHTML, "")
			if err := applyProjectFiles(&project, raw.NameWithOwner, raw.DefaultBranchRef.Target.OID, raw.Project.Entries); err != nil {
				return nil, fmt.Errorf("read metadata for %s: %w", raw.NameWithOwner, err)
			}
			if !project.HasAvatar {
				avatarURL, err := identiconURL(raw.NameWithOwner)
				if err != nil {
					return nil, fmt.Errorf("generate identicon for %s: %w", raw.NameWithOwner, err)
				}
				project.AvatarURL = avatarURL
				project.HasAvatar = true
			}
			project.LastCommitDate = raw.DefaultBranchRef.Target.CommittedDate
			project.LastCommitHash = raw.DefaultBranchRef.Target.AbbreviatedOID
			project.LastCommitURL = raw.DefaultBranchRef.Target.URL
			projects = append(projects, project)
		}
		if !response.Data.User.Projects.PageInfo.HasNextPage {
			break
		}
		nextCursor := response.Data.User.Projects.PageInfo.EndCursor
		if nextCursor == "" || nextCursor == previousCursor {
			return nil, errors.New("GitHub pagination returned no new cursor")
		}
		previousCursor = nextCursor
		cursor = nextCursor
	}
	sort.SliceStable(projects, func(i, j int) bool {
		return projects[i].LastCommitDate.After(projects[j].LastCommitDate)
	})
	return projects, nil
}

type projectMetadata struct {
	Name        string   `yaml:"name"`
	Description string   `yaml:"description"`
	Topics      []string `yaml:"topics"`
	Homepage    string   `yaml:"homepage"`
	Source      struct {
		Provider  string `yaml:"provider"`
		Namespace string `yaml:"namespace"`
		Path      string `yaml:"path"`
	} `yaml:"source"`
}

func applyProjectFiles(project *Project, nameWithOwner, commitOID string, entries []projectEntry) error {
	if project.Name == "" || project.DescriptionHTML == "" {
		for _, entry := range entries {
			if entry.Name != "project.yaml" || entry.Object.Text == nil {
				continue
			}
			var metadata projectMetadata
			decoder := yaml.NewDecoder(strings.NewReader(*entry.Object.Text))
			decoder.KnownFields(true)
			if err := decoder.Decode(&metadata); err != nil {
				return fmt.Errorf("invalid .project/project.yaml: %w", err)
			}
			if err := decoder.Decode(&struct{}{}); err != io.EOF {
				if err == nil {
					err = errors.New("multiple YAML documents are not allowed")
				}
				return fmt.Errorf("invalid .project/project.yaml: %w", err)
			}
			if project.Name == "" && metadata.Name != "" {
				project.Name = metadata.Name
				project.FirstLetter = firstLetter(metadata.Name)
			}
			if project.DescriptionHTML == "" && metadata.Description != "" {
				project.DescriptionHTML = html.EscapeString(metadata.Description)
			}
			break
		}
	}
	for _, entry := range entries {
		if entry.Type == "blob" && strings.HasPrefix(entry.Name, "image.") && commitOID != "" {
			owner, repository, ok := strings.Cut(nameWithOwner, "/")
			if !ok || owner == "" || repository == "" || strings.Contains(repository, "/") {
				return errors.New("invalid GitHub repository name")
			}
			project.AvatarURL = fmt.Sprintf("https://raw.githubusercontent.com/%s/%s/%s/.project/%s",
				url.PathEscape(owner), url.PathEscape(repository), url.PathEscape(commitOID), url.PathEscape(entry.Name))
			project.HasAvatar = true
			break
		}
	}
	return nil
}

func identiconURL(seed string) (string, error) {
	var data bytes.Buffer
	if err := png.Encode(&data, identicon.S2(128).Make([]byte(seed))); err != nil {
		return "", err
	}
	return "data:image/png;base64," + base64.StdEncoding.EncodeToString(data.Bytes()), nil
}

func newProject(name, url, descriptionHTML, avatarURL string) Project {
	return Project{
		Name:            name,
		URL:             url,
		DescriptionHTML: descriptionHTML,
		AvatarURL:       avatarURL,
		FirstLetter:     firstLetter(name),
		HSLColor:        randomColor(),
		HasAvatar:       avatarURL != "",
	}
}

func firstLetter(name string) string {
	if r, _ := utf8.DecodeRuneInString(name); r != utf8.RuneError || name != "" {
		return string(unicode.ToUpper(r))
	}
	return ""
}

func randomColor() string {
	var value [8]byte
	if _, err := rand.Read(value[:]); err != nil {
		panic(fmt.Sprintf("read random project color: %v", err))
	}
	n := binary.LittleEndian.Uint64(value[:])
	return fmt.Sprintf("hsl(%d, %d%%, %d%%)", n%360, 70+(n/360)%30, 40+(n/10800)%20)
}

// Fetcher is the data source used by Store.Refresh.
type Fetcher interface {
	Fetch(context.Context) (Cache, error)
}

// Store owns a concurrent in-memory cache and its JSON file.
type Store struct {
	mu      sync.RWMutex
	update  sync.Mutex
	path    string
	fetcher Fetcher
	cache   Cache
}

func NewStore(path string, fetcher Fetcher) *Store {
	return &Store{path: path, fetcher: fetcher}
}

// Load replaces the in-memory cache with the cache file contents.
func (s *Store) Load() error {
	s.update.Lock()
	defer s.update.Unlock()

	file, err := os.Open(s.path)
	if err != nil {
		return fmt.Errorf("open projects cache: %w", err)
	}
	defer file.Close()

	var cache Cache
	decoder := json.NewDecoder(io.LimitReader(file, maxResponseSize+1))
	if err := decoder.Decode(&cache); err != nil {
		return fmt.Errorf("decode projects cache: %w", err)
	}
	if cache.Version != cacheVersion || cache.Source != cacheSource || cache.RefreshedAt.IsZero() {
		return errors.New("projects cache uses an obsolete format")
	}

	s.mu.Lock()
	s.cache = cloneCache(cache)
	s.mu.Unlock()
	return nil
}

// Stale reports whether the current cache must be refreshed.
func (s *Store) Stale(now time.Time, maxAge time.Duration) bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.cache.RefreshedAt.IsZero() || now.Sub(s.cache.RefreshedAt) >= maxAge
}

// Get returns a snapshot that callers can modify safely.
func (s *Store) Get() Cache {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return cloneCache(s.cache)
}

// Refresh fetches, persists, and publishes one complete cache update.
func (s *Store) Refresh(ctx context.Context) error {
	s.update.Lock()
	defer s.update.Unlock()
	if s.fetcher == nil {
		return errors.New("projects fetcher is not set")
	}

	cache, err := s.fetcher.Fetch(ctx)
	if err != nil {
		return err
	}
	cache.Version = cacheVersion
	cache.Source = cacheSource
	if cache.RefreshedAt.IsZero() {
		cache.RefreshedAt = time.Now().UTC()
	}
	s.mu.RLock()
	preserveColors(&cache, s.cache)
	s.mu.RUnlock()

	if err := writeCache(s.path, cache); err != nil {
		return err
	}
	s.mu.Lock()
	s.cache = cloneCache(cache)
	s.mu.Unlock()
	return nil
}

func preserveColors(next *Cache, current Cache) {
	preserve := func(projects []Project, old []Project) {
		colors := make(map[string]string, len(old))
		for _, project := range old {
			colors[project.URL] = project.HSLColor
		}
		for i := range projects {
			if color, ok := colors[projects[i].URL]; ok {
				projects[i].HSLColor = color
			}
		}
	}
	preserve(next.Projects, current.Projects)
}

func writeCache(path string, cache Cache) error {
	dir := filepath.Dir(path)
	temp, err := os.CreateTemp(dir, ".projects-cache-*")
	if err != nil {
		return fmt.Errorf("create temporary projects cache: %w", err)
	}
	tempName := temp.Name()
	defer os.Remove(tempName)

	encoder := json.NewEncoder(temp)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(cache); err != nil {
		temp.Close()
		return fmt.Errorf("encode projects cache: %w", err)
	}
	if err := temp.Sync(); err != nil {
		temp.Close()
		return fmt.Errorf("sync projects cache: %w", err)
	}
	if err := temp.Close(); err != nil {
		return fmt.Errorf("close projects cache: %w", err)
	}
	if err := os.Rename(tempName, path); err != nil {
		return fmt.Errorf("replace projects cache: %w", err)
	}
	directory, err := os.Open(dir)
	if err != nil {
		return fmt.Errorf("open projects cache directory: %w", err)
	}
	defer directory.Close()
	if err := directory.Sync(); err != nil {
		return fmt.Errorf("sync projects cache directory: %w", err)
	}
	return nil
}

func cloneCache(cache Cache) Cache {
	return Cache{
		Version: cache.Version, Source: cache.Source, RefreshedAt: cache.RefreshedAt,
		Projects: append([]Project(nil), cache.Projects...),
	}
}
