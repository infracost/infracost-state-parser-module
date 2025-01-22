
variable "organization_id" {
  description = "You Infracost organization ID. This is found in the settings of the Infracost dashboard"
  type        = string
}

variable "state_files" {
  description = "A list of s3 based state files to monitor"
  type        = list(string)
}

variable "log_level" {
  description = "The log level for the lambda function"
  type        = string
  default     = "info"
}

variable "state_bucket" {
  description = "The bucket where the state files are stored"
  type        = string
  default     = "infracost-incoming"
}

variable "parser_version" {
  description = "The version of the parser to use, leave as latest unless requestec to changin ti"
  type        = string
  default     = "latest"
}
