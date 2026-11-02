data "aws_organizations_organization" "this" {}

locals {
  root_id = data.aws_organizations_organization.this.roots[0].id
}
