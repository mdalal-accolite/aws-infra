variable "name_prefix" { type = string }

variable "domain" {
  description = "Domain to verify for sending, e.g. stg.scribl.co"
  type        = string
}

variable "route53_zone_id" {
  description = "Route 53 hosted zone id for the domain. Empty (the case here) means the module outputs the records for you to publish yourself."
  type        = string
  default     = ""
}

variable "wait_for_verification" {
  description = "Block the apply until AWS confirms the domain is verified. Only safe when Route 53 is publishing the records, otherwise the apply times out after 45 minutes."
  type        = bool
  default     = false
}

variable "create_smtp_user" {
  description = "Create the SES SMTP credentials (an IAM user plus an access key whose v4-signed secret is the SMTP password) and store them in Secrets Manager. dev has the equivalent as ses-smtp-user.20260916-213932."
  type        = bool
  default     = true
}

variable "smtp_secret_arn" {
  description = "Secrets Manager secret to write the SMTP credentials into. Created by the secrets component."
  type        = string
  default     = ""
}

variable "region" {
  description = "Used to build the SMTP endpoint hostname."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
