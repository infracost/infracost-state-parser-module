# Infracost State Parser Module

## Overview

This is a Terraform module to deploy a Lambda function that parses Infracost state files and sends the data to Infracost.

## Usage

```hcl
module "infracost_state_parser" {
  source = "github.com/infracost/infracost-state-parser-module?ref=v0.1.4"

  organization_id = "your_organization_id"

  state_files = [
    "s3://your_bucket/your_state_file.json",
    "s3://your_bucket/your_state_file2.json",
    "s3://your_other_bucket/your_state_file.json",
  ]
}

// the ARN of the Lambda function created by this module
// give this ARN to Infracost to enable state parsing
output "infracost_state_parser_lambda_role_arn" {
  value = module.infracost_state_parser.iam_role_arn
}
```

### Optional Variables

- `log_level` (default: `INFO`): The log level for the Lambda function. Valid values are `DEBUG`, `INFO`, `WARN`, or `ERROR`.
