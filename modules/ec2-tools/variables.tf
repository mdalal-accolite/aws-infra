variable "name_prefix" { type = string }
variable "subnet_id" {
  description = "A PRIVATE subnet id. No public IP is assigned."
  type        = string
}
variable "security_group_ids" { type = list(string) }

variable "instance_type" {
  type    = string
  default = "c8i.xlarge"
}

variable "root_volume_size" {
  type    = number
  default = 100
}

variable "public_key_openssh" {
  description = "Optional SSH public key. Leave empty and use SSM Session Manager instead."
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
