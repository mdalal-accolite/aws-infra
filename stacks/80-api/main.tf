###############################################################################
# COMPONENT: 80-api
# STATE KEY: <environment>/80-api.tfstate
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

data "terraform_remote_state" "secrets" {
  backend = "s3"
  config = {
    bucket = module.config.state_bucket
    key    = "${var.environment}/36-secrets.tfstate"
    region = module.config.env.region
  }
}

module "api_gateway" {
  source = "../../modules/api-gateway"
  count  = module.config.env.enable_api_gateway ? 1 : 0

  name_prefix          = module.config.name_prefix
  stage_name           = var.environment
  nlb_arn              = module.config.env.nlb_arn
  access_log_group_arn = data.terraform_remote_state.secrets.outputs.api_gateway_log_group_arn

  tags = module.config.tags
}

output "rest_api_id" {
  value = module.config.env.enable_api_gateway ? module.api_gateway[0].rest_api_id : null
}
output "invoke_url" {
  value = module.config.env.enable_api_gateway ? module.api_gateway[0].invoke_url : null
}
