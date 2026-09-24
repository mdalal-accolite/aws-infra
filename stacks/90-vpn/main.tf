###############################################################################
# COMPONENT: 90-vpn
# STATE KEY: <environment>/90-vpn.tfstate
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

data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = module.config.state_bucket
    key    = "${var.environment}/10-network.tfstate"
    region = module.config.env.region
  }
}

module "client_vpn" {
  source = "../../modules/client-vpn"
  count  = module.config.env.enable_client_vpn ? 1 : 0

  name_prefix        = module.config.name_prefix
  vpc_id             = data.terraform_remote_state.network.outputs.vpc_id
  vpc_cidr           = data.terraform_remote_state.network.outputs.vpc_cidr
  subnet_ids         = data.terraform_remote_state.network.outputs.private_subnet_ids
  security_group_ids = [data.terraform_remote_state.network.outputs.sg_client_vpn_id]

  client_cidr_block                 = module.config.env.vpn_client_cidr_block
  server_certificate_arn            = module.config.env.vpn_server_certificate_arn
  client_root_certificate_chain_arn = module.config.env.vpn_client_root_certificate_chain_arn
  log_retention_days                = module.config.env.log_retention_days

  tags = module.config.tags
}

output "endpoint_id" {
  value = module.config.env.enable_client_vpn ? module.client_vpn[0].endpoint_id : null
}
output "dns_name" {
  value = module.config.env.enable_client_vpn ? module.client_vpn[0].dns_name : null
}
