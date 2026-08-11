provider "aws" {
  region                      = "eu-south-2"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_region_validation      = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

override_data {
  target = data.aws_region.current
  values = { id = "eu-south-2" }
}

override_data {
  target = data.aws_caller_identity.current
  values = { account_id = "123456789012" }
}

variables {
  organization_id = "3f9fa4c5-e856-4312-8423-3c8380f3f05e"
  state_files     = ["s3://customer-tfstate/env/prod/*.tfstate"]
}

run "managed_image_remains_region_limited" {
  command = plan

  expect_failures = [aws_lambda_function.state_file_parser]
}

run "customer_image_bypasses_only_managed_region_limit" {
  command = plan

  variables {
    parser_image_uri = "123456789012.dkr.ecr.eu-south-2.amazonaws.com/state-parser:v0.2.4"
  }

  assert {
    condition     = aws_lambda_function.state_file_parser.image_uri == var.parser_image_uri
    error_message = "Customer images must be usable outside the managed-image replication regions."
  }
}
