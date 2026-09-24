variable "name_prefix" {
  description = "Prefix for all resource names, e.g. scribl-stage"
  type        = string
}

variable "vpc_cidr" {
  description = "IPv4 CIDR for the VPC. Must not overlap with other environments."
  type        = string
}

variable "az_count" {
  description = "How many Availability Zones to spread subnets across (2 or 3 recommended)."
  type        = number
  default     = 3
}

variable "single_nat_gateway" {
  description = "true = one NAT Gateway shared by all AZs (cheaper, single point of failure). false = one NAT Gateway per AZ (recommended for prod)."
  type        = bool
  default     = true
}

variable "admin_cidr_blocks" {
  description = "CIDRs allowed to reach admin ports (RDP/SSH) on the tools EC2 host. Leave empty to rely on SSM Session Manager only."
  type        = list(string)
  default     = []
}

variable "interface_endpoints" {
  description = "AWS service names for VPC interface endpoints (created in the private subnets)."
  type        = list(string)
  default = [
    "ecr.api",
    "ecr.dkr",
    "sts",
    "secretsmanager",
    "logs",
    "ssm",
    "ssmmessages",
    "ec2messages",
    "sqs",
    "kms",
    "elasticloadbalancing",
    "eks",
  ]
}

variable "tags" {
  description = "Extra tags merged into every resource in this module."
  type        = map(string)
  default     = {}
}
