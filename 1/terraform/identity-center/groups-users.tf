resource "aws_identitystore_group" "this" {
  for_each = var.groups

  identity_store_id = local.identity_store_id
  display_name      = each.key
  description       = each.value
}

resource "aws_identitystore_user" "this" {
  for_each = var.users

  identity_store_id = local.identity_store_id
  user_name         = each.key
  display_name      = "${each.value.given_name} ${each.value.family_name}"

  name {
    given_name  = each.value.given_name
    family_name = each.value.family_name
  }

  emails {
    value   = each.value.email
    primary = true
  }
}

locals {
  group_memberships = merge([
    for user_name, user in var.users : {
      for group in user.groups : "${user_name}/${group}" => {
        user  = user_name
        group = group
      }
    }
  ]...)
}

resource "aws_identitystore_group_membership" "this" {
  for_each = local.group_memberships

  identity_store_id = local.identity_store_id
  group_id          = aws_identitystore_group.this[each.value.group].group_id
  member_id         = aws_identitystore_user.this[each.value.user].user_id
}
