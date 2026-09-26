# IAM, roles, policies, and GitHub access

You asked what roles, access, and policies are needed for one repository driving two AWS
accounts. This is the complete answer.

## The shape of it

```
GitHub repo: ScriblOrg/Infra-Scribl
   │
   │  a workflow run requests an OIDC token from GitHub.
   │  the token contains a "sub" claim describing exactly what is running.
   │  This repo (and scribl-mobile-app) has GitHub's "immutable subject" OIDC
   │  customization enabled - Settings -> Actions -> General -> subject claims,
   │  or `gh api repos/<org>/<repo>/actions/oidc/customization/sub` - which
   │  replaces the plain repo:ORG/REPO prefix with repo:ORG@ORG_ID/REPO@REPO_ID:
   │      repo:ScriblOrg@129197376/Infra-Scribl@1371735174:pull_request
   │      repo:ScriblOrg@129197376/Infra-Scribl@1371735174:ref:refs/heads/main
   │      repo:ScriblOrg@129197376/Infra-Scribl@1371735174:environment:prod
   │
   ├──────────────────────────► STAGE AWS ACCOUNT (419717495525)
   │                              OIDC provider: token.actions.githubusercontent.com
   │                              ├── scribl-stage-tf-plan     (read-only)
   │                              ├── scribl-stage-tf-apply    (builds infrastructure)
   │                              ├── scribl-stage-api-pod             (app runtime)
   │                              ├── scribl-stage-github-api-deploy   (app CI/CD)
   │                              └── scribl-stage-github-web-release  (SPA CI/CD)
   │
   └──────────────────────────► PROD AWS ACCOUNT (222222222222)
                                  OIDC provider: token.actions.githubusercontent.com
                                  ├── scribl-prod-tf-plan
                                  ├── scribl-prod-tf-apply
                                  ├── scribl-prod-api-pod
                                  ├── scribl-prod-github-api-deploy
                                  └── scribl-prod-github-web-release
```

Every role in each account is created by Terraform. Nothing is shared between accounts.
**No AWS access keys exist anywhere** — every credential is a short-lived token, minutes long.

## Why OIDC instead of access keys

An access key stored in GitHub Secrets is a permanent credential. If it leaks it works forever,
from anywhere, until someone notices. OIDC gives GitHub a signed, one-minute-lifetime assertion
about *what workflow in what repository on what branch* is running, and IAM decides whether that
specific thing may assume a role. A leaked log line is worthless.

The dev account already does this; the inventory shows the
`token.actions.githubusercontent.com` provider and three roles trusting it. This repo keeps that
pattern and tightens the trust conditions.

---

## The four infrastructure roles

### 1. `scribl-<env>-tf-plan` — read-only, for pull requests

**Created by:** `bootstrap/main.tf`
**Trusted subjects:** `repo:ORG/REPO:pull_request`
**Policies:** AWS-managed `ReadOnlyAccess`, plus read/write on the state bucket only.

A plan needs to read every resource to compute a diff, and needs to write the state lock file.
It must not be able to change anything else. This is the role that runs on every PR, including
PRs from people whose code you have not read yet.

### 2. `scribl-<env>-tf-apply` — creates and destroys infrastructure

**Created by:** `bootstrap/main.tf`
**Trusted subjects:**
- stage: `repo:ORG/REPO:ref:refs/heads/main` and `repo:ORG/REPO:environment:stage`
- prod: `repo:ORG/REPO:environment:prod` only — deliberately *not* `refs/heads/main`

**Policies:**

| Policy | Why |
| --- | --- |
| AWS-managed `PowerUserAccess` | everything except IAM. Covers VPC, EKS, RDS, S3, CloudFront, Cognito, SQS, WAF. |
| inline `terraform-iam-management` | IAM **role** actions only — create/delete/tag roles, attach policies, `PassRole`, instance profiles, service-linked roles |
| inline `terraform-state-access` | the state bucket |

The inline IAM policy carries two explicit `Deny` statements, and they are the important part:

```
Deny  iam:*User*, iam:*Group*, iam:*AccessKey*, iam:*LoginProfile*,
      iam:*SAMLProvider*, iam:*AccountAlias*
```

