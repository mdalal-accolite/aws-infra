###############################################################################
# COMPONENT: 32-messaging
# STATE KEY: <environment>/32-messaging.tfstate
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

module "messaging" {
  source = "../../modules/messaging"

  name_prefix = module.config.name_prefix
  alarm_email = module.config.env.alarm_email

  tags = module.config.tags
}

output "queue_arn" { value = module.messaging.queue_arn }
output "queue_url" { value = module.messaging.queue_url }
output "dlq_arn" { value = module.messaging.dlq_arn }
output "alarm_topic_arn" { value = module.messaging.alarm_topic_arn }
