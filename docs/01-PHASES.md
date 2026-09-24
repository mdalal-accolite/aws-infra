# The whole deployment, phase by phase

Nothing here assumes you have used Terraform, AWS CLI, or GitHub Actions before. Commands are
copy-pasteable. Anywhere you must substitute your own value it is written in `ANGLE_BRACKETS`.

Read the whole outline first, then start at Phase 0.

| Phase | What happens | Where you run it | Roughly |
| --- | --- | --- | --- |
| 0 | Install tools, get accounts, make three decisions | your laptop | 30 min |
| 1 | Create the GitHub repo, commit this code | your laptop | 15 min |
| 2 | Bootstrap the stage AWS account (state bucket, OIDC, CI roles) | your laptop | 10 min |
| 3 | Wire GitHub up to AWS (variables, environments, approvals) | github.com | 15 min |
| 4 | First real apply — VPC through EKS | laptop, then CI | 30–40 min |
| 5 | Fill in secret values, get `kubectl` working, init the database | laptop | 30 min |
| 6 | Deploy the app to EKS, then turn on API Gateway (second pass) | laptop + CI | 30 min |
| 7 | Publish the web SPA to S3/CloudFront | CI | 10 min |
| 8 | Verify everything end to end | laptop | 30 min |
| 9 | Add prod, later, with the same code | laptop + CI | 1 hr |
| 10 | Day-2 operations and teardown | ongoing | — |

Two Terraform passes are unavoidable (Phase 4 and Phase 6). The reason is in
[04-KUBERNETES-AND-NLB.md](04-KUBERNETES-AND-NLB.md); read that before Phase 6.

---

## Phase 0 — Prerequisites

### 0.1 Install four tools

```bash
# macOS
brew install terraform awscli kubernetes-cli gh

# Ubuntu / WSL
sudo snap install --classic terraform
sudo snap install --classic kubectl
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip awscliv2.zip && sudo ./aws/install
sudo apt install gh
```

Verify:

```bash
terraform version   # need >= 1.9.0
aws --version       # need >= 2.15
kubectl version --client
```

### 0.2 Get admin access to the new AWS account

You need credentials that can create IAM roles, VPCs, and EKS clusters — once, for Phase 2.
After that, everything runs through CI roles.

If your organisation uses AWS IAM Identity Center (SSO), which it should:

```bash
aws configure sso --profile scribl-stage
# SSO start URL:  https://<YOUR_ORG>.awsapps.com/start
# region:         us-east-1
# then pick the stage account + AdministratorAccess role

aws sso login --profile scribl-stage
export AWS_PROFILE=scribl-stage

# Confirm you are in the RIGHT account before doing anything
aws sts get-caller-identity
```

That last command prints an `Account` field. For stage it must be exactly:

```
419717495525
```

If it shows anything else, stop and fix your profile. Applying stage Terraform into the wrong
account is the single most common way this goes sideways. The provider has a guard rail for
this (`allowed_account_ids`), so Terraform will refuse to run against a different account - but
it is better to catch it here.

### 0.3 Three decisions to make now

**Decision 1 — VPC CIDR ranges.** Pick ranges that do not overlap each other, the dev account
(`172.31.0.0/16`), or your office network. Defaults in this repo:

| Environment | VPC CIDR | Private subnets (/20 each) | Public subnets (/24 each) |
| --- | --- | --- | --- |
| stage | `10.20.0.0/16` | `10.20.0.0/20`, `10.20.16.0/20`, `10.20.32.0/20` | `10.20.240.0/24`, `.241.0/24`, `.242.0/24` |
| prod | `10.30.0.0/16` | `10.30.0.0/20`, `10.30.16.0/20`, `10.30.32.0/20` | `10.30.240.0/24`, `.241.0/24`, `.242.0/24` |

