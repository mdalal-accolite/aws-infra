variable "name_prefix" { type = string }
variable "vpc_id" { type = string }
variable "vpc_cidr" { type = string }
variable "subnet_ids" {
  description = "Private subnets to associate the VPN with (one per AZ you want reachable)."
  type        = list(string)
}
variable "security_group_ids" { type = list(string) }

variable "client_cidr_block" {
  description = "CIDR handed out to VPN clients. Must not overlap the VPC."
  type        = string
  default     = "10.100.0.0/16"
}

variable "server_certificate_arn" {
  description = "ACM ARN of the SERVER certificate. You import this outside Terraform (see docs/03)."
  type        = string
}

variable "client_root_certificate_chain_arn" {
  description = "ACM ARN of the CLIENT root certificate chain, for mutual (cert) auth."
  type        = string
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "tags" {
  type    = map(string)
  default = {}
}
