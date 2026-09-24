###############################################################################
# COMPONENT: 60-eks
# STATE KEY: <environment>/60-eks.tfstate
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

data "terraform_remote_state" "iam" {
  backend = "s3"
  config = {
    bucket = module.config.state_bucket
    key    = "${var.environment}/50-iam.tfstate"
    region = module.config.env.region
  }
}

module "eks" {
  source = "../../modules/eks"

  name_prefix        = module.config.name_prefix
  private_subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids

  kubernetes_version     = module.config.env.kubernetes_version
  endpoint_public_access = module.config.env.eks_endpoint_public_access
  public_access_cidrs    = module.config.env.eks_public_access_cidrs
  app_namespace          = module.config.env.app_namespace

  cluster_admin_principal_arns   = module.config.env.eks_cluster_admin_principal_arns
  namespace_admin_principal_arns = [data.terraform_remote_state.iam.outputs.github_api_deploy_role_arn]
  api_pod_role_arn               = data.terraform_remote_state.iam.outputs.api_pod_role_arn

  cluster_log_retention_days = module.config.env.log_retention_days

  tags = module.config.tags
}

output "cluster_name" { value = module.eks.cluster_name }
output "cluster_arn" { value = module.eks.cluster_arn }
output "cluster_endpoint" { value = module.eks.cluster_endpoint }
output "cluster_security_group_id" { value = module.eks.cluster_security_group_id }
output "kubeconfig_command" { value = module.eks.kubeconfig_command }