If you plan to use Client VPN, its client range is a **third** range that must not overlap
either of the above. It ships as `10.100.0.0/22` (stage) and `10.110.0.0/22` (prod) in
`config/main.tf`. AWS requires that range to be between /12 and /22 — a /24 is rejected — and
it cannot be changed after the endpoint exists. See docs/05.

Private subnets are `/20` (~4,091 IPs each) because EKS gives every **pod** a real VPC IP
address. A `/24` would run out of pods fast. Public subnets are `/24` because the only thing
that ever lives in them is a NAT Gateway.

**Decision 2 — repository name.** This repo is written assuming `ScriblOrg/scribl-infra`. If you
use something else, it appears in six places; Phase 1.3 lists them.

**Decision 3 — how humans will reach the private network.** With everything on private subnets,
the RDS endpoint, Redis, the tools host, and the Kubernetes API are *not* reachable from the
internet. Pick one:

| Option | Effort | Notes |
| --- | --- | --- |
| **SSM Session Manager** | none, already configured | Works today for the EC2 tools host. Port-forward to RDS through it. |
| **Client VPN** | needs 2 ACM certs | Full network access. You said skip ACM, so it is off by default. See docs/05. |
| **Public EKS endpoint, IP-restricted** | one line | Set `eks_endpoint_public_access = true` and `eks_public_access_cidrs = ["<YOUR_OFFICE_IP>/32"]`. Least secure of the three, but pragmatic for stage. |

You can start with SSM and add the VPN later. Nothing else depends on this choice.

---

## Phase 1 — Create the GitHub repository

### 1.1 Create it empty

```bash
gh repo create ScriblOrg/scribl-infra --private --description "Terraform for Scribl AWS infrastructure"
```

Or on github.com: **New repository** → Owner `ScriblOrg` → Name `scribl-infra` → **Private** →
do *not* add a README or .gitignore (this repo has its own).

### 1.2 Put this code into it

Copy the contents of the `test/` folder into your clone. The `test` folder itself is not part of
the tree — its *contents* become the repository root.

```bash
git clone https://github.com/ScriblOrg/scribl-infra.git
cd scribl-infra
cp -r /path/to/test/. .        # note the trailing /. — it copies contents, including dotfiles
ls -a                          # you should see .github, .gitignore, README.md, bootstrap, live, modules, stacks, docs
```

### 1.3 Change the placeholders

Every environment-specific value now lives in **one file**: `config/main.tf`. Open it and edit
the `stage = { ... }` block.

| Setting | Status |
| --- | --- |
| `account_id` | **already set to `419717495525`** - nothing to do |
| `ses_domain` | **change me** - the domain you will verify for sending |
| `github_org`, `github_repo`, `github_allowed_subjects` | **change me** - your org and repo |
| `cognito_domain_prefix` | **check** - `scribl-stage-admin-auth` must be globally unique across all of AWS |

The `prod` block still has the `222222222222` placeholder. Leave it until you actually build prod.

`envs/stage.backend.hcl` has `bucket = "REPLACE_ME_WITH_BOOTSTRAP_OUTPUT"`. That is
deliberate: the state bucket name ends in a random token so the account number stays out of it,
which means you cannot know the name until bootstrap has run. Phase 2.3 gives you the value.

```bash
grep -n "CHANGE ME" config/main.tf
grep -rn "419717495525\|ScriblOrg" config/main.tf envs/
```

### 1.4 Commit

```bash
git add -A
git commit -m "Initial Terraform for stage and prod environments"
git push origin main
```

### 1.5 Protect `main`

On github.com → **Settings → Branches → Add branch protection rule**:

- Branch name pattern: `main`
- ☑ Require a pull request before merging (1 approval)
- ☑ Require status checks to pass → add the `plan stage/...` checks once they have run once
- ☑ Do not allow bypassing the above settings

This matters more than it looks: the CI apply role trusts `refs/heads/main`, so anything that
lands on `main` can change AWS.

---

## Phase 2 — Bootstrap the stage AWS account

