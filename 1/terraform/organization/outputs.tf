output "organization_id" {
  description = "Organization ID."
  value       = aws_organizations_organization.this.id
}

output "root_id" {
  description = "Organization root ID."
  value       = local.root_id
}

output "management_account_id" {
  description = "Management account ID."
  value       = aws_organizations_organization.this.master_account_id
}

output "ou_ids" {
  description = "OU IDs keyed by OU name."
  value       = local.ou_ids
}

output "account_ids" {
  description = "Member account IDs keyed by account name."
  value       = { for name, acct in aws_organizations_account.this : name => acct.id }
}
