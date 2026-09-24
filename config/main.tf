###############################################################################
# Shared environment configuration.
#
# Every per-component stack calls this module so that all environment-specific
# values live in ONE file. To change something for stage, edit the "stage" block
# below - not thirteen separate stack directories.
###############################################################################

locals {
  # Naming: scribl-<environment>-<resource_type>
  project = "scribl"

  environments = {
    ############################## STAGE ####################################
    stage = {
      account_id  = "419717495525" # Scribl stage account
      name_token  = "stage"        # resource names read scribl-stage-*, mirroring dev's scribl-dev-*
      region      = "us-east-1"
      owner       = "platform-team"
      cost_center = "engineering"

      # --- network ---
      vpc_cidr           = "10.20.0.0/16"
      az_count           = 3
      single_nat_gateway = true
      admin_cidr_blocks  = []

      # --- switches ---
      enable_tools_ec2   = true
      enable_client_vpn  = false
      enable_api_gateway = false
      enable_rds_proxy   = true
      enable_waf         = true
      enable_ses         = true

      # --- eks ---
      kubernetes_version         = "1.36"
      eks_endpoint_public_access = false
      eks_public_access_cidrs    = []
      app_namespace              = "scribl"
      eks_cluster_admin_principal_arns = [
        # "arn:aws:iam::419717495525:role/aws-reserved/sso.amazonaws.com/us-east-1/AWSReservedSSO_AdministratorAccess_abc123",
      ]

      # --- data ---
      postgres_engine_version         = "18.3"
      postgres_parameter_group_family = "postgres18"
      db_instance_class               = "db.r8g.large"
      db_allocated_storage            = 100
      db_multi_az                     = false
      db_deletion_protection          = false
      db_backup_retention_days        = 7
      db_skip_final_snapshot          = true
      redis_node_type                 = "cache.t4g.micro"
      redis_num_nodes                 = 1

      # --- tools host ---
      tools_instance_type      = "c8i.xlarge"
      tools_public_key_openssh = ""

      # --- github / ci ---
      github_org  = "ScriblOrg"
      github_repo = "scribl-infra"
      github_allowed_subjects = [
        "repo:ScriblOrg/scribl-infra:ref:refs/heads/main",
        "repo:ScriblOrg/scribl-infra:environment:stage",
      ]

      # --- edge / identity ---
      cognito_domain_prefix           = "scribl-stage-admin-auth" # globally unique
      cognito_callback_urls_mobile    = ["https://example.invalid/callback"]
      cognito_callback_urls_admin_spa = ["http://localhost:5173/admin/callback"]
      cognito_callback_urls_admin_bff = ["http://localhost:3000/admin/auth/callback"]

      # --- SES (domain + DKIM only; no email identities, no custom MAIL FROM) ---
      ses_domain           = "stg.scribl.co"
      ses_route53_zone_id  = "" # no Route 53 zone here; records published manually
      ses_create_smtp_user = true


      # --- CloudFront ---
      # ACM is no longer managed by Terraform. Issue/import the certificate for
      # mweb.stage.scribl.co yourself, then paste its ARN here.
      #
      # IMPORTANT: CloudFront REJECTS an alias that has no custom certificate
      # ("InvalidViewerCertificate"). So the alias below is only applied once
      # cloudfront_certificate_arn is non-empty. Until then the distribution
      # serves on its default *.cloudfront.net name.
      cloudfront_certificate_arn = ""
      cloudfront_aliases         = ["mweb.stage.scribl.co"]
      cloudfront_price_class     = "PriceClass_All"
      # DNS name of the k8s-created ADMIN API NLB. Empty = the /v1/admin/* and
      # /admin* behaviours are not created.
      admin_nlb_dns_name = ""

      # --- api gateway (set after the k8s NLB exists) ---
      nlb_arn = ""

      # --- client vpn (needs ACM certs) ---
      # AWS requires the client CIDR to be between /12 and /22. A /24 is
      # rejected. It must not overlap the VPC (10.20.0.0/16) or any route on
      # the endpoint, and it CANNOT be changed after the endpoint is created.
      vpn_client_cidr_block                 = "10.100.0.0/22"
      vpn_server_certificate_arn            = ""
      vpn_client_root_certificate_chain_arn = ""

      # --- ops ---
      alarm_email        = ""
      log_retention_days = 30
    }

    ############################## PROD #####################################
    prod = {
      account_id  = "882781045478" # Scribl prod account
      name_token  = "prod"
      region      = "us-east-1"
      owner       = "platform-team"
      cost_center = "engineering"

      vpc_cidr           = "10.30.0.0/16"
      az_count           = 3
      single_nat_gateway = false
      admin_cidr_blocks  = []

      enable_tools_ec2   = false
      enable_client_vpn  = false
      enable_api_gateway = false
      enable_rds_proxy   = true
      enable_waf         = true
      enable_ses         = true

      kubernetes_version               = "1.36"
      eks_endpoint_public_access       = false
      eks_public_access_cidrs          = []
      app_namespace                    = "scribl"
      eks_cluster_admin_principal_arns = []

      postgres_engine_version         = "18.3"
      postgres_parameter_group_family = "postgres18"
      db_instance_class               = "db.r8g.xlarge"
      db_allocated_storage            = 200
      db_multi_az                     = true
      db_deletion_protection          = true
      db_backup_retention_days        = 30
      db_skip_final_snapshot          = false
      redis_node_type                 = "cache.m7g.large"
      redis_num_nodes                 = 2

      tools_instance_type      = "c8i.xlarge"
      tools_public_key_openssh = ""

      github_org  = "ScriblOrg"
      github_repo = "scribl-infra"
      github_allowed_subjects = [
        "repo:ScriblOrg/scribl-infra:environment:prod",
      ]

      cognito_domain_prefix           = "scribl-prod-admin-auth"
      cognito_callback_urls_mobile    = ["https://example.invalid/callback"]
      cognito_callback_urls_admin_spa = []
      cognito_callback_urls_admin_bff = []

      ses_domain           = "scribl.co"
      ses_route53_zone_id  = ""
      ses_create_smtp_user = true


      cloudfront_certificate_arn = ""
      cloudfront_aliases         = ["mweb.scribl.co"]
      cloudfront_price_class     = "PriceClass_All"
      admin_nlb_dns_name         = ""

      nlb_arn = ""

      vpn_client_cidr_block                 = "10.110.0.0/22"
      vpn_server_certificate_arn            = ""
      vpn_client_root_certificate_chain_arn = ""

      alarm_email        = ""
      log_retention_days = 90
    }
  }

  env = local.environments[var.environment]

  # scribl-stg / scribl-prod - the token comes from the env block so that
  # resource names match the DNS names (stg.scribl.co), while directory and
  # state-key names stay the more readable "stage".
  name_prefix = "${local.project}-${local.env.name_token}"

  # Secrets Manager uses a slash hierarchy so one IAM wildcard covers the env.
  secret_prefix = "${local.project}/${local.env.name_token}"

  # Terraform state bucket, created by bootstrap/
  # The Terraform state bucket name is NOT computed here. bootstrap/ generates
  # it with a random suffix (so the account number stays out of the name), which
  # means it cannot be derived - only read.
  #
  # envs/<environment>.backend.hcl is the single source of truth: it is what
  # `terraform init -backend-config=...` uses, so reading the same file here
  # guarantees the remote-state data sources point at the same bucket. Paste the
  # bootstrap output into that ONE file and everything follows.
  state_bucket = regex("(?m)^\\s*bucket\\s*=\\s*\"([^\"]+)\"",
    file("${path.module}/../envs/${var.environment}.backend.hcl"))[0]

  tags = {
    Project     = local.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Repository  = "${local.env.github_org}/${local.env.github_repo}"
    CostCenter  = local.env.cost_center
    Owner       = local.env.owner
  }
}