This is the only Terraform you ever run with admin credentials from your laptop. It creates the
four things that make everything else possible:

1. an S3 bucket to hold Terraform state,
2. the GitHub OIDC identity provider, so Actions can get AWS credentials without secret keys,
3. a read-only `tf-plan` role for pull requests,
4. a `tf-apply` role for merges.

### 2.1 Point at the stage account

```bash
export AWS_PROFILE=scribl-stage
aws sts get-caller-identity          # MUST show 419717495525
```

### 2.2 Apply

```bash
cd bootstrap
cp terraform.tfvars.stage.example terraform.tfvars
# open terraform.tfvars and confirm github_org / github_repo are yours

terraform init
terraform plan                       # expect ~14 resources to add
terraform apply                      # type: yes
```

**If it fails with `EntityAlreadyExists` on the OIDC provider**, the account already has one.
Add `create_oidc_provider = false` to `terraform.tfvars` and re-run `terraform apply`.

### 2.3 Record the outputs

```bash
terraform output
```

You get four values. Do this with them:

| Output | Goes where |
| --- | --- |
| `state_bucket` | `envs/stage.backend.hcl`, replacing `REPLACE_ME_WITH_BOOTSTRAP_OUTPUT` |
| `tf_plan_role_arn` | GitHub repo variable `AWS_TF_PLAN_ROLE_STAGE` (Phase 3) |
| `tf_apply_role_arn` | GitHub repo variable `AWS_TF_APPLY_ROLE_STAGE` (Phase 3) |
| `account_id` | must be `419717495525` — if not, you are in the wrong account |

### 2.4 Keep the bootstrap state

`bootstrap/terraform.tfstate` is a real file on your laptop, and `.gitignore` has an exception
so it *is* committed. That is deliberate — it contains no secrets, it is tiny, and losing it
means you cannot cleanly change CI permissions later.

```bash
cd ..
git add bootstrap/terraform.tfstate envs/stage.backend.hcl
git commit -m "Bootstrap stage account"
git push
```

---

## Phase 3 — Connect GitHub to AWS

### 3.1 Repository variables

github.com → **Settings → Secrets and variables → Actions → Variables tab → New repository variable**.

These are *variables*, not secrets. Role ARNs are not sensitive; they are useless without the
trust policy matching your repo.

| Name | Value |
| --- | --- |
| `AWS_TF_PLAN_ROLE_STAGE` | the `tf_plan_role_arn` from Phase 2.3 |
| `AWS_TF_APPLY_ROLE_STAGE` | the `tf_apply_role_arn` from Phase 2.3 |
| `AWS_TF_PLAN_ROLE_PROD` | fill in during Phase 9 |
| `AWS_TF_APPLY_ROLE_PROD` | fill in during Phase 9 |

### 3.2 Environments

github.com → **Settings → Environments → New environment**. Create two, named exactly `stage`
and `prod` — the names appear in the IAM trust policies, so spelling counts.

For `stage`: no protection rules needed.

For `prod`:
- ☑ **Required reviewers** → add yourself and one other person
- ☑ **Deployment branches** → *Selected branches* → `main`

This is your production safety net. The prod `tf-apply` role only trusts the subject
`repo:ORG/REPO:environment:prod`, which GitHub only issues after a reviewer approves.

### 3.3 Test the connection

Open a throwaway pull request that touches a `.tf` file (add a comment line). The
`Terraform Plan` workflow should run and post a plan comment. If it fails at
**Configure AWS credentials**, the mismatch is between your `plan_subjects` in
`bootstrap/terraform.tfvars` and your actual org/repo name. Fix and re-apply bootstrap.

---

## Phase 4 — First apply: build the stage environment

The infrastructure is split into 13 independent components, each with its own Terraform state.
Read [08-COMPONENTS-AND-PIPELINE.md](08-COMPONENTS-AND-PIPELINE.md) for why. The first build
runs them once each, in order.

