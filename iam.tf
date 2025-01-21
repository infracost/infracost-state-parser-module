locals {
  parsed_state_files = [
    for url in var.state_files : {
      bucket = regex("s3://([^/]+)/.*", url)[0]
      prefix = regex("s3://[^/]+/(.*)", url)[0]
    }
  ]

  grouped_by_bucket = {
    for obj in local.parsed_state_files : obj.bucket => compact([
      for obj2 in local.parsed_state_files : obj2.bucket == obj.bucket ? obj2.prefix : null
    ])...
  }

}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = ["*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["ec3:GetDownloadUrlForLayer"]
    resources = ["*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["ecr:BatchGetImage"]
    resources = [local.image_arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = [var.state_bucket]
  }
}

data "aws_iam_policy_document" "state_file_access" {
  dynamic "statement" {
    for_each = local.grouped_by_bucket
    content {
      actions = [
        "s3:GetObject",
        "s3:ListBucket",
      ]
      resources = concat(
        ["arn:aws:s3:::${statement.key}"],
        [for prefix in statement.value[0] : "arn:aws:s3:::${statement.key}/${prefix}"]
      )
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

output "iam_role_arn" {
  value = aws_iam_role.state_file_parser.arn
}
