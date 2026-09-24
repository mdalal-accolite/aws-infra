variable "name_prefix" { type = string }

variable "bucket_suffix" {
  description = "Optional fixed suffix for the S3 bucket names. Leave empty and a stable 6-character random token is generated instead. No AWS account id is ever used."
  type        = string
  default     = ""
}

variable "enable_waf" {
  type    = bool
  default = true
}

variable "waf_rate_limit" {
  description = "Requests per 5 minutes per IP before WAF starts blocking."
  type        = number
  default     = 2000
}

variable "price_class" {
  description = "PriceClass_All matches dev (\"Use all edge locations\")."
  type        = string
  default     = "PriceClass_All"
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the custom domain. MUST be ISSUED. Empty = CloudFront keeps its default *.cloudfront.net certificate and no alias is attached."
  type        = string
  default     = ""
}

variable "aliases" {
  description = "Alternate domain names. Only applied when certificate_arn is set."
  type        = list(string)
  default     = []
}

variable "admin_nlb_dns_name" {
  description = "DNS name of the Kubernetes-created ADMIN API NLB. Empty = the /v1/admin/* and /admin* behaviours are not created, exactly as in dev before the admin pod existed."
  type        = string
  default     = ""
}

variable "enable_standard_logging" {
  description = "CloudFront standard access logs to a dedicated bucket (dev has this On, cookie logging Off)."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  type    = number
  default = 60
}

variable "tags" {
  type    = map(string)
  default = {}
}
