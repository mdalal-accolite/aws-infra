###############################################################################
# COMPONENT: 50-iam
# STATE KEY: <environment>/50-iam.tfstate
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

data "terraform_remote_state" "edge" {
  backend = "s3"
  config = {
    bucket = module.config.state_bucket
    key    = "${var.environment}/20-edge.tfstate"
    region = module.config.env.region
  }
}

data "terraform_remote_state" "registry" {
  backend = "s3"
  config = {
    bucket = module.config.state_bucket
    key    = "${var.environment}/30-registry.tfstate"
    region = module.config.env.region
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

data "terraform_remote_state" "email" {
  backend = "s3"
  config = {
    bucket = module.config.state_bucket
    key    = "${var.environment}/38-email.tfstate"
    region = module.config.env.region
  }
}

data "aws_caller_identity" "current" {}

module "iam" {
  source = "../../modules/iam"

  github_allowed_subjects = module.config.env.github_allowed_subjects

  cognito_pool_arns = data.terraform_remote_state.identity.outputs.pool_arns
  data_bucket_arn   = data.terraform_remote_state.edge.outputs.data_bucket_arn
  app_bucket_arn    = data.terraform_remote_state.edge.outputs.app_bucket_arn
  sqs_queue_arns = [
    data.terraform_remote_state.messaging.outputs.queue_arn,
    data.terraform_remote_state.messaging.outputs.dlq_arn,
  ]
  ecr_repository_arns         = data.terraform_remote_state.registry.outputs.repository_arns
  cloudfront_distribution_arn = data.terraform_remote_state.edge.outputs.cloudfront_distribution_arn

  secret_arn_prefix = "arn:aws:secretsmanager:${module.config.env.region}:${data.aws_caller_identity.current.account_id}:secret:${module.config.secret_prefix}/*"

  project          = module.config.project
  ses_identity_arn = data.terraform_remote_state.email.outputs.ses_identity_arn

  tags = module.config.tags
}

output "api_pod_role_arn" { value = module.iam.api_pod_role_arn }
output "github_api_deploy_role_arn" { value = module.iam.github_api_deploy_role_arn }
output "github_web_release_role_arn" { value = module.iam.github_web_release_role_arn }
