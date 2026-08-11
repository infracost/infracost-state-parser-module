resource "aws_lambda_function" "state_file_parser" {
  function_name = local.function_name
  description   = "Extracts an allowlisted, sanitized inventory from Terraform state"
  role          = aws_iam_role.state_file_parser.arn
  package_type  = "Image"
  architectures = ["arm64"]
  timeout       = 900
  memory_size   = 512

  # One writer prevents overlapping scheduled/manual executions from racing
  # the account's single report object.
  reserved_concurrent_executions = 1

  image_uri = local.image_ref

  dynamic "vpc_config" {
    for_each = var.vpc_config == null ? [] : [var.vpc_config]
    content {
      subnet_ids         = sort(tolist(vpc_config.value.subnet_ids))
      security_group_ids = sort(tolist(vpc_config.value.security_group_ids))
    }
  }

  environment {
    variables = {
      ORGANIZATION_ID               = var.organization_id
      STATE_FILE_PATTERNS_JSON      = jsonencode(var.state_files)
      DEFAULT_BUCKET_DISCOVERY      = local.default_discovery ? "true" : "false"
      INFRACOST_STATE_BUCKET        = var.state_bucket
      INFRACOST_STATE_BUCKET_REGION = var.state_bucket_region
      INFRACOST_STATE_BUCKET_PREFIX = var.state_bucket_prefix
      LOG_LEVEL                     = lower(var.log_level)
      EXPECTED_INTERVAL_SECONDS     = tostring(local.expected_interval_seconds)
      ALLOW_BUCKET_WILDCARDS        = "true"
      ALLOW_BROAD_KEY_WILDCARDS     = "true"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.state_file_access_policy_attachement,
    aws_iam_role_policy.vpc_access,
  ]

  lifecycle {
    precondition {
      condition     = !local.managed_image || contains(local.supported_image_regions, data.aws_region.current.id)
      error_message = "The Infracost state-parser image is not replicated to this AWS region. Deploy in one of: ${join(", ", sort(tolist(local.supported_image_regions)))}."
    }
  }
}

resource "aws_cloudwatch_event_rule" "infracost_state_scrape_schedule" {
  name                = "infracost_state_scrape_schedule"
  schedule_expression = local.schedule_expression
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.infracost_state_scrape_schedule.name
  target_id = "lambda"
  arn       = aws_lambda_function.state_file_parser.arn
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.state_file_parser.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.infracost_state_scrape_schedule.arn
}
