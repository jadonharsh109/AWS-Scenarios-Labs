output "policy_ids" {
  description = "Policy IDs keyed by policy name."
  value       = { for name, p in aws_organizations_policy.this : name => p.id }
}

output "attachments" {
  description = "Policy attachments as policy/target."
  value       = keys(aws_organizations_policy_attachment.this)
}