### 4.1 The order, and what depends on what

| # | Component | Reads state from | Minutes |
| --- | --- | --- | --- |
| 1 | `10-network` | — | 6 |
| 2 | `20-edge` | — | 6 |
| 3 | `30-registry` | — | 1 |
| 4 | `32-messaging` | — | 1 |
| 5 | `34-identity` | — | 2 |
| 6 | `36-secrets` | `34-identity` | 1 |
| 7 | `38-email` | `32-messaging` | 1 |
| 8 | `40-data` | `10-network`, `32-messaging` | 20 |
| 9 | `50-iam` | `20-edge`, `30-registry`, `32-messaging`, `34-identity`, `38-email` | 1 |
| 10 | `60-eks` | `10-network`, `50-iam` | 15 |
| 11 | `70-tools` | `10-network` | 2 |
| 12 | `80-api` | `36-secrets` | skip until Phase 6 |
| 13 | `90-vpn` | `10-network` | skip (needs ACM) |

### 4.2 Run them

The repeated command is the same every time, so use a loop:

```bash
cd stacks

for C in 10-network 20-edge 30-registry 32-messaging 34-identity \
         36-secrets 38-email 40-data 50-iam 60-eks 70-tools; do
  echo "=============== $C ==============="
  ( cd "$C" \
    && terraform init -input=false \
         -backend-config=../../envs/stage.backend.hcl \
         -backend-config="key=stage/$C.tfstate" \
    && terraform apply -input=false -auto-approve -var="environment=stage" ) || break
done
```

The `|| break` matters: if a component fails, stop rather than pressing on into components that
depend on it.

Prefer to go one at a time and read each plan first? That is the safer habit:

```bash
cd stacks/10-network
terraform init -input=false \
  -backend-config=../../envs/stage.backend.hcl \
  -backend-config="key=stage/10-network.tfstate"
terraform plan -var="environment=stage"      # read it
terraform apply -var="environment=stage"     # then type yes
```

Before approving `40-data`, check the plan shows `publicly_accessible = false`. Before approving
`60-eks`, check `subnet_ids` are the three private subnet ids.

### 4.3 If a component fails

Fix the cause and re-run **that component only**. Nothing else has been touched.

| Error | Fix |
| --- | --- |
| `Cannot find version 18.3 for postgres` | run the check in 4.5, set `postgres_engine_version` in `config/main.tf` |
| `BucketAlreadyExists` | someone owns that S3 name globally — change `account_id`, or add a suffix in `modules/storage-cdn/main.tf` |
| `InvalidParameterException: domain already exists` | `cognito_domain_prefix` is taken |
| `UnsupportedAvailabilityZoneException` | set `az_count = 2` |
| `AccessDenied` on `iam:CreateRole` | you are not using admin credentials — check `aws sts get-caller-identity` |
| `Unable to find remote state` | an upstream component has not been applied yet — check the table in 4.1 |
| `creating RDS DB Proxy: InvalidParameterCombination` | set `enable_rds_proxy = false`, revisit later |

### 4.4 After the first build, never loop again

From here on, edit a file, open a PR, and CI plans **only** the affected component. See
[08-COMPONENTS-AND-PIPELINE.md](08-COMPONENTS-AND-PIPELINE.md).

### 4.5 Verify the Postgres version is real before you trust it

```bash
aws rds describe-db-engine-versions \
  --engine postgres \
  --query 'DBEngineVersions[?starts_with(EngineVersion, `18`)].[EngineVersion,DBParameterGroupFamily]' \
  --output table
```

Use an `EngineVersion` from that table and its matching `DBParameterGroupFamily`. The repo
defaults to `18.3` / `postgres18`, matching dev. AWS adds new 18.x minors regularly, so
**check rather than trusting the default**.

### 4.6 Collect the outputs

Each component holds its own outputs:

