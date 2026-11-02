variable "region" {
  description = "The only region where security services run (GuardDuty, Security Hub home region, Config, Access Analyzer)."
  type        = string
  default     = "us-east-1"
}

variable "owner" {
  description = "Owner tag value (team or person responsible)."
  type        = string
}

variable "security_account_id" {
  description = "Security account ID — becomes the delegated admin for all security services."
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

variable "create_config_service_linked_roles" {
  description = "Create AWSServiceRoleForConfig in each account. Set false where it already exists (e.g. Config was enabled in the console)."
  type        = bool
  default     = true
}

variable "guardduty_paid_features" {
  description = "GuardDuty protection plans kept OFF (they cost extra). Foundational detection (CloudTrail, VPC Flow, DNS) is always on."
  type        = list(string)
  default = [
    "S3_DATA_EVENTS",
    "EKS_AUDIT_LOGS",
    "EBS_MALWARE_PROTECTION",
    "RDS_LOGIN_EVENTS",
    "LAMBDA_NETWORK_LOGS",
    "RUNTIME_MONITORING",
  ]
}

variable "securityhub_standards" {
  description = "Security Hub standards enabled org-wide by the central configuration policy. Each extra standard adds paid security checks."
  type        = list(string)
  default     = ["aws-foundational-security-best-practices/v/1.0.0"]
}

variable "access_analyzer_archive_rules" {
  description = "Archive rules for expected external access. Key = rule name, value = filter criteria (Access Analyzer filter syntax)."
  type = map(map(object({
    eq       = optional(list(string))
    neq      = optional(list(string))
    contains = optional(list(string))
    exists   = optional(bool)
  })))
  default = {
    # Identity Center roles trust the AWSSSO SAML provider, which sits outside the org's zone of trust.
    "expected-identity-center-roles" = {
      resourceType = { eq = ["AWS::IAM::Role"] }
      resource     = { contains = ["/aws-reserved/sso.amazonaws.com/"] }
    }
  }
}
