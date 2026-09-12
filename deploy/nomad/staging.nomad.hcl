variable "image" {
  type        = string
  description = "Immutable GHCR image reference"

  validation {
    condition     = strlen(var.image) == 101 && substr(var.image, 0, 37) == "ghcr.io/sachahjkl/sacha.house@sha256:"
    error_message = "The image must use the sacha.house GHCR repository and an exact SHA-256 digest."
  }
}

job "sacha-house" {
  namespace   = "staging"
  datacenters = ["homelab"]
  type        = "service"

  meta {
    image = var.image
  }

  group "web" {
    count = 1

    update {
      max_parallel      = 1
      health_check      = "checks"
      min_healthy_time  = "10s"
      healthy_deadline  = "2m"
      progress_deadline = "5m"
      auto_revert       = true
    }

    restart {
      attempts = 3
      interval = "10m"
      delay    = "15s"
      mode     = "fail"
    }

    reschedule {
      attempts       = 3
      interval       = "1h"
      delay          = "30s"
      delay_function = "exponential"
      max_delay      = "5m"
      unlimited      = false
    }

    network {
      mode = "host"

      port "http" {
        static       = 9071
        to           = 6969
        host_network = "loopback"
      }
    }

    volume "data" {
      type            = "host"
      source          = "sacha-house-staging-data"
      attachment_mode = "file-system"
      access_mode     = "single-node-writer"
      sticky          = true
    }

    task "web" {
      driver = "docker"

      config {
        image        = var.image
        network_mode = "services"
        ports        = ["http"]
      }

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
  "WEBAUTHN_RP_ID": "staging.sacha.house",
  "WEBAUTHN_RP_ORIGINS": ["https://staging.sacha.house"],
  "TRUST_PROXY_HTTPS": true,
  "PASTE_ENABLED": false,
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

      volume_mount {
        volume      = "data"
        destination = "/data"
      }

      service {
        name     = "sacha-house-staging"
        provider = "nomad"
        port     = "http"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.sacha-house-staging.entrypoints=nomad",
          "traefik.http.routers.sacha-house-staging.middlewares=sacha-house-staging-noindex",
          "traefik.http.routers.sacha-house-staging.rule=Host(`staging.sacha.house`)",
          "traefik.http.routers.sacha-house-staging.tls.domains[0].main=staging.sacha.house",
          "traefik.http.middlewares.sacha-house-staging-noindex.headers.customresponseheaders.X-Robots-Tag=noindex, nofollow",
        ]

        check {
          name     = "HTTP health"
          type     = "http"
          path     = "/ping"
          interval = "10s"
          timeout  = "2s"

          check_restart {
            limit           = 3
            grace           = "30s"
            ignore_warnings = false
          }
        }
      }

      resources {
        cpu    = 300
        memory = 256
      }

      logs {
        max_files     = 5
        max_file_size = 10
      }

      kill_timeout = "20s"
    }
  }
}
