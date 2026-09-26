variable "project" {
  type    = string
  default = "scribl"
}

variable "environment" {
  description = "stage or prod - determines names and how tightly CI is scoped."
  type        = string
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "github_org" {
  description = "e.g. ScriblOrg"
  type        = string
}

variable "github_repo" {
  description = "e.g. Infra-Scribl"
  type        = string
}

variable "plan_subjects" {
  description = <<-EOT
    OIDC subjects allowed to run `terraform plan` (read-only).
    Typically pull requests: repo:ORG/REPO:pull_request
  EOT
  type        = list(string)
}

variable "apply_subjects" {
  description = <<-EOT
    OIDC subjects allowed to run `terraform apply`.
    Scope this to a GitHub Environment so you get approval gates:
      repo:ORG/REPO:environment:stage
      repo:ORG/REPO:environment:prod
  EOT
  type        = list(string)
}

variable "create_oidc_provider" {
  description = "Set to false if the GitHub OIDC provider already exists in this account."
  type        = bool
  default     = true
}
