data "aws_caller_identity" "management" {}

data "aws_organizations_organization" "this" {}

locals {
  management_account_id = data.aws_caller_identity.management.account_id
  organization_id       = data.aws_organizations_organization.this.id

  # Known before the trail exists, so the bucket and key policies can be scoped to it (confused deputy protection).
  trail_arn = "arn:aws:cloudtrail:${var.region}:${local.management_account_id}:trail/${var.trail_name}"

  log_bucket_name = "${var.name_prefix}-org-cloudtrail-${var.security_account_id}"
  # Built from the name (not the resource) so the bucket policy is fully visible at plan time.
  log_bucket_arn = "arn:aws:s3:::${local.log_bucket_name}"
}
