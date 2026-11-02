# External-access analyzer with the organization as the zone of trust (free).
# The "unused access" analyzer type is paid and intentionally not created.

resource "aws_organizations_delegated_administrator" "access_analyzer" {
  account_id        = var.security_account_id
  service_principal = "access-analyzer.amazonaws.com"
}

resource "aws_accessanalyzer_analyzer" "org" {
  provider = aws.security

  analyzer_name = "org-external-access"
  type          = "ORGANIZATION"

  depends_on = [aws_organizations_delegated_administrator.access_analyzer]
}

resource "aws_accessanalyzer_archive_rule" "this" {
  provider = aws.security
  for_each = var.access_analyzer_archive_rules

  analyzer_name = aws_accessanalyzer_analyzer.org.analyzer_name
  rule_name     = each.key

  dynamic "filter" {
    for_each = each.value

    content {
      criteria = filter.key
      eq       = filter.value.eq
      neq      = filter.value.neq
      contains = filter.value.contains
      exists   = filter.value.exists == null ? null : tostring(filter.value.exists)
    }
  }
}
