# Infracost Statefile Parser Module

This gives Infracost the ability to improve our algorithm that maps cloud resources to IaC code. The parser is a Lambda function that is deployed in your AWS accounts that contain your Terraform Statefiles so it can extract certain non-sensitive/non-secret attributes to send to Infracost periodically.

## Prerequisites
- You have an AWS account
- You need your Infracost Cloud organization ID - find this in the Org Settings of [Infracost Cloud](https://dashboard.infracost.io)
- You store your Terraform state files in S3. Please email support@infracost.io if you use other state stores.

## Usage instructions

1. Use the module to create the cross account role in your AWS account

```hcl
provider "aws" {
  region = "us-west-2"
}

module "infracost_state_parser" {
  source = "github.com/infracost/infracost-state-parser-module?ref=v0.1.6"

  providers = {
    aws = aws
  }

  organization_id = "your_organization_id"

  # You can pass in path prefixes or full paths to state files
  state_files = [
    "s3://your_bucket/statefiles/*",
    "s3://your_other_bucket/full/path/to/statefile.json"
  ]

  # log_level = "INFO" # Optional log level for the Lambda function. Valid values are `DEBUG`, `INFO` (default), `WARN`, or `ERROR`.
}

// the ARN of the Lambda function created by this module
// give this ARN to Infracost to enable state parsing
output "infracost_state_parser_lambda_role_arn" {
  value = module.infracost_state_parser.iam_role_arn
}
```

2. Run `terraform init` and `terraform apply` to create the statefile parser

3. Email the `infracost_state_parser_lambda_role_arn` outputs to Infracost:

```text
To: support@infracost.io
Subject: Enable Statefile parser for Infracost Cloud

Body:
Hi, my name is Rafa and I'm the DevOps Lead at ACME Corporation.

- Infracost Cloud org ID: $YOUR_INFRACOST_ORGANIZATION_ID
- Our statefile parser Lambda ARNs are:
<terraform output infracost_state_parser_lambda_role_arn>

Regards,
Rafa
```

## How will Infracost use the above access?

1. This sets up a Lambda function that runs periodically using a CloudWatch Event Rule
2. This Lambda function is given access to an S3 bucket in Infracost's account.
2. It scans your S3 bucket for Terraform statefiles and extracts the attributes listed below.
3. It then sends a subset of the below attributes to the S3 bucket in Infracost's account:

For all resources:
 * `id`
 * `arn`
 * `region`
 * `tags`

For `aws_instance`:
 * `instance_type`
 * `availability_zone`
 * `launch_template.id`
 * `launch_template.name`
 * `launch_template.version`
 * `root_block_device.volume_id`
 * `root_block_device.volume_type`
 * `root_block_device.volume_size`
 * `root_block_device.iops`
 * `root_block_device.throughput`
 * `ebs_block_device.device_name`
 * `ebs_block_device.volume_id`
 * `ebs_block_device.volume_type`
 * `ebs_block_device.volume_size`
 * `ebs_block_device.iops`
 * `ebs_block_device.throughput`

For `aws_db_instance`:
 * `instance_class`
 * `engine`
 * `engine_version`
 * `multi_az`
 * `allocated_storage`
 * `storage_type`

For `aws_rds_cluster`:
 * `cluster_identifier`
 * `database_name`
 * `engine`
 * `engine_version`
 * `instance_class`

For `aws_rds_cluster_instance`:
 * `cluster_identifier`
 * `instance_identifier`
 * `instance_class`

For `aws_autoscaling_group`:
 * `name`
 * `min_size`
 * `max_size`
 * `desired_capacity`

For `aws_launch_template`:
 * `name`
 * `version`
 * `instance_type`
 * `image_id`
 * `placement.availability_zone`
 * `block_device_mappings.device_name`
 * `block_device_mappings.ebs.volume_type`
 * `block_device_mappings.ebs.volume_size`
 * `block_device_mappings.ebs.iops`
 * `block_device_mappings.ebs.throughput`

For `aws_launch_configuration`:
 * `name`
 * `image_id`
 * `instance_type`
 * `root_block_device.volume_type`
 * `root_block_device.volume_size`
 * `root_block_device.iops`
 * `root_block_device.throughput`
 * `ebs_block_device.device_name`
 * `ebs_block_device.volume_id`
 * `ebs_block_device.volume_type`
 * `ebs_block_device.volume_size`
 * `ebs_block_device.iops`
 * `ebs_block_device.throughput`

For `aws_eks_cluster`:
 * `cluster_id`
 * `name`
 * `version`

`aws_eks_node_group`:
 * `cluster_name`
 * `node_group_name`
 * `ami_type`
 * `disk_size`
 * `instance_types`
 * `launch_template`
 * `version`
 * `resources.autoscaling_groups.*.name`

`aws_ecs_cluster`:
 * `name`

`aws_ecs_service`:
 * `name`
 * `cluster`
 * `launch_type`

`aws_ecs_task_definition`:
 * `family`
 * `cpu`
 * `memory`
 * `required_compatibilities`
 * `runtime_platform.operating_system_family`
 * `runtime_platform.cpu_architecture`

For `aws_lambda_function`:
 * `function_name`
 * `architectures`
 * `ephemeral_storage`
 * `memory_size`

## Updates

When new FinOps policies or features are added, this module may need to be updated, and the Lambda function may need to be redeployed. We will notify you when this is the case so you can update the version of the module.
