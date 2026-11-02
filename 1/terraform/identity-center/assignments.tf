locals {
  # One entry per group / permission set / account, limited to accounts that exist right now.
  account_assignments = merge([
    for a in var.account_assignments : {
      for account in a.accounts : "${a.group}/${a.permission_set}/${account}" => {
        group          = a.group
        permission_set = a.permission_set
        account_id     = local.account_ids[account]
      } if contains(keys(local.account_ids), account)
    }
  ]...)

  skipped_assignments = flatten([
    for a in var.account_assignments : [
      for account in a.accounts : "${a.group}/${a.permission_set}/${account}"
      if !contains(keys(local.account_ids), account)
    ]
  ])
}

resource "aws_ssoadmin_account_assignment" "this" {
  for_each = local.account_assignments

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.permission_set].arn

  principal_type = "GROUP"
  principal_id   = aws_identitystore_group.this[each.value.group].group_id

  target_type = "AWS_ACCOUNT"
  target_id   = each.value.account_id

  # Provision the permission set with its policies attached, not empty.
  depends_on = [aws_ssoadmin_managed_policy_attachment.this]
}
