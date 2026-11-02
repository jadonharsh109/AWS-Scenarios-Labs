data "aws_iam_policy_document" "cloudtrail_key" {
  statement {
    sid       = "EnableSecurityAccountAdmin"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.security_account_id}:root"]
    }
  }

  statement {
    sid       = "AllowCloudTrailEncrypt"
    actions   = ["kms:GenerateDataKey*"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }

    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = ["arn:aws:cloudtrail:*:${local.management_account_id}:trail/*"]
    }
  }

  statement {
    sid       = "AllowCloudTrailDescribeKey"
    actions   = ["kms:DescribeKey"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  statement {
    sid       = "AllowOrgPrincipalsToDecryptLogs"
    actions   = ["kms:Decrypt", "kms:ReEncryptFrom"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [local.organization_id]
    }

    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = ["arn:aws:cloudtrail:*:${local.management_account_id}:trail/*"]
    }
  }
}

# ~$1/month. Must be in the same region as the bucket.
resource "aws_kms_key" "cloudtrail" {
  provider = aws.security

  description             = "Encrypts organization CloudTrail logs"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.cloudtrail_key.json
}

resource "aws_kms_alias" "cloudtrail" {
  provider = aws.security

  name          = "alias/cloudtrail-org"
  target_key_id = aws_kms_key.cloudtrail.key_id
}
