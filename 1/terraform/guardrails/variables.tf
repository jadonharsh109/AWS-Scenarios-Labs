variable "region" {
  description = "Home region."
  type        = string
  default     = "us-east-1"
}

variable "owner" {
  description = "Owner tag value (team or person responsible)."
  type        = string
}

variable "policies_dir" {
  description = "Directory holding the policy JSON files, relative to this stack."
  type        = string
  default     = "../../policies"
}

variable "policies" {
  description = <<-EOT
    Organization policies keyed by policy name. file is relative to policies_dir.
    targets are "Root", an OU name, or an account name (all must exist in the org).
  EOT
  type = map(object({
    type        = string
    file        = string
    description = string
    targets     = list(string)
  }))

  validation {
    condition = alltrue([
      for p in values(var.policies) :
      contains(["SERVICE_CONTROL_POLICY", "TAG_POLICY", "DECLARATIVE_POLICY_EC2"], p.type)
    ])
    error_message = "type must be SERVICE_CONTROL_POLICY, TAG_POLICY or DECLARATIVE_POLICY_EC2."
  }

  # Organizations allows 5 SCPs per target, and the AWS-managed FullAWSAccess takes one slot.
  validation {
    condition = alltrue([
      for target in distinct(flatten([for p in values(var.policies) : p.targets if p.type == "SERVICE_CONTROL_POLICY"])) :
      length([for p in values(var.policies) : p if p.type == "SERVICE_CONTROL_POLICY" && contains(p.targets, target)]) <= 4
    ])
    error_message = "At most 4 custom SCPs per target (5 including FullAWSAccess). Merge statements into fewer policies."
  }
}
