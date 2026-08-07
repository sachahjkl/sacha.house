package app

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strconv"

	"sacha.house/internal/paste"
)

const DefaultPort = 6969

// Config keeps the deployed JSON field names.
type Config struct {
	GitHubRESTAPIEndpoint    string   `json:"GITHUB_REST_API_ENDPOINT"`
	GitLabAPIEndpoint        string   `json:"GITLAB_API_ENDPOINT"`
	GitHubGraphQLAPIEndpoint string   `json:"GITHUB_GRAPHQL_API_ENDPOINT"`
	GitLabBearerToken        string   `json:"GITLAB_BEARER_TOKEN"`
	GitHubBearerToken        string   `json:"GITHUB_BEARER_TOKEN"`
	GitRepoID                string   `json:"GIT_REPO_ID"`
	AdminPasswordHash        string   `json:"ADMIN_PASSWORD_HASH"`
	AdminPasswordPepper      string   `json:"ADMIN_PASSWORD_PEPPER"`
	PasswordSalt             string   `json:"PASSWORD_SALT"`
	WebAuthnCredentialsFile  string   `json:"WEBAUTHN_CREDENTIALS_FILE"`
	WebAuthnRPID             string   `json:"WEBAUTHN_RP_ID"`
	WebAuthnRPOrigins        []string `json:"WEBAUTHN_RP_ORIGINS"`
	WebAuthnOrigin           string   `json:"WEBAUTHN_ORIGIN"`
	TrustProxyHTTPS          bool     `json:"TRUST_PROXY_HTTPS"`
	PasteEnabled             bool     `json:"PASTE_ENABLED"`
	PasteSecretsFile         string   `json:"PASTE_SECRETS_FILE"`
	PasteMaxBodyBytes        int      `json:"PASTE_MAX_BODY_BYTES"`
	PasteMaxListItems        int      `json:"PASTE_MAX_LIST_ITEMS"`
}

// configFile accepts known retired fields until the deployed config removes them.
type configFile struct {
	Config
	AdminIPs             json.RawMessage `json:"ADMIN_IPS"`
	HygraphAPIEndpoint   json.RawMessage `json:"HYGRAPH_API_ENDPOINT"`
	LinkedInGistID       json.RawMessage `json:"LINKEDIN_GIST_ID"`
	ProxyCurlAPIEndpoint json.RawMessage `json:"PROXYCURL_API_ENDPOINT"`
	ProxyCurlBearerToken json.RawMessage `json:"PROXYCURL_BEARER_TOKEN"`
}

func DefaultConfig() Config {
	return Config{
		GitHubRESTAPIEndpoint:    "https://api.github.com",
		GitLabAPIEndpoint:        "https://gitlab.com/api/graphql",
		GitHubGraphQLAPIEndpoint: "https://api.github.com/graphql",
		WebAuthnCredentialsFile:  "webauthn_credentials.json",
		PasteSecretsFile:         "paste-secrets.json",
		PasteMaxBodyBytes:        262144,
		PasteMaxListItems:        200,
	}
}

func ConfigPath() string {
	if path := os.Getenv("CONFIG_PATH"); path != "" {
		return path
	}
	return "config.json"
}

func Port() int {
	value := os.Getenv("PORT")
	if value == "" {
		return DefaultPort
	}
	port, err := strconv.Atoi(value)
	if err != nil || port < 1 || port > 65535 {
		return DefaultPort
	}
	return port
}

func LoadConfig(path string) (Config, error) {
	var decoded configFile
	file, err := os.Open(path)
	if err != nil {
		return Config{}, fmt.Errorf("open config: %w", err)
	}
	defer file.Close()
	decoder := json.NewDecoder(file)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&decoded); err != nil {
		return Config{}, fmt.Errorf("decode config: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return Config{}, fmt.Errorf("decode config: trailing JSON data")
	}
	applySecretEnvironment(&decoded.Config)
	return normalizeConfig(decoded.Config)
}

func applySecretEnvironment(config *Config) {
	overrides := []struct {
		name   string
		target *string
	}{
		{name: "GITLAB_BEARER_TOKEN", target: &config.GitLabBearerToken},
		{name: "GITHUB_BEARER_TOKEN", target: &config.GitHubBearerToken},
		{name: "ADMIN_PASSWORD_HASH", target: &config.AdminPasswordHash},
		{name: "ADMIN_PASSWORD_PEPPER", target: &config.AdminPasswordPepper},
		{name: "PASTE_SECRETS_FILE", target: &config.PasteSecretsFile},
	}
	for _, override := range overrides {
		if value, exists := os.LookupEnv(override.name); exists {
			*override.target = value
		}
	}
}

func normalizeConfig(config Config) (Config, error) {
	defaults := DefaultConfig()
	if config.GitHubRESTAPIEndpoint == "" {
		config.GitHubRESTAPIEndpoint = defaults.GitHubRESTAPIEndpoint
	}
	if config.GitLabAPIEndpoint == "" {
		config.GitLabAPIEndpoint = defaults.GitLabAPIEndpoint
	}
	if config.GitHubGraphQLAPIEndpoint == "" {
		config.GitHubGraphQLAPIEndpoint = defaults.GitHubGraphQLAPIEndpoint
	}
	if config.WebAuthnCredentialsFile == "" {
		config.WebAuthnCredentialsFile = defaults.WebAuthnCredentialsFile
	}
	if config.PasteSecretsFile == "" {
		config.PasteSecretsFile = defaults.PasteSecretsFile
	}
	if config.PasteMaxBodyBytes == 0 {
		config.PasteMaxBodyBytes = defaults.PasteMaxBodyBytes
	}
	if config.PasteMaxListItems == 0 {
		config.PasteMaxListItems = defaults.PasteMaxListItems
	}
	if config.AdminPasswordPepper == "" {
		config.AdminPasswordPepper = config.PasswordSalt
	}
	if config.PasswordSalt == "" {
		config.PasswordSalt = config.AdminPasswordPepper
	}
	if len(config.WebAuthnRPOrigins) == 0 && config.WebAuthnOrigin != "" {
		config.WebAuthnRPOrigins = []string{config.WebAuthnOrigin}
	}
	if config.PasteMaxBodyBytes < paste.MinBodyBytes || config.PasteMaxBodyBytes > paste.MaxBodyBytes ||
		config.PasteMaxListItems < paste.MinListItems || config.PasteMaxListItems > paste.MaxListItems {
		return Config{}, fmt.Errorf("paste limits are outside the allowed ranges")
	}
	return config, nil
}

func (config Config) adminPasswordPepper() string {
	if config.AdminPasswordPepper != "" {
		return config.AdminPasswordPepper
	}
	return config.PasswordSalt
}

func (config Config) PasswordPepper() string {
	return config.adminPasswordPepper()
}
