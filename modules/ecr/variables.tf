variable "name_prefix" { type = string }
variable "env_token" { type = string }

variable "repositories" {
  description = "Base app names. Final repo name is <app>-<env_token>, e.g. scribl-mobile-app-stage."
  type        = list(string)
  default     = ["scribl-mobile-app", "meta-scribl-mobile-app"]
}
variable "image_tag_mutability" {
  type    = string
  default = "MUTABLE"
}
variable "keep_last_n_images" {
  type    = number
  default = 30
}
variable "tags" {
  type    = map(string)
  default = {}
}
