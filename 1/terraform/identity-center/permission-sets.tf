resource "aws_ssoadmin_permission_set" "this" {
  for_each = var.permission_sets

  instance_arn     = local.instance_arn
  name             = each.key
  description      = each.value.description
  session_duration = each.value.session_duration
}

locals {
  permission_set_policies = merge([
    for ps_name, ps in var.permission_sets : {
      for policy_arn in ps.managed_policy_arns : "${ps_name}/${policy_arn}" => {
        permission_set = ps_name
        policy_arn     = policy_arn
      }
    }
  ]...)
}

resource "aws_ssoadmin_managed_policy_attachment" "this" {
  for_each = local.permission_set_policies

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.permission_set].arn
  managed_policy_arn = each.value.policy_arn
}
