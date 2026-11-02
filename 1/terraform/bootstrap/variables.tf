variable "region" {
  description = "Home region for the state bucket."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Short prefix used in resource names (e.g. acme-lab1)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.name_prefix))
    error_message = "name_prefix must be 3-20 chars of lowercase letters, digits or hyphens."
  }
}

variable "owner" {
  description = "Owner tag value (team or person responsible)."
  type        = string
}

variable "noncurrent_version_retention_days" {
  description = "Days to keep old state file versions before expiring them."
  type        = number
  default     = 90
}
