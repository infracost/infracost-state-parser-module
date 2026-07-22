variable "organization_id" {
  description = "Infracost organization ID shown in the Infracost dashboard"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$", var.organization_id))
    error_message = "organization_id must contain only letters, numbers, '.', '_', or '-' and may not contain path or wildcard characters."
  }
}

variable "state_files" {
  description = "S3 object paths or glob patterns containing Terraform state"
  type        = list(string)

  validation {
    condition = length(var.state_files) > 0 && alltrue([
      for source in var.state_files : can(regex("^s3://[^/]+/.+$", source))
    ])
    error_message = "state_files must contain valid s3://bucket/key paths."
  }
}

variable "schedule_period" {
  description = "ISO 8601 period between parser runs; supports whole minutes, hours, or days"
  type        = string
  default     = "PT1H"

  validation {
    condition = try(
      (
        try(tonumber(regex("^P([1-9][0-9]*)D$", var.schedule_period)[0]) * 86400, 0) +
        try(tonumber(regex("^PT([1-9][0-9]*)H$", var.schedule_period)[0]) * 3600, 0) +
        try(tonumber(regex("^PT([1-9][0-9]*)M$", var.schedule_period)[0]) * 60, 0)
      ) >= 600 &&
      (
        try(tonumber(regex("^P([1-9][0-9]*)D$", var.schedule_period)[0]) * 86400, 0) +
        try(tonumber(regex("^PT([1-9][0-9]*)H$", var.schedule_period)[0]) * 3600, 0) +
        try(tonumber(regex("^PT([1-9][0-9]*)M$", var.schedule_period)[0]) * 60, 0)
      ) <= 604800,
      false,
    )
    error_message = "schedule_period must be an ISO 8601 whole-minute, whole-hour, or whole-day period between PT10M and P7D."
  }
}

variable "state_kms_key_arns" {
  description = "Customer-managed KMS keys used to encrypt configured Terraform state objects"
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for arn in var.state_kms_key_arns : can(regex("^arn:aws:kms:[a-z]{2}-[a-z]+-[0-9]:[0-9]{12}:key/[A-Za-z0-9-]+$", arn))
    ])
    error_message = "state_kms_key_arns must contain explicit KMS key ARNs; aliases and wildcards are not accepted."
  }
}

variable "log_level" {
  description = "Parser log level"
  type        = string
  default     = "info"

  validation {
    condition     = contains(["debug", "info", "warn", "error"], lower(var.log_level))
    error_message = "log_level must be debug, info, warn, or error."
  }
}

variable "state_bucket" {
  description = "Infracost-owned bucket that receives sanitized parser reports"
  type        = string
  default     = "infracost-incoming"

  validation {
    condition = (
      can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.state_bucket)) &&
      !strcontains(var.state_bucket, "..") &&
      !can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$", var.state_bucket))
    )
    error_message = "state_bucket must be one exact, valid S3 bucket name; paths and wildcards are not accepted."
  }
}
