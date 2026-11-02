locals {
  default_tags = {
    Lab       = "lab-1-landing-zone"
    Stack     = "logging"
    Owner     = var.owner
    ManagedBy = "terraform"
  }
}

# Management account — owns the organization trail.
provider "aws" {
  region = var.region

  default_tags {
    tags = local.default_tags
  }
}

# Security account — owns the log bucket and KMS key.
# Reached through the role Organizations creates in every new member account.
provider "aws" {
  alias  = "security"
  region = var.region

  assume_role {
    role_arn     = "arn:aws:iam::${var.security_account_id}:role/${var.security_role_name}"
    session_name = "terraform-lab1-logging"
  }

  default_tags {
    tags = local.default_tags
  }
}
