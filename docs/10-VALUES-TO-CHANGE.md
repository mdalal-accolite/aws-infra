# Every value you must set yourself

Three tables and four procedures.

- **Table 1** — set these before your first apply.
- **Table 2** — these you cannot know yet; each links to the procedure that produces it.
- **Table 3** — optional, change when you want the feature.

## Already done for you

| Value | Set to |
| --- | --- |
| Stage AWS account | `419717495525` |
| Prod AWS account | `882781045478` |
| Region, both environments | `us-east-1` |
| Naming token | `stage` / `prod`, so resources read `scribl-stage-db` |
| Postgres version | `18.3` (the version dev runs) with family `postgres18` |
| SES domain | `stg.scribl.co` |
| CloudFront alternate domain | `mweb.stage.scribl.co` (applied once you supply a certificate) |
| Every resource name | no AWS account numbers anywhere |

---

## Table 1 — set these now, before anything runs

| # | File | Setting | Current | Set to |
| --- | --- | --- | --- | --- |
| 1 | `config/main.tf` | `github_org` (stage block) | `"ScriblOrg"` | your GitHub org |
| 2 | `config/main.tf` | `github_repo` (stage block) | `"scribl-infra"` | the repo holding this code |
| 3 | `config/main.tf` | `github_allowed_subjects` (stage block) | `repo:ScriblOrg/scribl-infra:...` | your org/repo, **both lines** |
| 4 | `config/main.tf` | `cognito_domain_prefix` (stage block) | `"scribl-stage-admin-auth"` | keep it if globally free — **check first**, procedure D |
| 5 | `bootstrap/terraform.tfvars` | `github_org`, `github_repo`, `plan_subjects`, `apply_subjects` | — | **this file does not exist yet.** Procedure A creates it. |

### Your question: "there is no file called `terraform.tfvars` under bootstrap"

Correct, and that is intended. What ships is `bootstrap/terraform.tfvars.stage.example`. You
copy it to `terraform.tfvars` and edit the copy.

The reason for the split: `.gitignore` ignores `*.tfvars` but keeps `*.tfvars.example`. The
example is committed so everyone can see the shape; your real copy stays on your laptop. Here
it holds nothing secret, but it is the standard Terraform convention and worth keeping.

```bash
cd bootstrap
cp terraform.tfvars.stage.example terraform.tfvars      # macOS / Linux
```
```powershell
cd bootstrap
Copy-Item terraform.tfvars.stage.example terraform.tfvars   # Windows
```

Then edit `terraform.tfvars` — four values, all your org/repo:

```hcl
environment = "stage"
region      = "us-east-1"
github_org  = "YourOrg"          # <-- change
github_repo = "scribl-infra"     # <-- change

plan_subjects = [
  "repo:YourOrg/scribl-infra:pull_request",
]

apply_subjects = [
  "repo:YourOrg/scribl-infra:ref:refs/heads/main",
  "repo:YourOrg/scribl-infra:environment:stage",
]
```

Those subject strings go straight into IAM trust policies. A typo means GitHub Actions fails to
authenticate later with `Not authorized to perform sts:AssumeRoleWithWebIdentity`, which is a
confusing error to debug — so copy your org and repo name exactly, including capitalisation.

---

## Table 2 — you cannot know these yet

| # | Where it goes | Value | Produced by |
| --- | --- | --- | --- |
| 6 | `envs/stage.backend.hcl` → `bucket` | `scribl-stage-tfstate-<random>` | **Procedure A** |
| 7 | 🐙 repo variable `AWS_TF_PLAN_ROLE_STAGE` | an IAM role ARN | **Procedure A**, applied in **Procedure B** |
| 8 | 🐙 repo variable `AWS_TF_APPLY_ROLE_STAGE` | an IAM role ARN | **Procedure A**, applied in **Procedure B** |
| 9 | `config/main.tf` → `nlb_arn` | the product NLB's ARN | **Procedure C** |
| 10 | `config/main.tf` → `admin_nlb_dns_name` | the admin NLB's DNS name | **Procedure C** |
| 11 | `config/main.tf` → `cloudfront_certificate_arn` | an ACM certificate ARN | docs/12 Phase 8 |

---

## Procedure A — run bootstrap and read its output

**This answers: how do I get the bootstrap output, when, and with what command.**

Bootstrap is a small, separate Terraform stack under `bootstrap/`. It runs **once per AWS
account**, from your laptop, with admin credentials, **before** anything in `stacks/`. It
creates four things:

