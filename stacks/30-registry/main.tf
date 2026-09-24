###############################################################################
# COMPONENT: 30-registry
# STATE KEY: <environment>/30-registry.tfstate
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

module "ecr" {
  source = "../../modules/ecr"

  name_prefix = module.config.name_prefix
  env_token   = module.config.env.name_token
  tags        = module.config.tags
}

output "repository_arns" { value = module.ecr.repository_arns }
output "repository_urls" { value = module.ecr.repository_urls }
output "repository_names" { value = module.ecr.repository_names }
