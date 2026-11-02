# Compliance C3: centralized root access management.
# Accounts created by Organizations have no root credentials; this keeps it that way and lets the
# management account run short, task-scoped root sessions instead of anyone holding a root password.
resource "aws_iam_organizations_features" "this" {
  enabled_features = [
    "RootCredentialsManagement",
    "RootSessions",
  ]

  lifecycle {
    precondition {
      condition     = contains(var.aws_service_access_principals, "iam.amazonaws.com")
      error_message = "Centralized root access requires iam.amazonaws.com in aws_service_access_principals."
    }
  }

  depends_on = [aws_organizations_organization.this]
}