1. the S3 bucket that holds all Terraform state,
2. the GitHub OIDC identity provider,
3. `scribl-stage-tf-plan` — a read-only role for pull requests,
4. `scribl-stage-tf-apply` — the role that creates infrastructure.

It cannot run in GitHub Actions, because it creates the very roles Actions would need to
authenticate.

### A1. Point at the right account

```bash
export AWS_PROFILE=scribl-stage        # macOS / Linux
```
```powershell
$env:AWS_PROFILE = "scribl-stage"      # Windows
```
```
aws sts get-caller-identity
```

Must print `419717495525`. If not, stop and fix your profile.

### A2. Create your tfvars (Table 1, item 5) and apply

```
cd bootstrap
terraform init
terraform plan        # dry run — expect about 15 resources to add
terraform apply       # type: yes
```

Takes under a minute.

### A3. Read the output — this is the command you asked about

```
terraform output
```

That prints, from inside `bootstrap/`, something like:

```
account_id        = "419717495525"
state_bucket      = "scribl-stage-tfstate-k3m9x2"
tf_apply_role_arn = "arn:aws:iam::419717495525:role/scribl-stage-tf-apply"
tf_plan_role_arn  = "arn:aws:iam::419717495525:role/scribl-stage-tf-plan"
next_steps        = <<EOT
    1. Copy state_bucket below into envs/stage.backend.hcl ...
EOT
```

`terraform output` only works **from the directory that owns the state**, and only **after**
that stack has been applied. Run it in `bootstrap/` and you get these four. Run it in
`stacks/40-data/` after applying that component and you get the database endpoints instead.

One value at a time, without quotes, for pasting:

```
terraform output -raw state_bucket
terraform output -raw tf_plan_role_arn
terraform output -raw tf_apply_role_arn
```

Forgot to note them down? They are not lost — `terraform output` re-reads state and prints them
again, any time.

### A4. Paste `state_bucket` into the backend file

`envs/stage.backend.hcl` currently reads:

```hcl
bucket = "REPLACE_ME_WITH_BOOTSTRAP_OUTPUT"   # e.g. scribl-stage-tfstate-k3m9x2
region = "us-east-1"
```

Replace that string with what `terraform output -raw state_bucket` gave you:

```hcl
bucket = "scribl-stage-tfstate-k3m9x2"
region = "us-east-1"
```

**Why is this not pre-filled?** The bucket name ends in a random 6-character token. That is
deliberate — it keeps your AWS account number out of the name while still being globally unique
(S3 bucket names are shared across every AWS customer). The trade-off is that nobody, including
me, can know the name until bootstrap generates it.

### A5. Commit

```
cd ..
git add bootstrap/terraform.tfstate envs/stage.backend.hcl config/main.tf
git commit -m "Bootstrap stage account"
git push
```

`bootstrap/terraform.tfstate` **is** committed, deliberately — `.gitignore` has an exception for
it. It is a few KB, contains no secrets, and losing it means you can no longer cleanly change
CI permissions.

---

## Procedure B — put the two role ARNs into GitHub

**This answers: "didn't get what you are saying" about items 7 and 8.**

You are creating two **repository variables** in GitHub — not files, not Terraform. They tell
the workflows which AWS role to assume.

### B1. Navigate

1. Open your repo on github.com
2. **Settings** (top tab bar, far right)
3. Left sidebar → **Secrets and variables** → **Actions**
4. Click the **Variables** tab — *not* Secrets
5. **New repository variable**

### B2. Add two

| Name | Value |
| --- | --- |
| `AWS_TF_PLAN_ROLE_STAGE` | `arn:aws:iam::419717495525:role/scribl-stage-tf-plan` |
| `AWS_TF_APPLY_ROLE_STAGE` | `arn:aws:iam::419717495525:role/scribl-stage-tf-apply` |

Exact names, capitals included. `.github/workflows/terraform-plan.yml` reads
`vars.AWS_TF_PLAN_ROLE_STAGE` literally; a typo means the workflow passes an empty role and
fails at the credentials step.

Faster from the CLI, if you have `gh`:

```bash
cd bootstrap
gh variable set AWS_TF_PLAN_ROLE_STAGE  --body "$(terraform output -raw tf_plan_role_arn)"
gh variable set AWS_TF_APPLY_ROLE_STAGE --body "$(terraform output -raw tf_apply_role_arn)"
gh variable list
```
```powershell
cd bootstrap
gh variable set AWS_TF_PLAN_ROLE_STAGE  --body (terraform output -raw tf_plan_role_arn)
gh variable set AWS_TF_APPLY_ROLE_STAGE --body (terraform output -raw tf_apply_role_arn)
gh variable list
```

