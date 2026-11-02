variable "region" {
  description = "Region where IAM Identity Center is enabled."
  type        = string
  default     = "us-east-1"
}

variable "owner" {
  description = "Owner tag value (team or person responsible)."
  type        = string
}

variable "groups" {
  description = "Identity Center groups: name => description."
  type        = map(string)
}

variable "users" {
  description = "Identity Center users keyed by user name. In production these usually come from an external IdP via SCIM instead."
  type = map(object({
    given_name  = string
    family_name = string
    email       = string
    groups      = optional(list(string), [])
  }))
  default = {}

  validation {
    condition     = alltrue(flatten([for u in values(var.users) : [for g in u.groups : contains(keys(var.groups), g)]]))
    error_message = "Every user group must be a key in var.groups."
  }
}

variable "permission_sets" {
  description = "Permission sets keyed by name (max 32 chars)."
  type = map(object({
    description         = string
    session_duration    = optional(string, "PT1H")
    managed_policy_arns = list(string)
  }))

  validation {
    condition     = alltrue([for name in keys(var.permission_sets) : length(name) <= 32])
    error_message = "Permission set names must be 32 characters or fewer."
  }

  validation {
    condition     = alltrue([for ps in values(var.permission_sets) : can(regex("^PT([1-9]|1[0-2])H$", ps.session_duration))])
    error_message = "session_duration must be PT1H to PT12H."
  }
}

variable "account_assignments" {
  description = <<-EOT
    Group -> permission set -> accounts. Accounts are referenced by their name in the organization;
    the special name "management" means the management account. Accounts that don't exist yet are
    skipped (see the skipped_assignments output), so the full matrix can be declared up front.
  EOT
  type = list(object({
    group          = string
    permission_set = string
    accounts       = list(string)
  }))

  validation {
    condition     = alltrue([for a in var.account_assignments : contains(keys(var.groups), a.group)])
    error_message = "Every assignment group must be a key in var.groups."
  }

  validation {
    condition     = alltrue([for a in var.account_assignments : contains(keys(var.permission_sets), a.permission_set)])
    error_message = "Every assignment permission_set must be a key in var.permission_sets."
  }
}
