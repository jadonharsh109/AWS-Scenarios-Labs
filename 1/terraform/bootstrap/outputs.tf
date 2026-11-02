output "state_bucket_name" {
  description = "S3 bucket for remote state — use it in each stack's backend.hcl."
  value       = aws_s3_bucket.state.id
}

output "region" {
  description = "Region of the state bucket."
  value       = var.region
}
