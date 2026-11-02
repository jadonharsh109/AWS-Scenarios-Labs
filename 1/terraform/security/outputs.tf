output "guardduty_detector_id" {
  description = "GuardDuty detector in the security (admin) account."
  value       = aws_guardduty_detector.security.id
}

output "securityhub_policy_id" {
  description = "Security Hub central configuration policy attached to the root."
  value       = aws_securityhub_configuration_policy.baseline.id
}

output "config_aggregator_arn" {
  description = "Organization Config aggregator."
  value       = aws_config_configuration_aggregator.org.arn
}

output "access_analyzer_arn" {
  description = "Organization external-access analyzer."
  value       = aws_accessanalyzer_analyzer.org.arn
}
