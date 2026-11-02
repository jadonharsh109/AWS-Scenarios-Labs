output "instance_arn" {
  description = "IAM Identity Center instance ARN."
  value       = local.instance_arn
}

output "identity_store_id" {
  description = "Identity store ID."
  value       = local.identity_store_id
}

output "group_ids" {
  description = "Group IDs keyed by group name."
  value       = { for name, g in aws_identitystore_group.this : name => g.group_id }
}

output "permission_set_arns" {
  description = "Permission set ARNs keyed by name."
  value       = { for name, ps in aws_ssoadmin_permission_set.this : name => ps.arn }
}

output "skipped_assignments" {
  description = "Assignments whose target account doesn't exist yet — re-apply after creating it."
  value       = local.skipped_assignments
}
