variable "project" {
  description = "Role names follow the dev pattern scribl-api-pod / scribl-github-*. Each environment is its own AWS account, so there is no name collision."
  type        = string
  default     = "scribl"
}

variable "github_allowed_subjects" {
  description = "GitHub OIDC 'sub' patterns allowed to assume the app deploy roles. Scope these tightly."
  type        = list(string)
}

variable "cognito_pool_arns" { type = list(string) }
variable "data_bucket_arn" { type = string }
variable "app_bucket_arn" { type = string }
variable "sqs_queue_arns" { type = list(string) }
variable "ecr_repository_arns" { type = list(string) }
variable "secret_arn_prefix" {
  description = "Wildcard ARN covering this environment's secrets, e.g. arn:aws:secretsmanager:us-east-1:123:secret:scribl/stage/*"
  type        = string
}
variable "cloudfront_distribution_arn" { type = string }

variable "tags" {
  type    = map(string)
  default = {}
}

variable "ses_identity_arn" {
  description = "SES domain identity ARN the pods may send from. Empty = no SES permission."
  type        = string
  default     = ""
}


