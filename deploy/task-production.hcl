      env {
        CONFIG_PATH = "/local/config.json"
        HOST        = "0.0.0.0"
        PORT        = "6969"
      }

      template {
        data = <<EOH
{
  "GITHUB_REST_API_ENDPOINT": "https://api.github.com",
  "GITHUB_GRAPHQL_API_ENDPOINT": "https://api.github.com/graphql",
  "GIT_REPO_ID": "sachahjkl/sacha.house",
  "WEBAUTHN_CREDENTIALS_FILE": "webauthn_credentials.json",
  "WEBAUTHN_RP_ID": "sacha.house",
  "WEBAUTHN_RP_ORIGINS": ["https://sacha.house"],
  "TRUST_PROXY_HTTPS": true,
  "PASTE_ENABLED": true,
  "PASTE_MAX_BODY_BYTES": 262144,
  "PASTE_MAX_LIST_ITEMS": 500
}
EOH

        destination = "local/config.json"
        change_mode = "restart"
      }

      template {
        data = <<EOH
{{ with nomadVar "nomad/jobs/sacha-house" }}
GITHUB_BEARER_TOKEN={{ .GITHUB_BEARER_TOKEN | toJSON }}
ADMIN_PASSWORD_HASH={{ .ADMIN_PASSWORD_HASH | toJSON }}
ADMIN_PASSWORD_PEPPER={{ .ADMIN_PASSWORD_PEPPER | toJSON }}
PASTE_SECRETS_FILE="/secrets/paste-secrets.json"
{{ end }}
EOH

        destination          = "secrets/runtime.env"
        env                  = true
        error_on_missing_key = true
        change_mode          = "restart"
      }

      template {
        data = <<EOH
{{ with nomadVar "nomad/jobs/sacha-house" }}{{ .PASTE_SECRETS_JSON }}{{ end }}
EOH

        destination          = "secrets/paste-secrets.json"
        error_on_missing_key = true
        change_mode          = "restart"
      }
