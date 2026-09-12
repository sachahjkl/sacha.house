    task "backup" {
      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      driver = "docker"

      config {
        image        = "ghcr.io/sachahjkl/sacha.house@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
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
