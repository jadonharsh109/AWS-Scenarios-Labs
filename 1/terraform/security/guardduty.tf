# Compliance C13 (threats): GuardDuty for every account, administered from the security account.

resource "aws_guardduty_detector" "security" {
  provider = aws.security

  enable = true
}

# Paid protection plans OFF on the admin's own detector...
resource "aws_guardduty_detector_feature" "security_paid_off" {
  provider = aws.security
  for_each = toset(var.guardduty_paid_features)

  detector_id = aws_guardduty_detector.security.id
  name        = each.value
  status      = "DISABLED"
}

resource "aws_guardduty_organization_admin_account" "security" {
  admin_account_id = var.security_account_id

  depends_on = [aws_guardduty_detector.security]
}

resource "aws_guardduty_organization_configuration" "this" {
  provider = aws.security

  detector_id                      = aws_guardduty_detector.security.id
  auto_enable_organization_members = "ALL"

  depends_on = [aws_guardduty_organization_admin_account.security]
}

# ...and OFF for every member account.
resource "aws_guardduty_organization_configuration_feature" "paid_off" {
  provider = aws.security
  for_each = toset(var.guardduty_paid_features)

  detector_id = aws_guardduty_detector.security.id
  name        = each.value
  auto_enable = "NONE"

  depends_on = [aws_guardduty_organization_configuration.this]
}
