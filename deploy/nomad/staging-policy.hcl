namespace "staging" {
  capabilities = ["list-jobs", "parse-job", "read-job", "submit-job"]
}

host_volume "sacha-house-staging-data" {
  policy = "write"
}