```bash
cd stacks/40-data  && terraform output
cd ../60-eks       && terraform output
cd ../38-email     && terraform output -json dns_records | python3 -m json.tool
```

Phase 5 needs `db_proxy_endpoint`, `db_master_secret_arn`, `redis_primary_endpoint` (from
`40-data`) and `cluster_name` (from `60-eks`).

## Phase 5 — Post-apply configuration

Terraform created empty *containers* for secrets. Real values go in by hand, once. Terraform
deliberately ignores them afterwards (`ignore_changes = [secret_string]`), so applies never
overwrite what you put there.

### 5.1 Get into the private network

```bash
# the tools host — works with no VPN, no SSH key, no public IP
aws ssm start-session --target <TOOLS_INSTANCE_ID>
```

To reach RDS from your laptop, tunnel through that host:

```bash
aws ssm start-session \
  --target <TOOLS_INSTANCE_ID> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["<DB_PROXY_ENDPOINT>"],"portNumber":["5432"],"localPortNumber":["15432"]}'
```

Leave that running. `localhost:15432` now points at the database.

### 5.2 Read the database password

RDS generated it and stores it in Secrets Manager. Terraform never saw it.

```bash
SECRET_ARN=$(terraform output -raw db_master_secret_arn)
aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" \
  --query SecretString --output text | python3 -m json.tool
```

### 5.3 Fill in the application secrets

Terraform created the secret *containers* with placeholder values. One script writes the real
ones:

```bash
./scripts/seed-secrets.sh stage
```

It reads the RDS-managed master password out of Secrets Manager, builds the two connection
strings (proxy for the app, direct for migrations), generates the random signing secrets, and
writes them. Terraform has `ignore_changes = [secret_string]` on all of them, so applies never
overwrite what the script put there.

What it writes:

| Secret | Value |
| --- | --- |
| `scribl/stage/api` | `DATABASE_URL` via RDS Proxy + a generated `INTERNAL_JOB_SECRET` |
| `scribl/stage/admin-api/database-url` | via RDS Proxy |
| `scribl/stage/migrate/database-url` | direct to the instance, bypassing the proxy |
| `scribl/stage/admin-api/session-cookie-secret` | 32 random bytes |
| `scribl/stage/admin-api/origin-verify` | 32 random bytes |

What it leaves alone, because something else already owns them:

| Secret | Owner |
| --- | --- |
| `scribl/stage/admin-api/idp-client-secret` | Terraform, from the Cognito client |
| `scribl/stage/redis/auth-token` | Terraform, generated |
| `scribl/stage/ses/smtp-credentials` | you, only if you use SMTP (docs/09) |

Verify:

```bash
aws secretsmanager list-secrets \
  --filters Key=name,Values=scribl/stage \
  --query 'SecretList[].Name' --output table
```

The Redis auth token matters: this build enables TLS and a password on Redis, which dev did not
have. Your client needs `rediss://` plus that token. If the app is not ready, set
`redis_transit_encryption_enabled = false` and `redis_auth_token_enabled = false` in
`modules/data/variables.tf` — but do it before you have data, since changing it later replaces
the cache cluster.

### 5.4 Get `kubectl` working

```bash
aws eks update-kubeconfig --name scribl-stage-eks --region us-east-1
kubectl get nodes
```

`kubectl get nodes` returning **zero nodes is correct** on a fresh Auto Mode cluster. Nodes are
created on demand when a pod needs scheduling. If instead it hangs or times out, you are
outside the VPC and the API endpoint is private — see Decision 3 in Phase 0.

```bash
kubectl create namespace scribl
```

### 5.5 Run migrations

With the port-forward from 5.1 still open:

```bash
psql "postgresql://scribl_admin:<PASS>@localhost:15432/scribl?sslmode=require" -c '\l'
# then your project's migration command
```

---

## Phase 6 — Deploy to EKS, then enable API Gateway

