

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
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage"
    ]
    resources = [local.image_arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${var.state_bucket}/${var.organization_id}/*"]
  }

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
