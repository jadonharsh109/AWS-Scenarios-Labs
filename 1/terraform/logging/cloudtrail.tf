# Organization trail: every account, every region, management events only.
# The first copy of management events is free; data events, Insights and CloudWatch Logs are left off to avoid charges.
# Requires cloudtrail.amazonaws.com trusted access (organization stack).
resource "aws_cloudtrail" "org" {
  name                          = var.trail_name
  s3_bucket_name                = aws_s3_bucket.logs.id
  kms_key_id                    = aws_kms_key.cloudtrail.arn
  is_organization_trail         = true
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  # Bucket and key must accept writes from this trail before it is created.
  depends_on = [
    aws_s3_bucket_policy.logs,
    aws_s3_bucket_server_side_encryption_configuration.logs,
  ]
}
