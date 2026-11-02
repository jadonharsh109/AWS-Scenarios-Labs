variable "region" {
  description = "Home region."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Short prefix used in resource names (e.g. acme-lab1)."
  type        = string
}

variable "owner" {
  description = "Owner tag value (team or person responsible)."
  type        = string
}

# --- Organization -------------------------------------------------------------

variable "aws_service_access_principals" {
  description = "Services granted trusted access to the organization."
  type        = list(string)
  default = [
    "iam.amazonaws.com",        # centralized root access management
    "sso.amazonaws.com",        # IAM Identity Center
    "cloudtrail.amazonaws.com", # organization trail (logging stack)
    "guardduty.amazonaws.com",  # security stack
    "malware-protection.guardduty.amazonaws.com",
    "securityhub.amazonaws.com",              # security stack
    "config.amazonaws.com",                   # security stack (aggregator)
    "config-multiaccountsetup.amazonaws.com", # security stack (org rules / conformance packs)
    "access-analyzer.amazonaws.com",          # security stack
  ]
}

variable "enabled_policy_types" {
  description = "Organization policy types to enable on the root. The guardrails stack attaches policies of these types."
  type        = list(string)
  default     = ["SERVICE_CONTROL_POLICY", "TAG_POLICY", "DECLARATIVE_POLICY_EC2"]
}

variable "organizational_units" {
  description = "OUs keyed by name. parent = null for a top-level OU, or the name of a top-level OU (max two levels)."
  type = map(object({
    parent = optional(string)
  }))

  validation {
    condition = alltrue([
      for name, ou in var.organizational_units :
      ou.parent == null || try(var.organizational_units[ou.parent].parent == null, false)
    ])
    error_message = "Each OU parent must be an existing top-level OU (only two levels are supported)."
  }
}

variable "accounts" {
  description = "Member accounts keyed by account name. ou must be a key of organizational_units."
  type = map(object({
    email       = string
    ou          = string
    project     = optional(string, "shared")
    environment = optional(string, "shared")
    tags        = optional(map(string), {})
  }))

  validation {
    condition     = alltrue([for a in values(var.accounts) : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", a.email))])
    error_message = "Every account needs a valid, unique email address."
  }

  validation {
    condition     = length(distinct([for a in values(var.accounts) : lower(a.email)])) == length(var.accounts)
    error_message = "Account emails must be unique."
  }

  validation {
    condition     = alltrue([for a in values(var.accounts) : contains(keys(var.organizational_units), a.ou)])
    error_message = "Every account ou must match a key in organizational_units."
  }
}

# --- Cost control -------------------------------------------------------------

variable "monthly_budget_usd" {
  description = "Monthly cost budget for the whole organization (consolidated billing)."
  type        = number
  default     = 10
}

variable "budget_alert_thresholds" {
  description = "Percent-of-budget thresholds that trigger an email on actual spend."
  type        = list(number)
  default     = [50, 80, 100]
}

variable "budget_alert_emails" {
  description = "Email addresses that receive budget alerts."
  type        = list(string)
}
