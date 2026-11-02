# Compliance C12: every account records its configuration; the security account sees all of it.

module "config_management" {
  source = "../modules/config-recorder"

  create_service_linked_role = var.create_config_service_linked_roles
}

module "config_security" {
  source = "../modules/config-recorder"
  providers = {
    aws = aws.security
  }

  create_service_linked_role = var.create_config_service_linked_roles
}

# Config has no console option for delegation — this is the API the CLI step uses.
resource "aws_organizations_delegated_administrator" "config" {
  for_each = toset(["config.amazonaws.com", "config-multiaccountsetup.amazonaws.com"])

  account_id        = var.security_account_id
  service_principal = each.value
}

resource "aws_config_configuration_aggregator" "org" {
  provider = aws.security

  name = "org-aggregator"

  organization_aggregation_source {
    all_regions = false
    regions     = [var.region]
    # Delegated admins can use Config's service-linked role for org aggregation.
    role_arn = "arn:aws:iam::${var.security_account_id}:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig"
  }

  depends_on = [
    aws_organizations_delegated_administrator.config,
    module.config_security,
  ]
}
