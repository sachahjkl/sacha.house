namespace "production" {
  capabilities = ["list-jobs", "parse-job", "read-job", "submit-job"]
}

host_volume "sacha-house-production-data" {
  policy = "write"
}
