output "recorder_name" {
  description = "Configuration recorder name."
  value       = aws_config_configuration_recorder.this.name
}

output "bucket_name" {
  description = "Config delivery bucket."
  value       = aws_s3_bucket.config.id
}
