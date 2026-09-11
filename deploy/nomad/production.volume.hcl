name      = "sacha-house-production-data"
namespace = "production"
type      = "host"
plugin_id = "mkdir"

capability {
  access_mode     = "single-node-writer"
  attachment_mode = "file-system"
}

parameters {
  mode = "0700"
  uid  = 65532
  gid  = 65532
}
