###############################################################################
# COMPONENT: 36-secrets
# STATE KEY: <environment>/36-secrets.tfstate
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

data "terraform_remote_state" "messaging" {
  backend = "s3"
  config = {
    bucket = module.config.state_bucket
    key    = "${var.environment}/32-messaging.tfstate"
    region = module.config.env.region
  }
}

data "terraform_remote_state" "identity" {
  backend = "s3"
  config = {
    bucket = module.config.state_bucket
    key    = "${var.environment}/34-identity.tfstate"
    region = module.config.env.region
  }
}

module "secrets" {
  source = "../../modules/secrets"

  name_prefix     = module.config.name_prefix
  secret_prefix   = module.config.secret_prefix
  alarm_topic_arn = data.terraform_remote_state.messaging.outputs.alarm_topic_arn

  admin_bff_client_id     = data.terraform_remote_state.identity.outputs.admin_bff_client_id
  admin_bff_client_secret = data.terraform_remote_state.identity.outputs.admin_bff_client_secret

  tags = module.config.tags
}

output "secret_arns" { value = module.secrets.secret_arns }
output "secret_names" { value = module.secrets.secret_names }
output "api_gateway_log_group_arn" { value = module.secrets.api_gateway_log_group_arn }
output "service_event_log_group_names" { value = module.secrets.service_event_log_group_names }
