# Runs in the management account, in the region where Identity Center is enabled.
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Lab       = "lab-1-landing-zone"
      Stack     = "identity-center"
      Owner     = var.owner
      ManagedBy = "terraform"
    }
  }
}
