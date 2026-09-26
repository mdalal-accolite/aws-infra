###############################################################################
# COMPONENT: 10-network
# STATE KEY: <environment>/10-network.tfstate
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

module "network" {
  source = "../../modules/network"

  name_prefix        = module.config.name_prefix
  vpc_cidr           = module.config.env.vpc_cidr
  az_count           = module.config.env.az_count
  single_nat_gateway = module.config.env.single_nat_gateway
  admin_cidr_blocks  = module.config.env.admin_cidr_blocks
  # Only open VPN-sourced ingress when a Client VPN endpoint actually exists for
  # this environment - config always carries a CIDR value, but that alone
  # doesn't mean 90-vpn has been applied.
  vpn_client_cidr_block = module.config.env.enable_client_vpn ? module.config.env.vpn_client_cidr_block : ""

  tags = module.config.tags
}

output "vpc_id" { value = module.network.vpc_id }
output "vpc_cidr" { value = module.network.vpc_cidr }
output "private_subnet_ids" { value = module.network.private_subnet_ids }
output "public_subnet_ids" { value = module.network.public_subnet_ids }
output "availability_zones" { value = module.network.availability_zones }
output "sg_rds_id" { value = module.network.sg_rds_id }
output "sg_rds_proxy_id" { value = module.network.sg_rds_proxy_id }
output "sg_redis_id" { value = module.network.sg_redis_id }
output "sg_ec2_tools_id" { value = module.network.sg_ec2_tools_id }
output "sg_client_vpn_id" { value = module.network.sg_client_vpn_id }
output "nat_gateway_public_ips" { value = module.network.nat_gateway_public_ips }
