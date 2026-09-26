data "aws_caller_identity" "current" {}

# A short random token keeps the bucket name globally unique without putting
# the AWS account number into it. Committed bootstrap state keeps it stable.
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true

  lifecycle {
    ignore_changes = all
  }
}

locals {
  name_prefix  = "${var.project}-${var.environment}"
  state_bucket = "${local.name_prefix}-tfstate-${random_string.suffix.result}"
}

###############################################################################
# 1. Remote state bucket
#    S3 native locking (use_lockfile) replaces the old DynamoDB lock table.
###############################################################################
resource "aws_s3_bucket" "state" {
  bucket = local.state_bucket

  tags = { Name = local.state_bucket, Purpose = "terraform-state" }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration { noncurrent_days = 365 }
  }
}

###############################################################################
# 2. GitHub OIDC identity provider
#    Lets GitHub Actions get short-lived AWS credentials. No access keys ever.
###############################################################################
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # AWS no longer validates this thumbprint for GitHub's OIDC endpoint, but
  # the API still requires the field. This is GitHub's published value.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = { Name = "github-actions-oidc" }
}

data "aws_iam_openid_connect_provider" "github" {
  url        = "https://token.actions.githubusercontent.com"
  depends_on = [aws_iam_openid_connect_provider.github]
}

###############################################################################
# 3. Terraform CI roles
#    tf-plan  : read-only, for pull requests
#    tf-apply : can create/change infrastructure, gated by GitHub Environment
###############################################################################
data "aws_iam_policy_document" "state_access" {
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketVersioning"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }
}

# ---- plan role ----
resource "aws_iam_role" "tf_plan" {
  name        = "${local.name_prefix}-tf-plan"
  description = "Terraform plan (read-only) via GitHub OIDC"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        StringLike   = { "token.actions.githubusercontent.com:sub" = var.plan_subjects }
      }
    }]
  })

  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "tf_plan_readonly" {
  role       = aws_iam_role.tf_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "tf_plan_state" {
  name   = "terraform-state-access"
  role   = aws_iam_role.tf_plan.id
  policy = data.aws_iam_policy_document.state_access.json
}

# ---- apply role ----
resource "aws_iam_role" "tf_apply" {
  name        = "${local.name_prefix}-tf-apply"
  description = "Terraform apply via GitHub OIDC, gated by a GitHub Environment"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        StringLike   = { "token.actions.githubusercontent.com:sub" = var.apply_subjects }
      }
    }]
  })

  max_session_duration = 3600
}

# Terraform genuinely needs broad rights to create VPCs, EKS clusters and IAM
# roles. PowerUserAccess covers everything except IAM, so IAM is granted
# separately and explicitly below - that split makes the blast radius visible.
resource "aws_iam_role_policy_attachment" "tf_apply_poweruser" {
  role       = aws_iam_role.tf_apply.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

resource "aws_iam_role_policy" "tf_apply_iam" {
  name = "terraform-iam-management"
  role = aws_iam_role.tf_apply.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ManageServiceRoles"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:UpdateRole",
          "iam:UpdateRoleDescription",
          "iam:ListRoles",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:PassRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:TagInstanceProfile",
          "iam:CreateServiceLinkedRole",
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:ListEntitiesForPolicy",
        ]
        Resource = "*"
      },
      {
        # SES SMTP authentication is, unavoidably, an IAM user with an access
        # key - there is no other way to get SMTP credentials. It is created
        # under /service/ with a single ses:SendRawEmail permission and no
        # console access. CI may manage users and keys ONLY under that path.
        Sid    = "AllowServiceUsersUnderServicePathOnly"
        Effect = "Allow"
        Action = [
          "iam:CreateUser",
          "iam:DeleteUser",
          "iam:GetUser",
          "iam:TagUser",
          "iam:UntagUser",
          "iam:PutUserPolicy",
          "iam:DeleteUserPolicy",
          "iam:GetUserPolicy",
          "iam:ListUserPolicies",
          "iam:ListAttachedUserPolicies",
          "iam:CreateAccessKey",
          "iam:DeleteAccessKey",
          "iam:ListAccessKeys",
          "iam:UpdateAccessKey",
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/service/*"
      },
      {
        # Everything else about human identities stays denied.
        Sid    = "DenyTouchingHumanIdentities"
        Effect = "Deny"
        Action = [
          "iam:*User*",
          "iam:*AccessKey*",
        ]
        NotResource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/service/*"
      },
      {
        Sid    = "DenyGroupsAndConsoleAccess"
        Effect = "Deny"
        Action = [
          "iam:*Group*",
          "iam:*LoginProfile*",
          "iam:*SAMLProvider*",
          "iam:*AccountAlias*",
          "iam:CreateVirtualMFADevice",
          "iam:DeactivateMFADevice",
        ]
        Resource = "*"
      },
      {
        Sid    = "ProtectBootstrap"
        Effect = "Deny"
        Action = ["iam:DeleteRole", "iam:DeleteRolePolicy", "iam:DetachRolePolicy"]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.name_prefix}-tf-plan",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.name_prefix}-tf-apply",
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "tf_apply_state" {
  name   = "terraform-state-access"
  role   = aws_iam_role.tf_apply.id
  policy = data.aws_iam_policy_document.state_access.json
}
