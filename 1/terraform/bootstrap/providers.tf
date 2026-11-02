provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Lab       = "lab-1-landing-zone"
      Stack     = "bootstrap"
      Owner     = var.owner
      ManagedBy = "terraform"
    }
  }
}
