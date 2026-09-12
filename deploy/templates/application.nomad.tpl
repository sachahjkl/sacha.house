[[ if eq (var "environment" .) "staging" ]]
job "sacha-house" {
  namespace   = [[ var "environment" . | quote ]]
  datacenters = ["homelab"]
  type        = "service"

  meta {
    image = [[ var "image" . | quote ]]
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
        to = 6969
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
        image        = [[ var "image" . | quote ]]
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
  "WEBAUTHN_RP_ID": "[[ var "domain" . ]]",
  "WEBAUTHN_RP_ORIGINS": ["https://[[ var "domain" . ]]"],
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
          "traefik.http.routers.sacha-house-staging.entrypoints=websecure",
          "traefik.http.routers.sacha-house-staging.middlewares=sacha-house-staging-noindex",
          "traefik.http.routers.sacha-house-staging.rule=Host(`[[ var "domain" . ]]`)",
          "traefik.http.routers.sacha-house-staging.tls.domains[0].main=[[ var "domain" . ]]",
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
[[ else ]]
job "sacha-house" {
  namespace   = [[ var "environment" . | quote ]]
  datacenters = ["homelab"]
  type        = "service"

  meta {
    image = [[ var "image" . | quote ]]
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
        to = 6969
      }
    }

    volume "data" {
      type            = "host"
      source          = "sacha-house-production-data"
      attachment_mode = "file-system"
      access_mode     = "single-node-writer"
      sticky          = true
    }

    task "backup" {
      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      driver = "docker"

      config {
        image        = [[ var "image" . | quote ]]
        command      = "/bin/sh"
        args         = ["-ec", "test -d /data/data/blog; mkdir -p /data/backups; archive=/data/backups/pre-deploy-$NOMAD_ALLOC_ID.tar.gz; tar -czf $archive -C /data data projects_cache.json webauthn_credentials.json; test -s $archive"]
        network_mode = "services"
      }

      volume_mount {
        volume      = "data"
        destination = "/data"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }


    task "web" {
      driver = "docker"

      config {
        image        = [[ var "image" . | quote ]]
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
  "GIT_REPO_ID": "sachahjkl/[[ var "domain" . ]]",
  "WEBAUTHN_CREDENTIALS_FILE": "webauthn_credentials.json",
  "WEBAUTHN_RP_ID": "[[ var "domain" . ]]",
  "WEBAUTHN_RP_ORIGINS": ["https://[[ var "domain" . ]]"],
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

      volume_mount {
        volume      = "data"
        destination = "/data"
      }

      service {
        name     = "sacha-house-production"
        provider = "nomad"
        port     = "http"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.sacha-house-production.entrypoints=websecure",
          "traefik.http.routers.sacha-house-production.rule=Host(`[[ var "domain" . ]]`)",
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
[[ end ]]
