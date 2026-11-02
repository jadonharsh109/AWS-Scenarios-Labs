locals {
  default_tags = {
    Lab       = "lab-1-landing-zone"
    Stack     = "security"
    Owner     = var.owner
    ManagedBy = "terraform"
  }
}

# Management account — registers the delegated administrators.
provider "aws" {
  region = var.region

  default_tags {
    tags = local.default_tags
  }
}

# Security account — the delegated admin that runs every security service.
# The break-glass role is exempt from the guardrail SCPs (C5, C7), which Terraform needs.
provider "aws" {
  alias  = "security"
  region = var.region

  assume_role {
    role_arn     = "arn:aws:iam::${var.security_account_id}:role/${var.security_role_name}"
    session_name = "terraform-lab1-security"
  }

  default_tags {
    tags = local.default_tags
  }
}
