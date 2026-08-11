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
  source = "github.com/infracost/infracost-state-parser-module?ref=v0.2.3"

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

  # Optional destination overrides. The bucket can be owned by you or by
  # another AWS account that permits this module's Lambda role to write.
  # state_bucket        = "your-report-bucket"
  # state_bucket_region = "us-west-2"
  # state_bucket_prefix = "infracost-reports"

  # Optional VPC configuration in which to run the Lambda.
  # vpc_config = {
  #   subnet_ids         = ["subnet-0123456789abcdef0"]
  #   security_group_ids = ["sg-0123456789abcdef0"]
  # }

  # Optional customer-managed parser image. Tags and digests are supported.
  # parser_image_uri = "123456789012.dkr.ecr.us-west-2.amazonaws.com/infracost-state-parser:v0.2.3"
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
3. It then sends a subset of the below attributes to the configured S3 destination bucket:

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

## Report destination

By default, reports are written to the Infracost-managed destination. You can
instead set `state_bucket`, `state_bucket_region`, and optionally
`state_bucket_prefix` to deliver reports to a bucket under your control.

The Lambda role can write only this object in each deployment account:

```text
<prefix>/<organization_id>/aws_account_id=<account_id>/terraform-state-resources.json
```

When `state_bucket_prefix` is empty, the key starts with `organization_id`.
The destination bucket policy is managed outside this module and must permit
the role exposed by the `iam_role_arn` output to call `s3:PutObject` on that
object.

For deployments across accounts in one AWS Organization, a customer-managed
bucket policy can authorize the dedicated parser role while retaining an exact
account-specific object path. Replace the placeholders and omit
`DESTINATION_PREFIX/` when no prefix is configured:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowOrganizationStateParserReports",
    "Effect": "Allow",
    "Principal": "*",
    "Action": "s3:PutObject",
    "Resource": "arn:aws:s3:::DESTINATION_BUCKET/DESTINATION_PREFIX/INFRACOST_ORGANIZATION_ID/aws_account_id=${aws:PrincipalAccount}/terraform-state-resources.json",
    "Condition": {
      "StringEquals": {
        "aws:PrincipalOrgID": "o-EXAMPLEORGID"
      },
      "ArnLike": {
        "aws:PrincipalArn": "arn:aws:iam::*:role/infracost-state-parser-role"
      }
    }
  }]
}
```

The AWS Organization ID in `aws:PrincipalOrgID` is distinct from the Infracost
organization ID used in the report key.

## VPC configuration

Set `vpc_config` to attach the Lambda to existing subnets and security groups.
The subnets and security groups must belong to the same VPC and AWS region.

This module does not create or validate network routes, internet egress, VPC
endpoints, endpoint policies, or security-group rules. The supplied network must
provide connectivity to every S3 bucket used by the parser. VPC attachment and
detachment can take several minutes while Lambda manages its network interfaces.

The IAM principal running Terraform needs these permissions in addition to the
permissions normally required to deploy the module:

```text
ec2:DescribeSecurityGroups
ec2:DescribeSubnets
ec2:DescribeVpcs
ec2:GetSecurityGroupsForVpc
```

AWS documents the separate deployment and execution-role permission sets in
[Giving Lambda functions access to resources in an Amazon VPC](https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html#configuration-vpc-permissions).

## Customer-managed parser image

Set `parser_image_uri` to deploy an image from a private ECR repository under
your control. The image must be in the Lambda function's AWS region, must contain
a Lambda-compatible Linux ARM64 image, and must not be a multi-architecture
image index. You are responsible for the ECR repository policy, including any
cross-account access required by Lambda.

Tags and digests are both accepted. When using a tag, publish a new tag whenever
the image changes. Overwriting an existing tag does not change Terraform's
`image_uri` and therefore does not cause Lambda to update its code. Digest
pinning is available but not required.

## Updates

When new FinOps policies or features are added, this module may need to be updated, and the Lambda function may need to be redeployed. We will notify you when this is the case so you can update the version of the module.
