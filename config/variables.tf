variable "environment" {
  description = "stage or prod"
  type        = string

  validation {
    condition     = contains(["stage", "prod"], var.environment)
    error_message = "environment must be \"stage\" or \"prod\"."
  }
}
