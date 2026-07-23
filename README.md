# Infracost Statefile Parser Module

This gives Infracost the ability to improve our algorithm that maps cloud resources to IaC code. The parser is a Lambda function that is deployed in your AWS accounts that contain your Terraform Statefiles so it can extract certain non-sensitive/non-secret attributes to send to Infracost periodically.

## Prerequisites
- You have an AWS account.
- You need your Infracost Cloud organization ID - find this in the Org Settings of [Infracost Cloud](https://dashboard.infracost.io).
- You store your Terraform state files in S3. Please email support@infracost.io if you use other state stores.

## Usage instructions

1. Use the module to create the parser Lambda in your AWS account:

```hcl
provider "aws" {
  region = "us-west-2"
}

module "infracost_state_parser" {
  source = "github.com/infracost/infracost-state-parser-module?ref=v0.2.1"

  providers = {
    aws = aws
  }

  organization_id = "your_organization_id"

  # Optional: explicit path prefixes or full paths to state files. If omitted,
  # the parser finds S3 buckets whose names reference Terraform, Terragrunt or
  # IaC state (e.g. tfstate, terraform-state, acme-prod-statefiles,
  # terragrunt-123456789012-us-east-1) and scans them for *.tfstate and
  # *.json objects.
  # state_files = [
  #   "s3://your_bucket/statefiles/*",
  #   "s3://your_other_bucket/full/path/to/statefile.json"
  # ]

  # state_kms_key_arns = ["arn:aws:kms:us-west-2:123456789012:key/your-key-id"] # Optional KMS keys used to encrypt the state files.
  # schedule_period = "PT1H" # Optional ISO 8601 period between parser runs. Defaults to one hour.
  # log_level = "INFO" # Optional log level for the Lambda function. Valid values are `DEBUG`, `INFO` (default), `WARN`, or `ERROR`.
}
```

2. Run `terraform init` and `terraform apply` to create the statefile parser.

3. Email support@infracost.io so we can enable state parsing for your organization:

```text
To: support@infracost.io
Subject: Enable Statefile parser for Infracost Cloud

Body:
Hi, my name is Rafa and I'm the DevOps Lead at ACME Corporation.

- Infracost Cloud org ID: $YOUR_INFRACOST_ORGANIZATION_ID

Regards,
Rafa
```

## How will Infracost use the above access?

1. This sets up a Lambda function that runs periodically using a CloudWatch Event Rule.
2. It scans your configured state files (or discovered state buckets) and extracts the attributes listed below.
3. It then sends a subset of the below attributes to an S3 bucket in Infracost's account:

For all resources:
 * `id`
 * `arn`
 * `region`
 * `tags`

For `aws_instance`:
 * `instance_type`
 * `ami`
 * `availability_zone`

For `aws_db_instance`:
 * `identifier`
 * `instance_class`
 * `engine`
 * `engine_version`
 * `endpoint`
 * `multi_az`
 * `allocated_storage`
 * `storage_type`

For `aws_rds_cluster`:
 * `cluster_identifier`
 * `database_name`
 * `engine`
 * `engine_version`
 * `db_cluster_instance_class`
 * `endpoint`

For `aws_rds_cluster_instance`:
 * `cluster_identifier`
 * `identifier`
 * `instance_class`
 * `engine`
 * `engine_version`
 * `endpoint`

For `aws_s3_bucket`:
 * `bucket`
 * `bucket_domain_name`
 * `bucket_region`

For `aws_autoscaling_group`:
 * `name`
 * `min_size`
 * `max_size`
 * `desired_capacity`
 * `launch_configuration`
 * `launch_template.id`
 * `launch_template.name`
 * `launch_template.version`
 * `launch_template.instance_type` (resolved from the launch template)

For `aws_launch_template`:
 * `name`
 * `image_id`
 * `instance_type`
 * `default_version`
 * `latest_version`

For `aws_launch_configuration`:
 * `name`
 * `image_id`
 * `instance_type`

For `aws_eks_cluster`:
 * `name`
 * `version`

For `aws_eks_node_group`:
 * `cluster_name`
 * `node_group_name`
 * `ami_type`
 * `instance_types`
 * `launch_template`
 * `version`
 * `resources.autoscaling_groups.*.name`

For `aws_ecs_cluster`:
 * `name`

For `aws_ecs_service`:
 * `name`
 * `cluster`
 * `launch_type`
 * `platform_version`

For `aws_lambda_function`:
 * `function_name`
 * `architectures`
 * `runtime`

## Updates

When new FinOps policies or features are added, this module may need to be updated, and the Lambda function may need to be redeployed. We will notify you when this is the case so you can update the version of the module.
