variable "name_prefix" { type = string }
variable "queue_name" {
  type    = string
  default = "push-nudge"
}
variable "retention_seconds" {
  description = "4 days, matching dev."
  type        = number
  default     = 345600
}
variable "visibility_timeout_seconds" {
  description = "dev uses 30s on both queues."
  type        = number
  default     = 30
}
variable "max_receive_count" {
  type    = number
  default = 5
}
variable "alarm_email" {
  description = "Subscribed to the alarm topic. Empty = no subscription (you can add one in the console)."
  type        = string
  default     = ""
}
variable "tags" {
  type    = map(string)
  default = {}
}
