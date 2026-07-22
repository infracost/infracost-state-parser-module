# Infracost state parser module

This module installs one AWS Lambda in a customer account. It reads selected
Terraform state objects from S3 and sends an allowlisted, sanitized resource
inventory to Infracost. Raw Terraform state never leaves the customer account.

## Requirements

- Terraform 1.5 or later
- AWS provider 5.42 or later
- Terraform state stored in S3
- An Infracost organization ID
- Deployment in `eu-central-1`, `eu-west-1`, `eu-west-2`, `us-east-1`,
  `us-east-2`, or `us-west-2`

## Usage

```hcl
provider "aws" {
  region = "us-east-2"
}

module "infracost_state_parser" {
  source = "github.com/infracost/infracost-state-parser-module?ref=v0.2.0"

  organization_id = "your-infracost-organization-id"

  state_files = [
    "s3://company-tfstate/accounts/prod/*.tfstate",
    "s3://company-tfstate/accounts/shared/network.tfstate",
  ]

  # Optional. The default is PT1H.
  schedule_period = "PT1H"

  # Optional. Include only keys used by the selected state objects.
  state_kms_key_arns = [
    "arn:aws:kms:us-east-2:123456789012:key/00000000-0000-0000-0000-000000000000",
  ]
}
```

`schedule_period` is an ISO 8601 period expressed in whole minutes, hours, or
days, for example `PT30M`, `PT1H`, or `P1D`.

## Selecting state files

`state_files` accepts exact S3 object paths and `*` or `?` glob patterns in
bucket names and object keys. The parser lists from the literal object-key
prefix before the first wildcard and filters matching keys inside the account.

For example, `s3://company-tfstate/accounts/prod/*.tfstate` lists only
`accounts/prod/`. A pattern such as `s3://*tfstate*/*prod*` necessarily examines
all matching buckets and keys because it has no narrower literal prefix.

The configured patterns are also the permission boundary: the module grants
read and listing access only for those patterns. Fixed parser safeguards bound
bucket, object, state-file, and byte counts. Reaching a safeguard produces a
partial report rather than a false claim that Terraform coverage is complete.

For state encrypted with a customer-managed KMS key, add its exact ARN to
`state_kms_key_arns`. The KMS key policy must also allow the parser role to use
`kms:Decrypt`; an IAM allow cannot override a restrictive key policy.

## Parser updates

Each module release uses a versioned parser image tag with the same
semantic version. For example, module `v0.2.0` uses parser image `0.2.0` (the
image release workflow omits the Git tag's `v` prefix). Once a paired module
release is published, Infracost does not move its parser image tag and retains
the referenced image digest.

To update the parser, change the module source to a newer release and run
`terraform apply` through the account provisioner. AWS Lambda resolves the
release tag to an image digest during that apply; it does not follow tag changes
on later invocations. The parser has no permission to update its own code.

## Data sent to Infracost

The parser emits only supported AWS resources and allowlisted fields needed for
Lambda, ECS, RDS, S3, and EC2 IaC gap analysis. Controlling resources such as
autoscaling groups, launch templates, and EKS node groups are included so their
child EC2 instances are not incorrectly presented as direct gaps.

Every resource can include:

- AWS account ID and its attribution method
- provider and Terraform resource type
- Terraform resource address
- ARN, or an allowlisted provider identity when no ARN exists
- region
- non-sensitive Terraform tags
- the resource-specific values below

| Terraform resource | Additional values |
| --- | --- |
| `aws_lambda_function` | `function_name`, `architectures`, `runtime` |
| `aws_ecs_service` | `name`, `launch_type`, `platform_version`, `cluster` |
| `aws_ecs_cluster` | `name` |
| `aws_s3_bucket` | `bucket`, `bucket_domain_name`, `bucket_region` |
| `aws_instance` | `instance_type`, `ami`, `availability_zone` |
| `aws_db_instance` | `identifier`, `instance_class`, `engine`, `engine_version`, `endpoint`, `multi_az`, `allocated_storage`, `storage_type` |
| `aws_rds_cluster` | `cluster_identifier`, `database_name`, `engine`, `engine_version`, `db_cluster_instance_class`, `endpoint` |
| `aws_rds_cluster_instance` | `cluster_identifier`, `identifier`, `instance_class`, `engine`, `engine_version`, `endpoint` |
| `aws_autoscaling_group` | `name`, `min_size`, `max_size`, `desired_capacity`, `launch_configuration`, `launch_template` |
| `aws_launch_template` | `name`, `image_id`, `instance_type`, `default_version`, `latest_version` |
| `aws_launch_configuration` | `name`, `image_id`, `instance_type` |
| `aws_eks_cluster` | `name`, `version` |
| `aws_eks_node_group` | `cluster_name`, `node_group_name`, `ami_type`, `instance_types`, `launch_template`, `resources`, `version` |

Terraform outputs, data resources, sensitive paths, raw state, policies, KMS
attributes, and attributes outside the allowlist are not uploaded. Terraform
tag keys and values are transmitted verbatim when Terraform does not mark their
paths sensitive; customers should not put secrets in ordinary tags.

The parser replaces one account-attributed report object on each successful
execution:

```text
<organization-id>/aws_account_id=<account-id>/terraform-state-resources.json
```

The report includes source coverage, counts, freshness metadata, and curated
error codes. Raw AWS error strings are not uploaded. Infracost only classifies
a resource as absent from Terraform when both AWS inventory and the
state-parser report are fresh and complete for that account and service.