### B3. Why variables and not secrets

A role ARN is an identifier, not a credential. It is useless to anyone whose GitHub OIDC token
does not match the role's trust policy — which names your exact repository and branch. Storing
it as a variable means you can read it back when a workflow misbehaves; a secret would be
masked in every log line and much harder to debug.

**There are no GitHub secrets in this setup at all.** If `AWS_ACCESS_KEY_ID` or
`AWS_SECRET_ACCESS_KEY` exist in your repo, delete them.

### B4. While you are in Settings

- **Environments** → New environment → create `stage` and `prod`. The names appear literally in
  the IAM trust policies (`repo:org/repo:environment:stage`), so spelling matters. Add required
  reviewers on `prod`.
- **Branches** → protect `main`: require a pull request, 1 approval, require the plan checks.

---

## Procedure C — get the NLB ARN and DNS name

**This answers: how will I get the NLB ARN.**

You will not find these in Terraform, and that is the whole point. When you apply a Kubernetes
`Service` of type `LoadBalancer`, the controller inside EKS calls the AWS API and creates a
Network Load Balancer. Terraform never sees it. You read the values back from AWS and hand them
to Terraform on a second pass.

So the order is: apply the infrastructure → deploy your pods → **then** come back here.

### C1. Confirm your Services exist

```
kubectl -n scribl get svc
```

You want two entries of type `LoadBalancer` with an `EXTERNAL-IP` filled in. A blank
`EXTERNAL-IP` means the controller is still working — wait two or three minutes. Blank after
five minutes usually means the subnets are missing their `kubernetes.io/role/*-elb` tags, which
this Terraform already sets, so it is more likely a bad annotation.

### C2. List the load balancers in your VPC

```bash
VPC=$(cd stacks/10-network && terraform output -raw vpc_id)

aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?VpcId=='$VPC'].{Name:LoadBalancerName,Scheme:Scheme,DNS:DNSName,Arn:LoadBalancerArn}" \
  --output table
```
```powershell
Push-Location stacks\10-network
$vpc = terraform output -raw vpc_id
Pop-Location

aws elbv2 describe-load-balancers `
  --query "LoadBalancers[?VpcId=='$vpc'].{Name:LoadBalancerName,Scheme:Scheme,DNS:DNSName,Arn:LoadBalancerArn}" `
  --output table
```

Two rows, looking like this:

```
|  Name                          | Scheme          | DNS                                          | Arn                                                                                    |
|  k8s-scribl-scriblap-fc2081e2  | internal        | k8s-scribl-scriblap-....elb.amazonaws.com    | arn:aws:elasticloadbalancing:us-east-1:419717495525:loadbalancer/net/k8s-scribl-scri...|
|  k8s-scribl-scriblad-cbbeca20  | internet-facing | k8s-scribl-scriblad-....elb.amazonaws.com    | arn:aws:elasticloadbalancing:us-east-1:419717495525:loadbalancer/net/k8s-scribl-scri...|
```

### C3. Work out which is which

The name segment after `k8s-scribl-` is the Kubernetes Service name, truncated:

| Fragment | Service | Which value you need | Goes into |
| --- | --- | --- | --- |
| `scriblap` | the **product** API | the full **ARN** | `nlb_arn` |
| `scriblad` | the **admin** API | the **DNS name** | `admin_nlb_dns_name` |

They take different value types because API Gateway's VPC Link wants an ARN, while CloudFront
wants a hostname for its custom origin.

The `Arn` column is truncated in table output. Get the full value:

```bash
aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?contains(LoadBalancerName, 'scriblap')].LoadBalancerArn" \
  --output text

aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?contains(LoadBalancerName, 'scriblad')].DNSName" \
  --output text
```

Same two commands work in PowerShell — no shell-specific syntax.

### C4. Check the schemes

The product NLB should be `internal`: it sits behind API Gateway's VPC Link and has no reason
to be on the internet. If it says `internet-facing`, the
`service.beta.kubernetes.io/aws-load-balancer-scheme: "internal"` annotation did not take — fix
the Service, delete it, re-apply, and wait for a new NLB. See docs/04.

The admin NLB is `internet-facing` in dev, because CloudFront reaches it over the public
internet as a custom origin.

### C5. Put them in config and apply

