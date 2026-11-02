output "trail_arn" {
  description = "Organization trail ARN."
  value       = aws_cloudtrail.org.arn
}

output "log_bucket_name" {
  description = "Central log bucket in the security account."
  value       = aws_s3_bucket.logs.id
}

output "kms_key_arn" {
  description = "KMS key that encrypts CloudTrail logs."
  value       = aws_kms_key.cloudtrail.arn
}
