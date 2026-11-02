variable "region" {
  description = "Home region. The trail, bucket and KMS key must all be in this region."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Short prefix used in resource names (e.g. acme)."
  type        = string
}

variable "owner" {
  description = "Owner tag value (team or person responsible)."
  type        = string
}

variable "security_account_id" {
  description = "Security account ID (terraform -chdir=../organization output account_ids)."
  type        = string

  validation {
    condition     = can(regex("^\\d{12}$", var.security_account_id))
    error_message = "security_account_id must be a 12-digit account ID."
  }
}

variable "security_role_name" {
  description = "Role Terraform assumes in the security account."
  type        = string
  default     = "OrganizationAccountAccessRole"
}

variable "trail_name" {
  description = "Organization trail name. It is part of the trail ARN referenced by the bucket and key policies."
  type        = string
  default     = "org-trail"
}

variable "object_lock_mode" {
  description = "GOVERNANCE (admins with s3:BypassGovernanceRetention can delete) or COMPLIANCE (nobody can delete until retention ends, irreversible)."
  type        = string
  default     = "GOVERNANCE"

  validation {
    condition     = contains(["GOVERNANCE", "COMPLIANCE"], var.object_lock_mode)
    error_message = "object_lock_mode must be GOVERNANCE or COMPLIANCE."
  }
}

variable "object_lock_retention_days" {
  description = "Default Object Lock retention. Keep it short in a lab so cleanup isn't blocked."
  type        = number
  default     = 1
}

variable "log_expiration_days" {
  description = "Days before current log versions expire."
  type        = number
  default     = 30
}

variable "noncurrent_version_expiration_days" {
  description = "Days before noncurrent (deleted or overwritten) log versions are removed."
  type        = number
  default     = 1
}
