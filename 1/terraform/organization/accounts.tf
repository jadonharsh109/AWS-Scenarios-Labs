# Account creation is limited by the Organizations "Maximum number of accounts" quota (L-E619E033).
# New orgs often start at 2 (management + one member), which is exactly this lab's design.
resource "aws_organizations_account" "this" {
  for_each = var.accounts

  name      = each.key
  email     = each.value.email
  parent_id = local.ou_ids[each.value.ou]

  role_name                  = "OrganizationAccountAccessRole"
  iam_user_access_to_billing = "DENY"

  # Removing an account from tfvars must never silently close it — closure is a deliberate manual step.
  close_on_deletion = false

  tags = merge(
    {
      Project     = each.value.project
      Environment = each.value.environment
    },
    each.value.tags,
  )

  lifecycle {
    prevent_destroy = true

    # Not returned by the Organizations API after creation, so they would always show a diff.
    ignore_changes = [role_name, iam_user_access_to_billing]
  }
}