Read [04-KUBERNETES-AND-NLB.md](04-KUBERNETES-AND-NLB.md) first. Short version: Kubernetes
creates the load balancer, not Terraform, so Terraform cannot reference it until it exists.

### 6.1 Push a container image

```bash
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin $ACCOUNT.dkr.ecr.us-east-1.amazonaws.com

docker build -t $ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/scribl-mobile-app:stage-001 .
docker push $ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/scribl-mobile-app:stage-001
```

### 6.2 Apply your Kubernetes manifests

The service account name must be exactly `scribl-api` in namespace `scribl` — that is what the
Pod Identity association Terraform created is bound to. The Service must be an **internal** NLB.
docs/04 has the exact annotations.

```bash
kubectl apply -f deploy/k8s/api/
kubectl -n scribl get pods -w
kubectl -n scribl get svc scribl-api      # wait for EXTERNAL-IP to appear
```

### 6.3 Find the NLB ARN

```bash
aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?VpcId=='$(cd stacks/40-data && terraform output -raw vpc_id)'].[LoadBalancerName,Scheme,LoadBalancerArn]" \
  --output table
```

### 6.4 Second Terraform pass

Edit `config/main.tf`:

```hcl
  enable_api_gateway = true
  nlb_arn            = "arn:aws:elasticloadbalancing:us-east-1:419717495525:loadbalancer/net/k8s-scribl-..."
```

Commit, open a PR, merge. CI applies it — about 12 new resources, 2 minutes.

```bash
cd stacks/40-data && terraform output -raw api_invoke_url
curl "$(terraform output -raw api_invoke_url)/health"
```

That invoke URL is what `VITE_API_BASE_URL` and `EXPO_PUBLIC_API_BASE_URL` should point at.

---

## Phase 7 — Publish the web SPA

```bash
BUCKET=$(cd stacks/40-data && terraform output -raw app_bucket_name)
DIST=$(cd stacks/40-data && terraform output -raw cloudfront_distribution_id)

aws s3 sync ./dist "s3://$BUCKET/" --delete
aws cloudfront create-invalidation --distribution-id "$DIST" --paths "/*"

echo "https://$(cd stacks/40-data && terraform output -raw cloudfront_domain_name)"
```

In your application repository's deploy workflow, assume the
`github_web_release_role_arn` role instead of using access keys — it has exactly these
permissions and nothing more.

---

## Phase 8 — Verify

Work down this list. Every line should come back the way the comment says.

```bash
cd stacks/40-data

# Database is NOT reachable from the internet
aws rds describe-db-instances --db-instance-identifier scribl-stage-db \
  --query 'DBInstances[0].[PubliclyAccessible,MultiAZ,StorageEncrypted,DeletionProtection]'
# => [false, false, true, false]   (stage; prod should be [false,true,true,true])

# Every EKS subnet is private (no route to an internet gateway)
for s in $(terraform output -json private_subnet_ids | python3 -c 'import sys,json;print(" ".join(json.load(sys.stdin)))'); do
  aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=$s" \
    --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`].GatewayId' --output text
done
# => three lines, each starting with "nat-". Any "igw-" is a bug.

# No EC2 instance has a public IP
aws ec2 describe-instances --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)" \
  --query 'Reservations[].Instances[].[InstanceId,PublicIpAddress]' --output table
# => PublicIpAddress column is empty everywhere

# Redis encryption is on (dev had it off)
aws elasticache describe-replication-groups --replication-group-id scribl-stage-redis \
  --query 'ReplicationGroups[0].[TransitEncryptionEnabled,AtRestEncryptionEnabled,AuthTokenEnabled]'
# => [true, true, true]

# The tools host's root volume is encrypted (dev's is not)
aws ec2 describe-volumes \
  --filters "Name=attachment.instance-id,Values=$(terraform output -raw tools_instance_id)" \
  --query 'Volumes[0].Encrypted'
# => true

