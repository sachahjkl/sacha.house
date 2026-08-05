package projects

import (
	"context"
	"crypto/rand"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"unicode"
	"unicode/utf8"
)

const maxResponseSize = 8 << 20

// Project keeps the field names used by projects_cache.json and the templates.
type Project struct {
	Name            string `json:"name"`
	URL             string `json:"url"`
	DescriptionHTML string `json:"descriptionHtml"`
	AvatarURL       string `json:"avatarUrl"`
	FirstLetter     string `json:"first_letter"`
	HSLColor        string `json:"hslColor"`
	HasAvatar       bool   `json:"hasAvatar"`
}

// Cache is the on-disk projects_cache.json format.
type Cache struct {
	GitLab []Project `json:"gitlab"`
	GitHub []Project `json:"github"`
}

type ClientConfig struct {
	GitLabEndpoint string
	GitHubEndpoint string
	GitLabToken    string
	GitHubToken    string
	Username       string
}

// Client fetches projects from the GitLab and GitHub GraphQL APIs.
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
	gitlab, err := c.fetchGitLab(ctx)
	if err != nil {
		return Cache{}, fmt.Errorf("fetch GitLab projects: %w", err)
	}

	github, err := c.fetchGitHub(ctx)
	if err != nil {
		return Cache{}, fmt.Errorf("fetch GitHub projects: %w", err)
	}

	return Cache{GitLab: gitlab, GitHub: github}, nil
}

type graphQLRequest struct {
	Query     string            `json:"query"`
	Variables map[string]string `json:"variables"`
}

type graphQLError struct {
	Message string `json:"message"`
}

func (c *Client) request(ctx context.Context, endpoint, token string, request graphQLRequest, response any) error {
	if endpoint == "" {
		return errors.New("GraphQL endpoint is not set")
	}
	if token == "" {
		return errors.New("bearer token is not set")
	}

	var body strings.Builder
	if err := json.NewEncoder(&body).Encode(request); err != nil {
		return fmt.Errorf("encode GraphQL request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, strings.NewReader(body.String()))
	if err != nil {
		return fmt.Errorf("create GraphQL request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")

	res, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("send GraphQL request: %w", err)
	}
	defer res.Body.Close()

	limited := io.LimitReader(res.Body, maxResponseSize+1)
	data, err := io.ReadAll(limited)
	if err != nil {
		return fmt.Errorf("read GraphQL response: %w", err)
	}
	if len(data) > maxResponseSize {
		return errors.New("GraphQL response exceeds 8 MiB")
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

func (c *Client) fetchGitLab(ctx context.Context) ([]Project, error) {
	var response struct {
		Data struct {
			Projects struct {
				Nodes []struct {
					Name            string `json:"name"`
					URL             string `json:"url"`
					DescriptionHTML string `json:"descriptionHtml"`
					AvatarURL       string `json:"avatarUrl"`
					Visibility      string `json:"visibility"`
				} `json:"nodes"`
			} `json:"projects"`
		} `json:"data"`
	}

	request := graphQLRequest{
		Query: `query GET_PROJECTS_GITLAB($username: ID!) {
			projects(namespacePath: $username) {
				nodes { name url: webUrl avatarUrl description descriptionHtml visibility }
			}
		}`,
		Variables: map[string]string{"username": c.config.Username},
	}
	if err := c.request(ctx, c.config.GitLabEndpoint, c.config.GitLabToken, request, &response); err != nil {
		return nil, err
	}

	projects := make([]Project, 0, len(response.Data.Projects.Nodes))
	for _, raw := range response.Data.Projects.Nodes {
		if !strings.EqualFold(raw.Visibility, "public") {
			continue
		}
		projects = append(projects, newProject(raw.Name, raw.URL, raw.DescriptionHTML, raw.AvatarURL))
	}
	return projects, nil
}

func (c *Client) fetchGitHub(ctx context.Context) ([]Project, error) {
	var response struct {
		Data struct {
			User struct {
				Projects struct {
					Nodes []struct {
						Name            string `json:"name"`
						URL             string `json:"url"`
						DescriptionHTML string `json:"descriptionHtml"`
						Visibility      string `json:"visibility"`
						Owner           struct {
							AvatarURL string `json:"avatarUrl"`
						} `json:"owner"`
					} `json:"nodes"`
				} `json:"projects"`
			} `json:"user"`
		} `json:"data"`
	}

	request := graphQLRequest{
		Query: `query GET_PROJECTS_GITHUB($username: String!) {
			user(login: $username) {
				projects: repositories(first: 50) {
					nodes { name url description descriptionHtml: descriptionHTML visibility owner { avatarUrl } }
				}
			}
		}`,
		Variables: map[string]string{"username": c.config.Username},
	}
	if err := c.request(ctx, c.config.GitHubEndpoint, c.config.GitHubToken, request, &response); err != nil {
		return nil, err
	}

	projects := make([]Project, 0, len(response.Data.User.Projects.Nodes))
	for _, raw := range response.Data.User.Projects.Nodes {
		if !strings.EqualFold(raw.Visibility, "public") {
			continue
		}
		projects = append(projects, newProject(raw.Name, raw.URL, raw.DescriptionHTML, raw.Owner.AvatarURL))
	}
	for left, right := 0, len(projects)-1; left < right; left, right = left+1, right-1 {
		projects[left], projects[right] = projects[right], projects[left]
	}
	return projects, nil
}

func newProject(name, url, descriptionHTML, avatarURL string) Project {
	first := ""
	if r, _ := utf8.DecodeRuneInString(name); r != utf8.RuneError || name != "" {
		first = string(unicode.ToUpper(r))
	}
	return Project{
		Name:            name,
		URL:             url,
		DescriptionHTML: descriptionHTML,
		AvatarURL:       avatarURL,
		FirstLetter:     first,
		HSLColor:        randomColor(),
		HasAvatar:       avatarURL != "",
	}
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

	s.mu.Lock()
	s.cache = cloneCache(cache)
	s.mu.Unlock()
	return nil
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
	preserve(next.GitLab, current.GitLab)
	preserve(next.GitHub, current.GitHub)
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
		GitLab: append([]Project(nil), cache.GitLab...),
		GitHub: append([]Project(nil), cache.GitHub...),
	}
}
