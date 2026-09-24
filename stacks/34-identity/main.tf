###############################################################################
# COMPONENT: 34-identity
# STATE KEY: <environment>/34-identity.tfstate
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

module "cognito" {
  source = "../../modules/cognito"

  name_prefix             = module.config.name_prefix
  project                 = module.config.project
  env_token               = module.config.env.name_token
  domain_prefix           = module.config.env.cognito_domain_prefix
  callback_urls_mobile    = module.config.env.cognito_callback_urls_mobile
  callback_urls_admin_spa = module.config.env.cognito_callback_urls_admin_spa
  callback_urls_admin_bff = module.config.env.cognito_callback_urls_admin_bff

  tags = module.config.tags
}

output "mobile_pool_id" { value = module.cognito.mobile_pool_id }
output "mobile_pool_arn" { value = module.cognito.mobile_pool_arn }
output "mobile_client_id" { value = module.cognito.mobile_client_id }
output "admin_pool_id" { value = module.cognito.admin_pool_id }
output "admin_pool_arn" { value = module.cognito.admin_pool_arn }
output "admin_spa_client_id" { value = module.cognito.admin_spa_client_id }
output "admin_bff_client_id" { value = module.cognito.admin_bff_client_id }
output "admin_bff_client_secret" {
  value     = module.cognito.admin_bff_client_secret
  sensitive = true
}
output "admin_domain" { value = module.cognito.admin_domain }
output "pool_arns" { value = module.cognito.pool_arns }
