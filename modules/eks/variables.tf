variable "name_prefix" { type = string }
variable "private_subnet_ids" { type = list(string) }

variable "kubernetes_version" {
  type    = string
  default = "1.36"
}

variable "endpoint_public_access" {
  description = "false = the Kubernetes API is only reachable from inside the VPC (or over the Client VPN). Recommended."
  type        = bool
  default     = false
}

variable "public_access_cidrs" {
  description = "If endpoint_public_access is true, restrict it to these CIDRs (your office/VPN egress IPs)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_pools" {
  type    = list(string)
  default = ["general-purpose", "system"]
}

variable "cluster_log_types" {
  type    = list(string)
  default = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "cluster_log_retention_days" {
  type    = number
  default = 90
}

variable "app_namespace" {
  type    = string
  default = "scribl"
}

variable "addons" {
  description = "EKS add-ons to install. Auto Mode already manages CoreDNS, kube-proxy, VPC CNI, EBS CSI and the load balancer controller, so those must NOT be listed here."
  type        = list(string)
  default     = ["metrics-server", "amazon-cloudwatch-observability"]
}

variable "cluster_admin_principal_arns" {
  description = "IAM role/user ARNs that get full cluster-admin via EKS access entries."
  type        = list(string)
  default     = []
}

variable "namespace_admin_principal_arns" {
  description = "IAM role ARNs (e.g. the GitHub deploy role) that get admin+edit scoped to app_namespace."
  type        = list(string)
  default     = []
}

variable "api_pod_role_arn" {
  description = "IAM role the scribl-api service account assumes via EKS Pod Identity."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
