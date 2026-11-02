data "aws_organizations_organization" "this" {}

data "aws_organizations_organizational_units" "top_level" {
  parent_id = local.root_id
}

locals {
  root_id = data.aws_organizations_organization.this.roots[0].id

  # Attachment targets by name: the root, top-level OUs and active member accounts.
  target_ids = merge(
    { Root = local.root_id },
    { for ou in data.aws_organizations_organizational_units.top_level.children : ou.name => ou.id },
    { for acct in data.aws_organizations_organization.this.accounts : acct.name => acct.id if acct.status == "ACTIVE" },
  )
}
