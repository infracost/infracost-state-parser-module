data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "state_file_access" {
  statement {
    sid       = "WriteLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:*"]
  }

  dynamic "statement" {
    for_each = local.managed_image ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage"
      ]
      resources = [local.image_arn]
    }
  }

  dynamic "statement" {
    for_each = local.managed_image ? [1] : []
    content {
      effect    = "Allow"
      actions   = ["ecr:GetAuthorizationToken"]
      resources = ["*"]
    }
  }

  statement {
    sid       = "WriteSanitizedReports"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${var.state_bucket}/${local.state_report_key}"]
  }

  dynamic "statement" {
    for_each = local.exact_buckets
    content {
      sid       = "LocateBucket${substr(sha1(statement.value), 0, 12)}"
      effect    = "Allow"
      actions   = ["s3:GetBucketLocation"]
      resources = ["arn:aws:s3:::${statement.value}"]
    }
  }

  dynamic "statement" {
    for_each = local.exact_buckets
    content {
      sid       = "ListBucket${substr(sha1(statement.value), 0, 12)}"
      effect    = "Allow"
      actions   = ["s3:ListBucket"]
      resources = ["arn:aws:s3:::${statement.value}"]
    }
  }

  dynamic "statement" {
    for_each = length(local.parsed_state_files) > 0 ? [1] : []
    content {
      sid     = "ReadConfiguredStateObjects"
      effect  = "Allow"
      actions = ["s3:GetObject"]
      resources = [
        for source in local.parsed_state_files : "arn:aws:s3:::${source.bucket}/${source.key_pattern}"
      ]
    }
  }

  dynamic "statement" {
    for_each = length(local.wildcard_bucket_sources) > 0 || local.default_discovery ? [1] : []
    content {
      sid       = "DiscoverMatchingBuckets"
      effect    = "Allow"
      actions   = ["s3:ListAllMyBuckets"]
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = local.default_discovery ? [1] : []
    content {
      sid       = "DefaultDiscoveryInspectBuckets"
      effect    = "Allow"
      actions   = ["s3:GetBucketLocation", "s3:ListBucket"]
      resources = local.default_discovery_bucket_arns
    }
  }

  dynamic "statement" {
    for_each = local.default_discovery ? [1] : []
    content {
      sid     = "DefaultDiscoveryReadStateObjects"
      effect  = "Allow"
      actions = ["s3:GetObject"]
      resources = flatten([
        for arn in local.default_discovery_bucket_arns : ["${arn}/*.tfstate", "${arn}/*.json"]
      ])
    }
  }

  dynamic "statement" {
    for_each = length(local.wildcard_bucket_sources) > 0 ? [1] : []
    content {
      sid     = "InspectMatchingBucketRegions"
      effect  = "Allow"
      actions = ["s3:GetBucketLocation"]
      resources = distinct([
        for source in local.wildcard_bucket_sources : "arn:aws:s3:::${source.bucket}"
      ])
    }
  }

  dynamic "statement" {
    for_each = {
      for source in local.wildcard_bucket_sources : sha1(source.url) => source
    }
    content {
      sid       = "ListMatchingBuckets${substr(statement.key, 0, 12)}"
      effect    = "Allow"
      actions   = ["s3:ListBucket"]
      resources = ["arn:aws:s3:::${statement.value.bucket}"]

      condition {
        test     = "StringLike"
        variable = "s3:prefix"
        values   = ["${statement.value.literal_key_prefix}*"]
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.state_kms_key_arns) > 0 ? [1] : []
    content {
      sid       = "DecryptConfiguredStateKeys"
      effect    = "Allow"
      actions   = ["kms:Decrypt"]
      resources = sort(tolist(var.state_kms_key_arns))
    }
  }

}

resource "aws_iam_policy" "state_file_access" {
  name        = "infracost-state-file-access"
  description = "Policy to allow access to state files"
  policy      = data.aws_iam_policy_document.state_file_access.json
}

resource "aws_iam_role" "state_file_parser" {
  name               = "infracost-state-parser-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "state_file_access_policy_attachement" {
  role       = aws_iam_role.state_file_parser.name
  policy_arn = aws_iam_policy.state_file_access.arn
}

resource "aws_iam_role_policy" "vpc_access" {
  count = var.vpc_config == null ? 0 : 1

  name = "infracost-state-parser-vpc-access"
  role = aws_iam_role.state_file_parser.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ManageLambdaNetworkInterfaces"
      Effect = "Allow"
      Action = [
        "ec2:CreateNetworkInterface",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DescribeSubnets",
        "ec2:DeleteNetworkInterface",
        "ec2:AssignPrivateIpAddresses",
        "ec2:UnassignPrivateIpAddresses",
      ]
      Resource = "*"
    }]
  })
}

output "iam_role_arn" {
  value = aws_iam_role.state_file_parser.arn
}
