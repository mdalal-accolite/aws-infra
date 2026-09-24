variable "name_prefix" { type = string }
variable "project" {
  description = "Pool names follow the dev pattern scribl-mobile-<env> / scribl-admin-<env>."
  type        = string
  default     = "scribl"
}
variable "env_token" { type = string }
variable "domain_prefix" {
  description = "Globally unique Cognito hosted-UI prefix, e.g. scribl-stage-admin-auth"
  type        = string
}
variable "callback_urls_mobile" {
  type    = list(string)
  default = []
}
variable "callback_urls_admin_spa" {
  type    = list(string)
  default = []
}
variable "callback_urls_admin_bff" {
  type    = list(string)
  default = []
}
variable "tags" {
  type    = map(string)
  default = {}
}
