###############################################################################
# COMPONENT: 40-data
# STATE KEY: <environment>/40-data.tfstate
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

data "terraform_remote_state" "messaging" {
  backend = "s3"
  config = {
    bucket = module.config.state_bucket
    key    = "${var.environment}/32-messaging.tfstate"
    region = module.config.env.region
  }
}

module "data" {
  source = "../../modules/data"

  name_prefix        = module.config.name_prefix
  vpc_id             = data.terraform_remote_state.network.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids

  postgres_engine_version         = module.config.env.postgres_engine_version
  postgres_parameter_group_family = module.config.env.postgres_parameter_group_family
  db_instance_class               = module.config.env.db_instance_class
  db_allocated_storage            = module.config.env.db_allocated_storage
  db_multi_az                     = module.config.env.db_multi_az
  db_deletion_protection          = module.config.env.db_deletion_protection
  db_backup_retention_days        = module.config.env.db_backup_retention_days
  db_skip_final_snapshot          = module.config.env.db_skip_final_snapshot
  db_security_group_ids           = [data.terraform_remote_state.network.outputs.sg_rds_id]
  db_proxy_security_group_ids     = [data.terraform_remote_state.network.outputs.sg_rds_proxy_id]
  enable_rds_proxy                = module.config.env.enable_rds_proxy

  redis_node_type          = module.config.env.redis_node_type
  redis_num_nodes          = module.config.env.redis_num_nodes
  redis_security_group_ids = [data.terraform_remote_state.network.outputs.sg_redis_id]

  alarm_topic_arn = data.terraform_remote_state.messaging.outputs.alarm_topic_arn

  tags = module.config.tags
}

output "db_instance_identifier" { value = module.data.db_instance_identifier }
output "db_endpoint" { value = module.data.db_endpoint }
output "db_port" { value = module.data.db_port }
output "db_master_secret_arn" { value = module.data.db_master_secret_arn }
output "db_proxy_endpoint" { value = module.data.db_proxy_endpoint }
output "redis_primary_endpoint" { value = module.data.redis_primary_endpoint }
output "redis_auth_secret_arn" { value = module.data.redis_auth_secret_arn }
output "redis_replication_group_id" { value = module.data.redis_replication_group_id }
