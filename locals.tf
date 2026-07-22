data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  parsed_state_files = [
    for url in var.state_files : {
      url                 = url
      bucket              = regex("^s3://([^/]+)/(.+)$", url)[0]
      key_pattern         = regex("^s3://[^/]+/(.+)$", url)[0]
      bucket_has_wildcard = length(regexall("[*?]", regex("^s3://([^/]+)/(.+)$", url)[0])) > 0
      key_has_wildcard    = length(regexall("[*?]", regex("^s3://[^/]+/(.+)$", url)[0])) > 0
      literal_key_prefix  = replace(regex("^s3://[^/]+/(.+)$", url)[0], "/[*?].*$/", "")
    }
  ]

  exact_bucket_sources    = [for source in local.parsed_state_files : source if !source.bucket_has_wildcard]
  wildcard_bucket_sources = [for source in local.parsed_state_files : source if source.bucket_has_wildcard]
  exact_buckets           = toset([for source in local.exact_bucket_sources : source.bucket])
  wildcard_key_sources    = [for source in local.exact_bucket_sources : source if source.key_has_wildcard]
  list_buckets = {
    for bucket in toset([for source in local.wildcard_key_sources : source.bucket]) : bucket => [
      for source in local.wildcard_key_sources : source if source.bucket == bucket
    ]
  }

  period_days    = try(tonumber(regex("^P([1-9][0-9]*)D$", var.schedule_period)[0]), 0)
  period_hours   = try(tonumber(regex("^PT([1-9][0-9]*)H$", var.schedule_period)[0]), 0)
  period_minutes = try(tonumber(regex("^PT([1-9][0-9]*)M$", var.schedule_period)[0]), 0)
  schedule_expression = local.period_days > 0 ? "rate(${local.period_days} ${local.period_days == 1 ? "day" : "days"})" : (
    local.period_hours > 0 ? "rate(${local.period_hours} ${local.period_hours == 1 ? "hour" : "hours"})" :
    "rate(${local.period_minutes} ${local.period_minutes == 1 ? "minute" : "minutes"})"
  )
  expected_interval_seconds = (local.period_days * 86400) + (local.period_hours * 3600) + (local.period_minutes * 60)

  function_name  = "infracost-state-file-parser"
  image_uri      = "237144093413.dkr.ecr.${data.aws_region.current.region}.amazonaws.com/infracost/state-parser"
  parser_version = "0.2.0"
  image_ref      = "${local.image_uri}:${local.parser_version}"

  supported_image_regions = toset([
    "eu-central-1",
    "eu-west-1",
    "eu-west-2",
    "us-east-1",
    "us-east-2",
    "us-west-2",
  ])
}
