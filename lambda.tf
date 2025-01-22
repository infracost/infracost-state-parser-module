locals {
  image_arn = "237144093413.dkr.ecr.us-east-2.amazonaws.com/infracost/state-parser"
}

resource "aws_lambda_function" "state_file_parser" {
  function_name = "infracost-state-file-parser"
  description   = "Lambda function to parse state files to send to Infracost"
  role          = aws_iam_role.state_file_parser.arn
  handler       = "main"
  runtime       = "provided.al2"
  package_type  = "Image"
  architectures = ["arm64"]
  timeout       = 60
  memory_size   = 128

  image_uri = "${local.image_arn}:${var.parser_version}"

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
  schedule_expression = "cron(0 * ? * * *)" // Run every hour
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.infracost_state_scrape_schedule.name
  target_id = "lambda"
  arn       = aws_lambda_function.state_file_parser.arn
}
