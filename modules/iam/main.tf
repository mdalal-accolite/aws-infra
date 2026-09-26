# The GitHub OIDC provider is created once per account by the bootstrap stack.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

###############################################################################
# scribl-api-pod: what the application pods can do at runtime
# Assumed via EKS Pod Identity by the scribl-api service account.
###############################################################################
resource "aws_iam_role" "api_pod" {
  name        = "${var.project}-api-pod"
  description = "Runtime permissions for the scribl-api pods"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "api_pod" {
  name = "app-runtime"
  role = aws_iam_role.api_pod.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid    = "CognitoSelfServiceAuth"
        Effect = "Allow"
        Action = [
          "cognito-idp:SignUp",
          "cognito-idp:ConfirmSignUp",
          "cognito-idp:ResendConfirmationCode",
          "cognito-idp:InitiateAuth",
          "cognito-idp:RespondToAuthChallenge",
          "cognito-idp:ForgotPassword",
          "cognito-idp:ConfirmForgotPassword",
          "cognito-idp:ChangePassword",
          "cognito-idp:GetUser",
          "cognito-idp:UpdateUserAttributes",
          "cognito-idp:GlobalSignOut",
          "cognito-idp:AdminGetUser",
          "cognito-idp:AdminCreateUser",
          "cognito-idp:AdminInitiateAuth",
          "cognito-idp:AdminRespondToAuthChallenge",
        ]
        Resource = var.cognito_pool_arns
      },
      {
        Sid    = "MediaBucketObjects"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:HeadObject",
          "s3:DeleteObject",
        ]
        Resource = ["${var.data_bucket_arn}/*"]
      },
      {
        Sid      = "MediaBucketList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [var.data_bucket_arn]
      },
      {
        Sid    = "PushNudgeQueue"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
        ]
        Resource = var.sqs_queue_arns
      },
      {
        Sid      = "ReadOwnSecrets"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [var.secret_arn_prefix]
      }
      ],
      var.ses_identity_arn == "" ? [] : [
        {
          Sid    = "SendEmailViaSes"
          Effect = "Allow"
          Action = [
            "ses:SendEmail",
            "ses:SendRawEmail",
            "ses:SendTemplatedEmail",
          ]
          Resource = [var.ses_identity_arn]
        }
    ])
  })
}

###############################################################################
# GitHub Actions: application deploy role (containers -> ECR -> EKS)
# Replaces dev's scribl-github-api-deploy.
###############################################################################
resource "aws_iam_role" "github_api_deploy" {
  name        = "${var.project}-github-api-deploy"
  description = "CI/CD: build and push images, then roll out the EKS deployment"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = var.github_allowed_subjects
        }
      }
    }]
  })

  max_session_duration = 3600
  tags                 = var.tags
}

resource "aws_iam_role_policy" "github_api_deploy" {
  name = "ecr-and-eks-deploy"
  role = aws_iam_role.github_api_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrLogin"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "EcrPushPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:DescribeImages",
          "ecr:DescribeRepositories",
        ]
        Resource = var.ecr_repository_arns
      },
      {
        Sid      = "DescribeCluster"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster", "eks:ListClusters"]
        Resource = "*"
      },
      {
        Sid      = "ReadDeploySecrets"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = [var.secret_arn_prefix]
      }
    ]
  })
}

###############################################################################
# GitHub Actions: web release role (static SPA -> S3 -> CloudFront invalidation)
# Replaces dev's scribl-github-web-release.
###############################################################################
resource "aws_iam_role" "github_web_release" {
  name        = "${var.project}-github-web-release"
  description = "CI/CD: publish the SPA to S3 and invalidate CloudFront"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = var.github_allowed_subjects
        }
      }
    }]
  })

  max_session_duration = 3600
  tags                 = var.tags
}

resource "aws_iam_role_policy" "github_web_release" {
  name = "s3-publish-and-invalidate"
  role = aws_iam_role.github_web_release.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [var.app_bucket_arn]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = ["${var.app_bucket_arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"]
        Resource = [var.cloudfront_distribution_arn]
      }
    ]
  })
}