```hcl
# config/main.tf, stage block
enable_api_gateway = true
nlb_arn            = "arn:aws:elasticloadbalancing:us-east-1:419717495525:loadbalancer/net/k8s-scribl-scriblap-fc2081e221/abc123"
admin_nlb_dns_name = "k8s-scribl-scriblad-cbbeca205c-1234567890.elb.amazonaws.com"
```

Commit, open a PR, merge. CI applies `20-edge` (the admin origin plus three cache behaviours)
and `80-api` (the REST API and VPC Link). Roughly 15 resources, 3 minutes.

### C6. Verify

```bash
cd stacks/80-api
curl "$(terraform output -raw invoke_url)/health"
```
```powershell
cd stacks\80-api
$url = terraform output -raw invoke_url
Invoke-RestMethod "$url/health"
```

### C7. If the NLB is ever recreated

Deleting and re-applying the Kubernetes Service produces a **new** NLB with a new ARN and DNS
name. Repeat C2 through C5. This is the cost of letting Kubernetes own its own load balancer,
and it is still better than the alternative — two systems fighting over one resource, with
every `kubectl apply` producing Terraform drift.

---

## Procedure D — check the Cognito domain prefix is free

Cognito hosted-UI prefixes are unique across all of AWS, not just your account. This is worth
30 seconds now because otherwise `34-identity` fails near the end of its apply.

```
aws cognito-idp describe-user-pool-domain --domain scribl-stage-admin-auth
```

`ResourceNotFoundException` means the name is **free** — that is the result you want. Anything
else means it is taken; pick another and update `cognito_domain_prefix`.

---

## Table 3 — optional, change when you need the feature

| File | Setting | Default | When to change |
| --- | --- | --- | --- |
| `config/main.tf` | `alarm_email` | `""` | to actually receive the 6 CloudWatch alarms |
| `config/main.tf` | `eks_cluster_admin_principal_arns` | `[]` | your SSO admin role ARN, so humans can use `kubectl` |
| `config/main.tf` | `admin_cidr_blocks` | `[]` | office egress CIDRs, if you want RDP to the tools host |
| `config/main.tf` | `cognito_callback_urls_*` | `example.invalid` / localhost | once the real app URLs exist |
| `config/main.tf` | `cloudfront_certificate_arn` | `""` | once `mweb.stage.scribl.co` is ISSUED — docs/12 Phase 8 |
| `config/main.tf` | `ses_route53_zone_id` | `""` | only if a Route 53 zone is created in this account |
| `config/main.tf` | `ses_create_smtp_user` | `true` | set false if you use the SES API rather than SMTP |
| `config/main.tf` | `tools_public_key_openssh` | `""` | only if you want SSH as well as SSM |
| `config/main.tf` | `vpn_*_certificate_arn` + `enable_client_vpn` | `""` / `false` | if you import Client VPN certs — docs/05 |
| `config/main.tf` | `owner`, `cost_center` | `platform-team`, `engineering` | to match your tagging policy |
| `config/main.tf` | `postgres_engine_version` | `"18.3"` | only if 18.3 is unavailable in your region |
| `envs/prod.backend.hcl` | `bucket` | placeholder | when you bootstrap prod |
| 🐙 variables | `AWS_*_ROLE_PROD` | — | when you build prod |

### Checking the Postgres version

`18.3` matches what the dev account runs. Confirm it is offered in us-east-1:

```
aws rds describe-db-engine-versions --engine postgres --query "DBEngineVersions[?starts_with(EngineVersion, '18')].[EngineVersion,DBParameterGroupFamily]" --output table
```

If `18.3` is missing, set `postgres_engine_version` and `postgres_parameter_group_family` to a
pair that is listed. AWS retires old minors eventually, so check rather than assume.

---

## Nothing here is a secret

Account ids, role ARNs, bucket names, NLB ARNs, domains — all identifiers, safe in git and safe
as GitHub variables. There are no passwords or keys in this repository, and no AWS access keys
exist in the setup at all.

The one sensitive artifact is the **Terraform state bucket**, because state holds resource
attributes including the SES SMTP password. Bootstrap creates it encrypted, versioned and with
public access blocked, readable only by the two CI roles and account admins. Keep it that way.

## Finding anything left over

```bash
grep -rn "ScriblOrg\|REPLACE_ME\|scribl.example" config/main.tf envs/ bootstrap/
```
```powershell
Select-String -Path config\main.tf, envs\*, bootstrap\* -Pattern "ScriblOrg|REPLACE_ME|scribl.example"
```

Clean apart from lines you meant to keep? Table 1 is done.