# S3 buckets are fully private
for b in $(terraform output -raw app_bucket_name) $(terraform output -raw data_bucket_name); do
  aws s3api get-public-access-block --bucket "$b" \
    --query 'PublicAccessBlockConfiguration' --output json
done
# => all four flags true, both buckets

# Alarms exist (dev has zero)
aws cloudwatch describe-alarms --query 'length(MetricAlarms)'
# => 4 or more

# Every resource is tagged
aws resourcegroupstaggingapi get-resources --tag-filters Key=Environment,Values=stage \
  --query 'length(ResourceTagMappingList)'
# => a large number

# The public path works end to end
curl -sI "https://$(terraform output -raw cloudfront_domain_name)" | head -1
curl -s "$(terraform output -raw api_invoke_url)/health"
```

---

## Phase 9 — Add prod, later

The code is already written. Repeat Phases 2 through 8 against the prod account:

```bash
export AWS_PROFILE=scribl-prod
aws sts get-caller-identity              # MUST show 882781045478

cd bootstrap
cp terraform.tfvars.prod.example terraform.tfvars
rm -rf .terraform terraform.tfstate      # bootstrap state is per-account
terraform init && terraform apply

# outputs -> envs/prod.backend.hcl, plus the two PROD GitHub variables

# then run each component for prod via Actions -> Terraform Component (manual)
```

Then apply through CI only: **Actions → Terraform Apply → Run workflow → environment: prod**.
A reviewer has to approve. That approval is the whole point of the `prod` GitHub Environment.

The `prod` block in `config/main.tf` already differs from stage in the ways that matter:

| Setting | stage | prod | Why |
| --- | --- | --- | --- |
| `single_nat_gateway` | `true` | `false` | one NAT per AZ removes a single point of failure |
| `db_multi_az` | `false` | `true` | automatic failover to a standby |
| `db_deletion_protection` | `false` | `true` | cannot be deleted by accident |
| `db_skip_final_snapshot` | `true` | `false` | always snapshot before destruction |
| `db_backup_retention_days` | 7 | 30 | longer recovery window |
| `db_instance_class` | `db.r8g.large` | `db.r8g.xlarge` | headroom |
| `redis_num_nodes` | 1 | 2 | primary + replica with failover |
| `enable_tools_ec2` | `true` | `false` | KiwiTCMS is a test tool |
| `log_retention_days` | 30 | 90 | audit needs |

**The two accounts share no state, no VPC, and no IAM roles.** Only the Terraform code is
shared. A mistake in stage cannot reach prod.

---

## Phase 10 — Day-2 operations

### Making a change

Never run `terraform apply` from your laptop against stage or prod after Phase 4. The flow is:

```bash
git checkout -b change-db-size
# edit config/main.tf (or a stacks/<component>/main.tf)
git commit -am "Bump stage DB to db.r8g.xlarge" && git push
gh pr create
# CI posts the plan on the PR -> review it -> merge -> CI applies
```

### Drift

If someone changes something in the AWS console, Terraform will try to change it back.

```bash
cd stacks/40-data
terraform plan -refresh-only     # shows what reality looks like versus state
```

### Kubernetes version upgrades

Bump `kubernetes_version` one minor at a time (1.36 → 1.37), stage first, then prod a week
later. Auto Mode handles the node rollout.

### Tearing down stage

```bash
cd stacks/40-data

# 1. Kubernetes must go first, or Terraform cannot delete the VPC. The NLB and its
#    security groups were created by Kubernetes and Terraform does not know about them.
kubectl delete -f deploy/k8s/api/
kubectl -n scribl get svc            # wait until no LoadBalancer remains

# 2. empty the versioned buckets
aws s3 rm "s3://$(terraform output -raw app_bucket_name)" --recursive
aws s3 rm "s3://$(terraform output -raw data_bucket_name)" --recursive

# 3. then Terraform
terraform destroy
```

Do not attempt this on prod. `db_deletion_protection = true` will stop it, which is the
intended behaviour.
