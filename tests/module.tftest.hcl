provider "aws" {
  region                      = "us-east-2"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_region_validation      = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

override_data {
  target = data.aws_region.current
  values = { region = "us-east-2" }
}

override_data {
  target = data.aws_caller_identity.current
  values = { account_id = "123456789012" }
}

variables {
  organization_id = "3f9fa4c5-e856-4312-8423-3c8380f3f05e"
  state_files     = ["s3://customer-tfstate/env/prod/*.tfstate"]
}

run "minimal_default_contract" {
  command = plan

  assert {
    condition     = aws_cloudwatch_event_rule.infracost_state_scrape_schedule.schedule_expression == "rate(1 hour)"
    error_message = "The default PT1H period must schedule an hourly run."
  }

  assert {
    condition     = aws_lambda_function.state_file_parser.environment[0].variables.EXPECTED_INTERVAL_SECONDS == "3600"
    error_message = "Parser freshness metadata must derive from the same ISO 8601 period."
  }

  assert {
    condition     = aws_lambda_function.state_file_parser.environment[0].variables.STATE_FILE_PATTERNS_JSON == jsonencode(var.state_files)
    error_message = "The parser must receive an unambiguous JSON source-pattern list."
  }

  assert {
    condition = (
      aws_lambda_function.state_file_parser.image_uri == "237144093413.dkr.ecr.us-east-2.amazonaws.com/infracost/state-parser:0.4.0" &&
      !contains(keys(aws_lambda_function.state_file_parser.environment[0].variables), "PARSER_AUTO_UPDATE") &&
      !strcontains(data.aws_iam_policy_document.state_file_access.json, "lambda:UpdateFunctionCode")
    )
    error_message = "The module must use its paired versioned parser release without self-update configuration or permissions."
  }

  assert {
    condition = (
      strcontains(data.aws_iam_policy_document.state_file_access.json, "ecr:BatchGetImage") &&
      strcontains(data.aws_iam_policy_document.state_file_access.json, "ecr:GetDownloadUrlForLayer")
    )
    error_message = "The existing cross-account ECR image permissions must be preserved."
  }

  assert {
    condition     = aws_lambda_function.state_file_parser.timeout == 900 && aws_lambda_function.state_file_parser.memory_size == 512
    error_message = "The fixed runtime must accommodate the existing 100 MiB state-file contract."
  }

  assert {
    condition     = aws_lambda_function.state_file_parser.reserved_concurrent_executions == 1
    error_message = "Executions must not race the account's single report object."
  }

  assert {
    condition = length([
      for statement in jsondecode(data.aws_iam_policy_document.state_file_access.json).Statement : statement
      if try(statement.Sid == "WriteSanitizedReports", false) &&
      try(statement.Action == "s3:PutObject", false) &&
      try(statement.Resource == "arn:aws:s3:::infracost-incoming/3f9fa4c5-e856-4312-8423-3c8380f3f05e/aws_account_id=123456789012/terraform-state-resources.json", false)
    ]) == 1
    error_message = "The parser may write only the reporting account's single sanitized report object."
  }

  assert {
    condition     = !contains(keys(aws_lambda_function.state_file_parser.environment[0].variables), "DEPLOYMENT_ID")
    error_message = "The single-object parser contract must not expose deployment/run hierarchy configuration."
  }

  assert {
    condition = length([
      for statement in jsondecode(data.aws_iam_policy_document.state_file_access.json).Statement : statement
      if try(statement.Sid == "WriteLogs", false) &&
      toset(try(tolist(statement.Action), [statement.Action])) == toset(["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]) &&
      try(statement.Resource == "arn:aws:logs:*:*:*", false)
    ]) == 1
    error_message = "The Lambda role must retain permissions to create its CloudWatch log group and streams and publish log events."
  }
}

run "explicit_state_files_disable_default_discovery" {
  command = plan

  assert {
    condition     = aws_lambda_function.state_file_parser.environment[0].variables.DEFAULT_BUCKET_DISCOVERY == "false"
    error_message = "Configured state files must switch off default bucket discovery."
  }

  assert {
    condition     = !strcontains(data.aws_iam_policy_document.state_file_access.json, "DefaultDiscovery")
    error_message = "Configured state files must not receive default-discovery permissions."
  }
}

run "omitted_state_files_enable_default_discovery" {
  command = plan

  variables { state_files = [] }

  assert {
    condition     = aws_lambda_function.state_file_parser.environment[0].variables.DEFAULT_BUCKET_DISCOVERY == "true"
    error_message = "Omitted state files must enable default bucket discovery."
  }

  assert {
    condition     = strcontains(data.aws_iam_policy_document.state_file_access.json, "s3:ListAllMyBuckets")
    error_message = "Default discovery requires bucket listing."
  }

  assert {
    condition = length([
      for statement in jsondecode(data.aws_iam_policy_document.state_file_access.json).Statement : statement
      if try(statement.Sid == "DefaultDiscoveryReadStateObjects", false) &&
      try(statement.Action == "s3:GetObject", false) &&
      alltrue([for resource in try(tolist(statement.Resource), [statement.Resource]) : endswith(resource, "/*.tfstate")])
    ]) == 1
    error_message = "Default discovery reads must be bounded to *.tfstate objects in state-named buckets."
  }

  assert {
    condition     = !strcontains(data.aws_iam_policy_document.state_file_access.json, "ReadConfiguredStateObjects")
    error_message = "No configured-object permissions should exist without configured state files."
  }
}

run "iso_periods_map_to_eventbridge_rates" {
  command = plan

  variables { schedule_period = "PT30M" }

  assert {
    condition     = aws_cloudwatch_event_rule.infracost_state_scrape_schedule.schedule_expression == "rate(30 minutes)"
    error_message = "PT30M must retain minute precision."
  }

  assert {
    condition     = aws_lambda_function.state_file_parser.environment[0].variables.EXPECTED_INTERVAL_SECONDS == "1800"
    error_message = "PT30M freshness must be 1800 seconds."
  }
}

run "day_period_maps_to_eventbridge_rate" {
  command = plan

  variables { schedule_period = "P2D" }

  assert {
    condition     = aws_cloudwatch_event_rule.infracost_state_scrape_schedule.schedule_expression == "rate(2 days)"
    error_message = "P2D must map to a two-day rate."
  }
}

run "invalid_period_is_rejected" {
  command = plan

  variables { schedule_period = "every hour" }

  expect_failures = [var.schedule_period]
}

run "period_below_parser_bound_is_rejected" {
  command = plan

  variables { schedule_period = "PT9M" }

  expect_failures = [var.schedule_period]
}

run "period_above_parser_bound_is_rejected" {
  command = plan

  variables { schedule_period = "P8D" }

  expect_failures = [var.schedule_period]
}

run "parser_period_boundaries_are_accepted" {
  command = plan

  variables { schedule_period = "P7D" }

  assert {
    condition     = aws_lambda_function.state_file_parser.environment[0].variables.EXPECTED_INTERVAL_SECONDS == "604800"
    error_message = "The parser's seven-day upper cadence bound must remain usable."
  }
}

run "exact_key_preserves_bucket_listing" {
  command = plan

  variables { state_files = ["s3://customer-tfstate/env/prod/main.tfstate"] }

  assert {
    condition     = strcontains(data.aws_iam_policy_document.state_file_access.json, "s3:ListBucket") && strcontains(data.aws_iam_policy_document.state_file_access.json, "arn:aws:s3:::customer-tfstate")
    error_message = "Exact paths must preserve the module's existing bucket-list permission and S3 missing-object behavior."
  }
}

run "bucket_and_key_globs_are_explicit_in_state_files" {
  command = plan

  variables { state_files = ["s3://*tfstate*/*foo*.tfstate"] }

  assert {
    condition     = strcontains(data.aws_iam_policy_document.state_file_access.json, "s3:ListAllMyBuckets")
    error_message = "A configured bucket glob requires bucket discovery without a second opt-in."
  }

  assert {
    condition     = strcontains(data.aws_iam_policy_document.state_file_access.json, "s3:ListBucket") && strcontains(data.aws_iam_policy_document.state_file_access.json, "s3:prefix")
    error_message = "A configured broad key glob must receive the listing permission it requires."
  }
}

run "wildcard_bucket_permissions_preserve_source_pairs" {
  command = plan

  variables {
    state_files = [
      "s3://prod-*tfstate/secret/*.tfstate",
      "s3://dev-*tfstate/other/*.tfstate",
    ]
  }

  assert {
    condition = length([
      for statement in jsondecode(data.aws_iam_policy_document.state_file_access.json).Statement : statement
      if try(statement.Action == "s3:ListBucket", false) &&
      try(statement.Resource == "arn:aws:s3:::prod-*tfstate", false) &&
      try(statement.Condition.StringLike["s3:prefix"] == "secret/*", false)
    ]) == 1
    error_message = "Wildcard-bucket IAM must preserve each configured bucket/prefix pair."
  }
}

run "kms_permissions_are_explicit" {
  command = plan

  variables {
    state_kms_key_arns = ["arn:aws:kms:us-east-2:123456789012:key/12345678-1234-1234-1234-123456789012"]
  }

  assert {
    condition     = strcontains(data.aws_iam_policy_document.state_file_access.json, "arn:aws:kms:us-east-2:123456789012:key/12345678-1234-1234-1234-123456789012")
    error_message = "Only explicitly configured KMS key ARNs should be granted."
  }
}

run "kms_wildcards_are_rejected" {
  command = plan

  variables {
    state_kms_key_arns = ["arn:aws:kms:*:123456789012:key/12345678-1234-1234-1234-123456789012"]
  }

  expect_failures = [var.state_kms_key_arns]
}

run "iam_interpolation_inputs_reject_wildcards" {
  command = plan

  variables {
    organization_id = "*"
    state_bucket    = "incoming-*"
  }

  expect_failures = [var.organization_id, var.state_bucket]
}
