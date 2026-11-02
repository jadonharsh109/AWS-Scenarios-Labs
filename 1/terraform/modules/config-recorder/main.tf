# AWS Config recorder + delivery channel + delivery bucket for ONE account in ONE region.
# Config has no org-wide "auto-enable" (without Control Tower), so every account needs this.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  bucket_name = "config-bucket-${local.account_id}"
  bucket_arn  = "arn:${data.aws_partition.current.partition}:s3:::${local.bucket_name}"
}

# Config's service-linked role. Only one can exist per account, so it is optional.
resource "aws_iam_service_linked_role" "config" {
  count = var.create_service_linked_role ? 1 : 0

  aws_service_name = "config.amazonaws.com"
}

locals {
  service_linked_role_arn = "arn:${data.aws_partition.current.partition}:iam::${local.account_id}:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig"
}

resource "aws_s3_bucket" "config" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy_bucket
}

resource "aws_s3_bucket_public_access_block" "config" {
  bucket = aws_s3_bucket.config.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "config" {
  bucket = aws_s3_bucket.config.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  bucket = aws_s3_bucket.config.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "config" {
  bucket = aws_s3_bucket.config.id

  rule {
    id     = "expire-config-history"
    status = "Enabled"

    filter {}

    expiration {
      days = var.retention_days
    }
  }
}

data "aws_iam_policy_document" "config_bucket" {
  statement {
    sid       = "AWSConfigBucketPermissionsCheck"
    actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
    resources = [local.bucket_arn]

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid       = "AWSConfigBucketDelivery"
    actions   = ["s3:PutObject"]
    resources = ["${local.bucket_arn}/AWSLogs/${local.account_id}/Config/*"]

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      local.bucket_arn,
      "${local.bucket_arn}/*",
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

resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config.id
  policy = data.aws_iam_policy_document.config_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.config]
}

resource "aws_config_configuration_recorder" "this" {
  name     = "default"
  role_arn = local.service_linked_role_arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = var.include_global_resource_types
  }

  recording_mode {
    recording_frequency = "CONTINUOUS"
  }

  depends_on = [aws_iam_service_linked_role.config]
}

resource "aws_config_delivery_channel" "this" {
  name           = "default"
  s3_bucket_name = aws_s3_bucket.config.id

  depends_on = [
    aws_config_configuration_recorder.this,
    aws_s3_bucket_policy.config,
  ]
}

resource "aws_config_configuration_recorder_status" "this" {
  name       = aws_config_configuration_recorder.this.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.this]
}
