resource "aws_organizations_organization" "this" {
  feature_set                   = "ALL"
  aws_service_access_principals = var.aws_service_access_principals
  enabled_policy_types          = var.enabled_policy_types

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  root_id = aws_organizations_organization.this.roots[0].id
}