CI can create the *service* roles Terraform needs, but it can never create a human identity, mint
an access key, or touch your SSO configuration. This is also how your "ignore IAM users and
groups" requirement is enforced mechanically rather than by convention — if someone adds an
`aws_iam_user` resource to this repo, CI apply fails.

```
Deny  iam:DeleteRole / DeleteRolePolicy / DetachRolePolicy
      on  scribl-<env>-tf-plan  and  scribl-<env>-tf-apply
```

CI cannot delete or defang its own roles. Without this, a bad `terraform destroy` locks you out
of your own account.

**Why not a tightly-scoped custom policy?** Because Terraform legitimately needs to create
VPCs, EKS clusters, IAM roles, and RDS instances. A least-privilege policy for that is thousands
of lines, breaks on every new resource type, and in practice ends up close to PowerUser anyway.
The real control here is *who can invoke the role* — a protected branch plus a GitHub
Environment with required reviewers — not the policy body. If your security team wants tighter
scoping, the highest-value change is adding a permissions boundary to `iam:CreateRole` so CI
cannot create a role more powerful than itself.

### 3. GitHub OIDC identity provider

**Created by:** `bootstrap/main.tf`, once per account.

```hcl
url            = "https://token.actions.githubusercontent.com"
client_id_list = ["sts.amazonaws.com"]
```

If the account already has one (common in AWS Organizations with shared tooling), set
`create_oidc_provider = false` in `bootstrap/terraform.tfvars`.

### 4. Human access — deliberately not in Terraform

You asked to ignore IAM users and groups, which is the right call. The dev account has nine IAM
users with long-lived passwords in two groups, and that is the one part of the dev setup worth
not copying.

Use **AWS IAM Identity Center (SSO)** instead, configured once at the Organization level, not
per account:

| Permission set | Assign to | Accounts |
| --- | --- | --- |
| `AdministratorAccess` | 2 platform engineers | stage + prod |
| `PowerUserAccess` | developers | stage only |
| `ReadOnlyAccess` | developers | prod only |
| `Billing` | finance | management account |

Then put your admin SSO role ARN into `eks_cluster_admin_principal_arns` in
`live/<env>/main.tf` so it can also reach the Kubernetes API:

```bash
aws iam list-roles --query 'Roles[?starts_with(RoleName,`AWSReservedSSO_Administrator`)].Arn' --output text
```

```hcl
eks_cluster_admin_principal_arns = [
  "arn:aws:iam::419717495525:role/aws-reserved/sso.amazonaws.com/us-east-1/AWSReservedSSO_AdministratorAccess_a1b2c3d4e5",
]
```

The dev account grants cluster admin to the IAM *user* `mohit.dalal@bounteous.com`. Granting it
to an SSO role instead means access follows the person's employment status automatically.

---

## The three application roles

Created by `modules/iam` in each environment, alongside the infrastructure.

### `scribl-<env>-api-pod` — runtime permissions for the application

**Trust:** `pods.eks.amazonaws.com` (EKS Pod Identity)
**Bound to:** service account `scribl-api` in namespace `scribl`, by
`aws_eks_pod_identity_association`

| Allowed | Scoped to |
| --- | --- |
| Cognito self-service auth (SignUp, InitiateAuth, ForgotPassword, GetUser, …) | the two user pool ARNs |
| `s3:PutObject/GetObject/HeadObject/DeleteObject` | `scribl-<env>-data-*/*` only |
| `sqs:SendMessage/ReceiveMessage/DeleteMessage/GetQueueAttributes` | the push-nudge queue and its DLQ |
| `secretsmanager:GetSecretValue` | `scribl/<env>/*` only |

This mirrors dev's `scribl-api-pod` role. Pod Identity is better than the older IRSA approach:
no OIDC trust policy to maintain, and the association is a first-class AWS resource you can see
and audit.

Your pod spec must use exactly this service account, or it gets no AWS access at all:

```yaml
spec:
  serviceAccountName: scribl-api
```

### `scribl-<env>-github-api-deploy` — application CI/CD

