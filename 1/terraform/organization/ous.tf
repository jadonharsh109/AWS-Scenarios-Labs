locals {
  top_level_ous = { for name, ou in var.organizational_units : name => ou if ou.parent == null }
  child_ous     = { for name, ou in var.organizational_units : name => ou if ou.parent != null }

  ou_ids = merge(
    { for name, ou in aws_organizations_organizational_unit.top_level : name => ou.id },
    { for name, ou in aws_organizations_organizational_unit.child : name => ou.id },
  )
}

resource "aws_organizations_organizational_unit" "top_level" {
  for_each = local.top_level_ous

  name      = each.key
  parent_id = local.root_id
}

resource "aws_organizations_organizational_unit" "child" {
  for_each = local.child_ous

  name      = each.key
  parent_id = aws_organizations_organizational_unit.top_level[each.value.parent].id
}
