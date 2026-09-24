###############################################################################
# COMPONENT: 70-tools
# STATE KEY: <environment>/70-tools.tfstate
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

module "tools_ec2" {
  source = "../../modules/ec2-tools"
  count  = module.config.env.enable_tools_ec2 ? 1 : 0

  name_prefix        = module.config.name_prefix
  subnet_id          = data.terraform_remote_state.network.outputs.private_subnet_ids[0]
  security_group_ids = [data.terraform_remote_state.network.outputs.sg_ec2_tools_id]
  instance_type      = module.config.env.tools_instance_type
  public_key_openssh = module.config.env.tools_public_key_openssh

  tags = module.config.tags
}

output "instance_id" {
  value = module.config.env.enable_tools_ec2 ? module.tools_ec2[0].instance_id : null
}
output "private_ip" {
  value = module.config.env.enable_tools_ec2 ? module.tools_ec2[0].private_ip : null
}
output "connect_command" {
  value = module.config.env.enable_tools_ec2 ? module.tools_ec2[0].connect_command : null
}
