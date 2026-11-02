variable "create_service_linked_role" {
  description = "Create AWSServiceRoleForConfig. Set false if the account already has it."
  type        = bool
  default     = true
}

variable "include_global_resource_types" {
  description = "Record global resources (IAM). Enable in exactly one region per account to avoid duplicate charges."
  type        = bool
  default     = true
}

variable "retention_days" {
  description = "Days to keep Config history and snapshot files."
  type        = number
  default     = 30
}

variable "force_destroy_bucket" {
  description = "Allow destroying the delivery bucket even when it holds objects (lab convenience)."
  type        = bool
  default     = false
}
