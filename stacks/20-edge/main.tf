###############################################################################
# COMPONENT: 20-edge
# STATE KEY: <environment>/20-edge.tfstate
#
# This component has its OWN Terraform state. Changing it plans and applies
# only these resources - nothing else in the account is touched or refreshed.
###############################################################################

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 6.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }

  backend "s3" {
    encrypt      = true
    use_lockfile = true
  }
}

variable "environment" {
  description = "stage or prod"
  type        = string
}

module "config" {
  source      = "../../config"
  environment = var.environment
}

provider "aws" {
  region              = module.config.env.region
  allowed_account_ids = [module.config.env.account_id]

  default_tags {
    tags = module.config.tags
  }
}

module "edge" {
  source = "../../modules/storage-cdn"

  name_prefix = module.config.name_prefix
  enable_waf  = module.config.env.enable_waf
  price_class = module.config.env.cloudfront_price_class

  # Only attached once you paste an ISSUED certificate ARN into config/main.tf.
  # While empty, CloudFront keeps its default certificate and no alias is set.
  certificate_arn = module.config.env.cloudfront_certificate_arn
  aliases         = module.config.env.cloudfront_aliases

  # Only set once the admin API's Kubernetes Service has created its NLB.
  admin_nlb_dns_name = module.config.env.admin_nlb_dns_name

  log_retention_days = module.config.env.log_retention_days

  tags = module.config.tags
}

output "app_bucket_name" { value = module.edge.app_bucket_name }
output "app_bucket_arn" { value = module.edge.app_bucket_arn }
output "data_bucket_name" { value = module.edge.data_bucket_name }
output "data_bucket_arn" { value = module.edge.data_bucket_arn }
output "cloudfront_distribution_id" { value = module.edge.cloudfront_distribution_id }
output "cloudfront_distribution_arn" { value = module.edge.cloudfront_distribution_arn }
output "cloudfront_domain_name" { value = module.edge.cloudfront_domain_name }
output "waf_web_acl_arn" { value = module.edge.waf_web_acl_arn }
output "bucket_suffix" { value = module.edge.bucket_suffix }
