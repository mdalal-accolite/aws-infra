variable "name_prefix" { type = string }
variable "stage_name" {
  description = "API Gateway stage name, e.g. stage or prod"
  type        = string
}

variable "nlb_arn" {
  description = <<-EOT
    ARN of the internal Network Load Balancer that Kubernetes created for the
    scribl-api Service. You only know this AFTER the Service is applied, which
    is why this module is gated behind enable_api_gateway.
  EOT
  type        = string
}

variable "access_log_group_arn" { type = string }

variable "xray_tracing_enabled" {
  description = "dev has X-Ray tracing on for the stage."
  type        = bool
  default     = true
}

variable "throttling_burst_limit" {
  type    = number
  default = 5000
}

variable "throttling_rate_limit" {
  type    = number
  default = 10000
}

variable "tags" {
  type    = map(string)
  default = {}
}
