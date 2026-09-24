variable "name_prefix" { type = string }
variable "secret_prefix" {
  description = "Slash-separated prefix, e.g. scribl/stage"
  type        = string
}
variable "log_retention_days" {
  description = "API Gateway access logs. dev uses 30 days."
  type        = number
  default     = 30
}

variable "service_event_log_retention_days" {
  description = "/aws/service-events/* log groups. dev uses 60 days."
  type        = number
  default     = 60
}

variable "alarm_topic_arn" {
  description = "SNS topic for the API error-rate alarm. Empty = no alarm."
  type        = string
  default     = ""
}
variable "admin_bff_client_id" {
  type    = string
  default = ""
}
variable "admin_bff_client_secret" {
  type      = string
  default   = ""
  sensitive = true
}
variable "tags" {
  type    = map(string)
  default = {}
}
