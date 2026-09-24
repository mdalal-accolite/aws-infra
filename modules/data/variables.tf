variable "name_prefix" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }

# ---- RDS ----
variable "postgres_engine_version" {
  description = "RDS PostgreSQL version. Pinned to the version the dev account runs (18.3). Use just \"18\" to always take the newest 18.x instead."
  type        = string
  default     = "18.3"
}
variable "postgres_parameter_group_family" {
  type    = string
  default = "postgres18"
}
variable "db_instance_class" {
  type    = string
  default = "db.r8g.large"
}
variable "db_allocated_storage" {
  type    = number
  default = 100
}
variable "db_max_allocated_storage" {
  description = "Upper bound for RDS storage autoscaling. Set equal to db_allocated_storage to disable."
  type        = number
  default     = 500
}
variable "db_name" {
  type    = string
  default = "scribl"
}
variable "db_master_username" {
  type    = string
  default = "scribl_admin"
}
variable "db_multi_az" {
  type    = bool
  default = false
}
variable "db_deletion_protection" {
  type    = bool
  default = false
}
variable "db_backup_retention_days" {
  type    = number
  default = 7
}
variable "db_skip_final_snapshot" {
  type    = bool
  default = true
}
variable "db_security_group_ids" { type = list(string) }
variable "db_proxy_security_group_ids" { type = list(string) }
variable "enable_rds_proxy" {
  description = "RDS Proxy adds connection pooling. Confirm your Postgres major version is supported before enabling."
  type        = bool
  default     = true
}

# ---- Redis ----
variable "redis_engine_version" {
  type    = string
  default = "7.1"
}
variable "redis_node_type" {
  type    = string
  default = "cache.t4g.micro"
}
variable "redis_num_nodes" {
  type    = number
  default = 1
}
variable "redis_security_group_ids" { type = list(string) }
variable "redis_transit_encryption_enabled" {
  description = "TLS in transit. Requires the app's Redis client to connect over TLS."
  type        = bool
  default     = true
}
variable "redis_auth_token_enabled" {
  description = "Require an auth token (password). Stored in Secrets Manager. Requires transit encryption."
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "alarm_topic_arn" {
  description = "SNS topic for RDS/Redis alarms. Empty = create the resources without alarms."
  type        = string
  default     = ""
}
