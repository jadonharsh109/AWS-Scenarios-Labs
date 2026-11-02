# The organization instance of Identity Center has no create API — it is enabled once in the console.
data "aws_ssoadmin_instances" "this" {
  lifecycle {
    postcondition {
      condition     = length(self.arns) == 1
      error_message = "IAM Identity Center is not enabled in ${var.region}. Enable it in the console first (see README)."
    }
  }
}

data "aws_organizations_organization" "this" {}

locals {
  instance_arn      = one(data.aws_ssoadmin_instances.this.arns)
  identity_store_id = one(data.aws_ssoadmin_instances.this.identity_store_ids)

  account_ids = merge(
    { for acct in data.aws_organizations_organization.this.accounts : acct.name => acct.id if acct.status == "ACTIVE" },
    { management = data.aws_organizations_organization.this.master_account_id },
  )
}
