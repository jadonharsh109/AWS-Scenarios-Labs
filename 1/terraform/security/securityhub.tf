# Compliance C13 (posture): Security Hub CSPM with central configuration.
# Central configuration lets one policy in the home region decide, for the whole org,
# whether Security Hub is on and which standards run — no per-account clicking.

resource "aws_securityhub_account" "security" {
  provider = aws.security

  enable_default_standards = false
}

resource "aws_securityhub_organization_admin_account" "security" {
  admin_account_id = var.security_account_id

  depends_on = [aws_securityhub_account.security]
}

# Central configuration requires a finding aggregator. NO_REGIONS = home region only.
resource "aws_securityhub_finding_aggregator" "this" {
  provider = aws.security

  linking_mode = "NO_REGIONS"

  depends_on = [aws_securityhub_organization_admin_account.security]
}

resource "aws_securityhub_organization_configuration" "this" {
  provider = aws.security

  auto_enable           = false
  auto_enable_standards = "NONE"

  organization_configuration {
    configuration_type = "CENTRAL"
  }

  depends_on = [aws_securityhub_finding_aggregator.this]
}

resource "aws_securityhub_configuration_policy" "baseline" {
  provider = aws.security

  name        = "org-baseline"
  description = "Security Hub on, FSBP only"

  configuration_policy {
    service_enabled       = true
    enabled_standard_arns = [for s in var.securityhub_standards : "arn:aws:securityhub:${var.region}::standards/${s}"]

    security_controls_configuration {
      disabled_control_identifiers = []
    }
  }

  depends_on = [aws_securityhub_organization_configuration.this]
}

resource "aws_securityhub_configuration_policy_association" "root" {
  provider = aws.security

  target_id = local.root_id
  policy_id = aws_securityhub_configuration_policy.baseline.id
}
