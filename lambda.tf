locals {
  image_arn = "237144093413.dkr.ecr.us-east-2.amazonaws.com/infracost/state-parser:latest"
}

resource "aws_lambda_function" "state_file_parser" {
  function_name = "InfracostStateFileParser"
  description   = "Lambda function to parse state files to send to Infracost"
  role          = aws_iam_role.state_file_parser.arn
  handler       = "main"
  runtime       = "provided.al2"
  timeout       = 60
  memory_size   = 128

  image_uri        = local.image_arn
  source_code_hash = data.aws_s3_object.lambda_source.checksum_sha1

  environment {
    variables = {
      ORGANIZATION_ID        = var.organization_id
      STATE_FILES            = join(",", var.state_files)
      INFRACOST_STATE_BUCKET = var.state_bucket
      LOG_LEVEL              = var.log_level
    }
  }
}

resource "aws_cloudwatch_event_rule" "infracost_state_scrape_schedule" {
  name                = "infracost_state_scrape_schedule"
  schedule_expression = "rate(24 hour)"
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.infracost_state_scrape_schedule.name
  target_id = "lambda"
  arn       = aws_lambda_function.state_file_parser.arn
}
