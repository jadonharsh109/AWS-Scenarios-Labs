# Runs in the management account.
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Lab       = "lab-1-landing-zone"
      Stack     = "organization"
      Owner     = var.owner
      ManagedBy = "terraform"
    }
  }
}