**Trust:** GitHub OIDC, subjects from `github_allowed_subjects`
**Also granted:** EKS access entry with `AmazonEKSAdminPolicy` + `AmazonEKSEditPolicy`, scoped
to the `scribl` namespace *only*

| Allowed | Scoped to |
| --- | --- |
| `ecr:GetAuthorizationToken` | `*` (AWS requires this) |
| ECR push/pull layer actions | the two ECR repository ARNs |
| `eks:DescribeCluster`, `eks:ListClusters` | `*` |
| `secretsmanager:GetSecretValue` | `scribl/<env>/*` |

The namespace scoping matters. This role can roll out deployments in `scribl` and cannot touch
`kube-system`.

### `scribl-<env>-github-web-release` — SPA publishing

| Allowed | Scoped to |
| --- | --- |
| `s3:GetObject/PutObject/DeleteObject` | `scribl-<env>-app-*/*` |
| `s3:ListBucket` | that bucket |
| `cloudfront:CreateInvalidation` | that one distribution ARN |

---

## One thing from dev to fix

The inventory flags `GitHubActions-ECR-Push-Role`, which trusts `repo:ScriblOrg/*` — **any**
repository in the organisation. Any repo anyone creates in that org can push images to your ECR.

This repo does not reproduce it. Set `github_allowed_subjects` to full, explicit subjects —
**and check `gh api repos/<org>/<repo>/actions/oidc/customization/sub` first**, since a
repo with the immutable-subject feature on (both `Infra-Scribl` and `scribl-mobile-app` do)
needs the `repo:ORG@ORG_ID/REPO@REPO_ID` prefix, not the plain one:

```hcl
# good — a specific repo, a specific branch or environment, correct immutable-subject prefix
github_allowed_subjects = [
  "repo:ScriblOrg@129197376/scribl-mobile-app@1353806374:ref:refs/heads/main",
  "repo:ScriblOrg@129197376/scribl-mobile-app@1353806374:environment:stage",
]

# bad — any repo in the org, any branch, any fork's PR
github_allowed_subjects = ["repo:ScriblOrg/*"]

# also bad — right repo, wrong prefix. Doesn't error, just never matches (see below).
github_allowed_subjects = ["repo:ScriblOrg/scribl-mobile-app:environment:stage"]
```

The condition operator is `StringLike`, so `*` works but should only appear where you actually
intend a wildcard. And after you finish Phase 9, consider deleting the old broad role from the
dev account.

A plain-prefix subject on a repo with immutable-subject enabled doesn't fail at `terraform
apply` — it silently never matches, and GitHub Actions fails much later with `Not authorized
to perform sts:AssumeRoleWithWebIdentity`. If you hit that error, check the OIDC customization
endpoint above and CloudTrail's `AssumeRoleWithWebIdentity` events (`userIdentity.userName`
shows the token's actual `sub` claim) before assuming it's a typo in the org/repo name.

---

## Setup checklist

### Per AWS account (twice: stage, then prod)

- [ ] Admin access via SSO, confirmed with `aws sts get-caller-identity`
- [ ] `cd bootstrap && terraform apply` with that environment's tfvars
- [ ] Record `state_bucket`, `tf_plan_role_arn`, `tf_apply_role_arn`
- [ ] Add your admin SSO role ARN to `eks_cluster_admin_principal_arns`

### Once, in GitHub

- [ ] Repo variables: `AWS_TF_PLAN_ROLE_STAGE`, `AWS_TF_APPLY_ROLE_STAGE`, `AWS_TF_PLAN_ROLE_PROD`, `AWS_TF_APPLY_ROLE_PROD`
- [ ] Environments named exactly `stage` and `prod`
- [ ] `prod` environment: required reviewers + deployment branch limited to `main`
- [ ] Branch protection on `main`: PR required, 1 approval, plan checks must pass
- [ ] No AWS access keys in Secrets. If any exist, delete them.

### Once, in the application repository

- [ ] Its deploy workflow assumes `github_api_deploy_role_arn` / `github_web_release_role_arn`
- [ ] Its pod spec uses `serviceAccountName: scribl-api`
- [ ] `permissions: id-token: write` in every workflow that talks to AWS
