###############################################################################
# COMPONENT: 38-email
# STATE KEY: <environment>/38-email.tfstate
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

module "ses" {
  source = "../../modules/ses"
  count  = module.config.env.enable_ses ? 1 : 0

  name_prefix     = module.config.name_prefix
  domain          = module.config.env.ses_domain
  route53_zone_id = module.config.env.ses_route53_zone_id
  region          = module.config.env.region

  create_smtp_user = module.config.env.ses_create_smtp_user
  smtp_secret_arn  = data.terraform_remote_state.secrets.outputs.secret_arns["ses/smtp-credentials"]

  # Only safe to wait when Route 53 is publishing the records for us.
  wait_for_verification = module.config.env.ses_route53_zone_id != ""

  tags = module.config.tags
}

output "ses_domain" {
  value = module.config.env.enable_ses ? module.ses[0].domain : null
}
output "ses_identity_arn" {
  value = module.config.env.enable_ses ? module.ses[0].domain_identity_arn : ""
}
output "ses_smtp_username" {
  value = module.config.env.enable_ses ? module.ses[0].smtp_username : null
}
output "ses_smtp_endpoint" {
  value = module.config.env.enable_ses ? module.ses[0].smtp_endpoint : null
}
output "ses_route53_managed" {
  value = module.config.env.enable_ses ? module.ses[0].route53_managed : null
}

# THE IMPORTANT ONE: the records you must publish in DNS.
#   terraform output -json dns_records | python3 -m json.tool
output "dns_records" {
  description = "Publish these in your DNS provider to verify the domain."
  value       = module.config.env.enable_ses ? module.ses[0].dns_records : []
}
