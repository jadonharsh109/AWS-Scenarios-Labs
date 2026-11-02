# Compliance C11: central, immutable audit log store in the security account.
resource "aws_s3_bucket" "logs" {
  provider = aws.security

  bucket              = local.log_bucket_name
  object_lock_enabled = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "logs" {
  provider = aws.security

  bucket = aws_s3_bucket.logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_object_lock_configuration" "logs" {
  provider = aws.security

  bucket = aws_s3_bucket.logs.id

  rule {
    default_retention {
      mode = var.object_lock_mode
      days = var.object_lock_retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.logs]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  provider = aws.security

  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.cloudtrail.arn
    }

    # Cuts KMS request costs by reusing a bucket-level data key.
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  provider = aws.security

  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  provider = aws.security

  bucket = aws_s3_bucket.logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  provider = aws.security

  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "expire-lab-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.log_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.logs]
}

data "aws_iam_policy_document" "logs_bucket" {
  statement {
    sid       = "AWSCloudTrailAclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [local.log_bucket_arn]

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
    sid     = "AWSCloudTrailWrite"
    actions = ["s3:PutObject"]
    resources = [
      "${local.log_bucket_arn}/AWSLogs/${local.management_account_id}/*",
      "${local.log_bucket_arn}/AWSLogs/${local.organization_id}/*",
    ]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      local.log_bucket_arn,
      "${local.log_bucket_arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  provider = aws.security

  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.logs_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.logs]
}
