# Stage runbook: dry run first, then build, then access

Written for someone new to this project and to AWS. Every command says **where** you run it:
🖥️ your laptop, ☁️ AWS console, or 🐙 GitHub.

## Which shell to use on Windows

Every command is given twice: **macOS / Linux (bash)** and **Windows (PowerShell)**. Open
PowerShell, not Command Prompt — `cmd.exe` cannot do most of this.

Three Windows-specific things to know before you start:

- **`python3` is usually just `python`** on Windows. If `python` opens the Microsoft Store,
  install Python from python.org and tick "Add to PATH".
- **`openssl` is not installed by default.** Phase 9 needs it. PowerShell equivalents are given,
  or install Git for Windows, which bundles it.
- **`scripts/seed-secrets.sh` is a bash script.** There is a PowerShell twin,
  `scripts/seed-secrets.ps1`, that does exactly the same thing.

If you would rather not deal with any of that, install **WSL2** (`wsl --install` in an admin
PowerShell, then reboot) and use the bash commands throughout. That is the smoothest path if
you expect to do a lot of this work.

The whole thing is dry-run first. You will see a plan for all 13 components before a single
resource is created.

---

## What "dry run" means here

`terraform plan` **is** the dry run. It contacts AWS read-only, compares desired state to
reality, and prints what it would do. It creates nothing. There is no flag to remove afterwards
— you run `plan`, read it, then run `apply`.

```
terraform plan     → "Plan: 34 to add, 0 to change, 0 to destroy."   nothing happened
terraform apply    → same thing, then asks "Enter a value:" → you type yes
```

Three ways to get a dry run, all read-only:

| Where | How |
| --- | --- |
| 🖥️ Laptop | `terraform plan -var="environment=stage"` |
| 🐙 GitHub | Open a PR. CI plans every affected component and comments the output. |
| 🐙 GitHub | Actions → **Terraform Component (manual)** → component → **plan** |

CI's plan uses the `scribl-stage-tf-plan` role, which holds `ReadOnlyAccess`. Even if the code
were wrong, that role cannot change anything.

---

## Phase 0 — Laptop setup (🖥️, 30 min)

**macOS / Linux**

```bash
brew install terraform awscli kubernetes-cli gh
terraform version    # >= 1.9.0
aws --version        # >= 2.15
```

**Windows (PowerShell)**

```powershell
winget install --id Hashicorp.Terraform -e
winget install --id Amazon.AWSCLI -e
winget install --id Kubernetes.kubectl -e
winget install --id GitHub.cli -e
winget install --id Git.Git -e            # brings bash + openssl

# close and reopen PowerShell so PATH refreshes, then:
terraform version    # >= 1.9.0
aws --version        # >= 2.15
kubectl version --client
```

If `winget` is missing, install the "App Installer" from the Microsoft Store, or use Chocolatey:
`choco install terraform awscli kubernetes-cli gh git -y`.

Get admin credentials for the stage account:

**macOS / Linux**

```bash
aws configure sso --profile scribl-stage
# SSO start URL: https://<your-org>.awsapps.com/start
# region: us-east-1, role: AdministratorAccess

aws sso login --profile scribl-stage
export AWS_PROFILE=scribl-stage
aws sts get-caller-identity
```

**Windows (PowerShell)**

```powershell
aws configure sso --profile scribl-stage
# SSO start URL: https://<your-org>.awsapps.com/start
# region: us-east-1, role: AdministratorAccess

aws sso login --profile scribl-stage
$env:AWS_PROFILE = "scribl-stage"
aws sts get-caller-identity
```

`$env:AWS_PROFILE` lasts only for that PowerShell window. To make it stick across reboots:
`[Environment]::SetEnvironmentVariable("AWS_PROFILE","scribl-stage","User")`, then reopen
PowerShell.

That last command **must print `419717495525`**. If it doesn't, stop. Every stack has
`allowed_account_ids`, so Terraform will refuse anyway, but catch it here.

---

## Phase 1 — Get the code into GitHub (🖥️, 15 min)

### 1.1 Create the repository

```
gh repo create YourOrg/scribl-infra --private --description "Terraform for Scribl AWS infrastructure"
```

Or on github.com: **New repository** → Private → do **not** add a README or .gitignore, this
repo ships its own.

### 1.2 Put all 82 files in it

Unzip the archive. The `test/` folder is a wrapper — its **contents** become the repo root.

**macOS / Linux**

```bash
unzip scribl-infra-terraform-v8.zip
git clone https://github.com/YourOrg/scribl-infra.git
cd scribl-infra
cp -r ../test/. .          # the trailing /. matters - it copies dotfiles too
chmod +x scripts/seed-secrets.sh
ls -a                      # .github and .gitignore must be listed
```

**Windows (PowerShell)**

```powershell
Expand-Archive scribl-infra-terraform-v8.zip -DestinationPath .
git clone https://github.com/YourOrg/scribl-infra.git
cd scribl-infra
Copy-Item -Path ..\test\* -Destination . -Recurse -Force
Copy-Item -Path ..\test\.github, ..\test\.gitignore -Destination . -Recurse -Force
Get-ChildItem -Force | Select-Object Name    # .github and .gitignore must be listed
```

On Windows `Copy-Item ..\test\*` silently skips dot-prefixed entries, which is why `.github`
and `.gitignore` are copied on a second line. Miss them and CI never runs.

You should now see:

```
.github/  .gitignore  README.md  bootstrap/  config/  docs/  envs/  modules/  scripts/  stacks/
```

### 1.3 Edit your own values

Open `config/main.tf`, the `stage = { ... }` block. Full list in
[10-VALUES-TO-CHANGE.md](10-VALUES-TO-CHANGE.md). Already correct: account id, `stage` naming
token, `ses_domain = "stg.scribl.co"`, Postgres `18.3`.

Change these three:

```hcl
github_org  = "ScriblOrg"          # your org
github_repo = "scribl-infra"       # the repo holding this code
github_allowed_subjects = [
  "repo:<org>/<repo>:ref:refs/heads/main",
  "repo:<org>/<repo>:environment:stage",
]
```

Check the Cognito domain prefix is free — this one fails late in the apply if taken:

**macOS / Linux / Windows** — identical, no shell-specific syntax:

```
aws cognito-idp describe-user-pool-domain --domain scribl-stage-admin-auth
# "ResourceNotFoundException" = free. Anything else = pick another name.
```

Check Postgres 18.3 exists in us-east-1 (this is the version the dev account runs):

**macOS / Linux**

```bash
aws rds describe-db-engine-versions --engine postgres \
  --query 'DBEngineVersions[?starts_with(EngineVersion, `18`)].[EngineVersion,DBParameterGroupFamily]' \
  --output table
```

**Windows (PowerShell)** — JMESPath accepts single-quoted string literals, so this version
avoids backticks entirely and works in both shells:

```powershell
aws rds describe-db-engine-versions --engine postgres `
  --query "DBEngineVersions[?starts_with(EngineVersion, '18')].[EngineVersion,DBParameterGroupFamily]" `
  --output table
```

PowerShell's line-continuation character is a backtick at end of line, not a backslash.

### 1.4 First commit — everything

This is the big one: all 82 files.

```
git add -A
git status              # sanity check: ~82 files, including .github/workflows/
git commit -m "Terraform for Scribl stage and prod infrastructure"
git push origin main
```

At this point `envs/stage.backend.hcl` still says `REPLACE_ME_WITH_BOOTSTRAP_OUTPUT`. That is
expected — the state bucket does not exist yet. Phase 2 creates it and Phase 2.4 fills the
value in.

**Before your first push on Windows**, set line endings so the bash script and the YAML
workflows survive the trip to Linux CI runners:

```powershell
git config --global core.autocrlf input
```

---

## Phase 2 — Bootstrap (🖥️, 10 min)

### 2.1 What this is

This is the only Terraform run using admin credentials. It creates the state bucket, the GitHub
OIDC provider, and the two CI roles. It cannot run in CI, because it creates the roles CI uses.

### 2.2 Create your tfvars and apply

There is no `bootstrap/terraform.tfvars` in the repo — only
`bootstrap/terraform.tfvars.stage.example`. You copy it and edit the copy; `.gitignore` keeps
your copy local.

**macOS / Linux**

```bash
cd bootstrap
cp terraform.tfvars.stage.example terraform.tfvars
# set github_org / github_repo in that file

terraform init
terraform plan        # DRY RUN — expect ~15 to add
terraform apply       # type: yes
terraform output
```

**Windows (PowerShell)**

```powershell
cd bootstrap
Copy-Item terraform.tfvars.stage.example terraform.tfvars
notepad terraform.tfvars      # set github_org / github_repo

terraform init
terraform plan        # DRY RUN — expect ~15 to add
terraform apply       # type: yes
terraform output
```

### 2.3 Record three values

| Output | Goes to |
| --- | --- |
| `state_bucket` | `envs/stage.backend.hcl`, replacing `REPLACE_ME_WITH_BOOTSTRAP_OUTPUT` |
| `tf_plan_role_arn` | 🐙 repo variable `AWS_TF_PLAN_ROLE_STAGE` |
| `tf_apply_role_arn` | 🐙 repo variable `AWS_TF_APPLY_ROLE_STAGE` |

### 2.4 Second commit — only what bootstrap changed

The whole repo already went up in Phase 1.4. This is a follow-up commit covering just the three
files that changed during Phase 2:

| File | What changed |
| --- | --- |
| `envs/stage.backend.hcl` | you pasted the real `state_bucket` name into it |
| `bootstrap/terraform.tfstate` | created by `terraform apply` — new file |
| `config/main.tf` | any edits from Phase 1.3 you have not pushed yet |

Identical in both shells:

```
cd ..
git add bootstrap/terraform.tfstate envs/stage.backend.hcl config/main.tf
git commit -m "Bootstrap stage: state bucket and CI roles"
git push
```

`git add -A` would work just as well here. The three paths are listed explicitly only to show
what should have changed — if `git status` shows something else modified, look at it before
committing.

**Why `bootstrap/terraform.tfstate` is committed on purpose.** Every other `*.tfstate` is
gitignored; this one has an exception. It is a few KB, holds no secrets, and it is the only
record of the CI roles and the state bucket. Lose it and you cannot cleanly change CI
permissions later — you would have to import or recreate them. Every other component keeps its
state in S3, which does not exist yet at this point in the process.

---

## Phase 3 — Connect GitHub to AWS (🐙, 15 min)

**Settings → Secrets and variables → Actions → Variables tab** (variables, *not* secrets):

| Name | Value |
| --- | --- |
| `AWS_TF_PLAN_ROLE_STAGE` | the plan role ARN |
| `AWS_TF_APPLY_ROLE_STAGE` | the apply role ARN |

**Settings → Environments** → create `stage` and `prod`. Spelling matters; the names appear
literally in the IAM trust policies. Add required reviewers on `prod`.

**Settings → Branches** → protect `main`: require a PR, 1 approval, require the plan checks.

**No AWS access keys.** If `AWS_ACCESS_KEY_ID` exists in Secrets, delete it — nothing here uses
it.

---

## Phase 4 — One account-level thing the console must do (☁️, 2 min)

API Gateway needs an account-level role before it can write access logs. It is set once per
account and Terraform cannot create it without also creating IAM plumbing that conflicts with
the console setting.

☁️ **API Gateway → Settings → CloudWatch log role ARN** → create/attach a role with
`AmazonAPIGatewayPushToCloudWatchLogs`.

Skip this and `80-api` still applies, but access logs stay empty.

---

## Phase 5 — THE DRY RUN (🖥️, 20 min)

Nothing is created here. This is the step you asked for.

**macOS / Linux**

```bash
cd stacks

for C in 10-network 20-edge 30-registry 32-messaging 34-identity \
         36-secrets 38-email 40-data 50-iam 60-eks 70-tools; do
  echo "═══════════════ PLAN: $C ═══════════════"
  ( cd "$C" \
    && terraform init -input=false \
         -backend-config=../../envs/stage.backend.hcl \
         -backend-config="key=stage/$C.tfstate" >/dev/null \
    && terraform plan -input=false -lock=false -var="environment=stage" -no-color ) \
    | tee "/tmp/plan-$C.txt" | tail -30
done
```

Every plan is saved under `/tmp/plan-*.txt`. Read them.

**Windows (PowerShell)**

```powershell
cd stacks
New-Item -ItemType Directory -Force -Path "$env:TEMP\tfplans" | Out-Null

$components = @(
  "10-network","20-edge","30-registry","32-messaging","34-identity",
  "36-secrets","38-email","40-data","50-iam","60-eks","70-tools"
)

foreach ($c in $components) {
  Write-Host "=============== PLAN: $c ===============" -ForegroundColor Cyan
  Push-Location $c
  terraform init -input=false `
    -backend-config=../../envs/stage.backend.hcl `
    -backend-config="key=stage/$c.tfstate" | Out-Null
  terraform plan -input=false -lock=false -var="environment=stage" -no-color |
    Tee-Object -FilePath "$env:TEMP\tfplans\plan-$c.txt" |
    Select-Object -Last 30
  Pop-Location
}
```

Every plan is saved under `%TEMP%\tfplans\`. Open that folder with
`explorer $env:TEMP\tfplans` and read them.

`-lock=false` is safe and deliberate here: `plan` never writes state, so it has no reason to
take a lock. Without it, interrupting the loop (Ctrl+C, or a component erroring) leaves a stale
lock behind and the next run fails with `Error acquiring the state lock`. Never use
`-lock=false` on `apply` — there the lock is what stops two applies corrupting the same state.

If you do hit a stale lock, the error prints its ID:

```powershell
cd stacks\50-iam
terraform force-unlock <THE-ID-FROM-THE-ERROR>
```

### If you see: S3 bucket "..." does not exist

```
Error: Error loading state error
  with data.terraform_remote_state.network,
error loading the remote state: S3 bucket "scribl-stage-tfstate-419717495525" does not exist.
```

Look at the bucket name in the error. If it ends in the **account number**
(`...-tfstate-419717495525`) you are on an old copy of this repo. The state bucket name ends in
a random token, not the account id. `config/main.tf` used to compute the wrong name while
`envs/stage.backend.hcl` held the right one — so `terraform init` connected to the correct
bucket but the `terraform_remote_state` data sources looked for a different, non-existent one.

Fix: take `config/main.tf` from v10 or later, where `state_bucket` is read out of
`envs/<environment>.backend.hcl` instead of being computed. One file holds the name; init and
the data sources both read it.

```powershell
Select-String -Path config\main.tf -Pattern "state_bucket"
# should show:  state_bucket = regex(... envs/${var.environment}.backend.hcl ...)
# NOT:          state_bucket = "${local.name_prefix}-tfstate-${local.env.account_id}"
```

Confirm the bucket that actually exists:

```
aws s3 ls | Select-String "tfstate"
```

and make sure `envs/stage.backend.hcl` names exactly that.

### If you see: Unable to find remote state

**Components after `10-network` will fail this first dry run** with `Unable to find remote
state`. That is expected and harmless — `40-data` reads the VPC's subnet ids from network's
state, which does not exist until network is applied. Plan `10-network` first, apply it, then
the rest plan cleanly.

What to check in the output:

| Component | Look for |
| --- | --- |
| `10-network` | 3 private + 3 public subnets, 1 NAT, `0.0.0.0/0` on private routes points at a NAT not an IGW |
| `40-data` | `publicly_accessible = false`, `storage_encrypted = true` |
| `60-eks` | `subnet_ids` are the three **private** ids, `endpoint_public_access = false` |
| `20-edge` | one `custom_error_response` (403), `price_class = PriceClass_All`, `cloudfront_default_certificate = true`, **no aliases** |
| all | every resource has `Project`, `Environment`, `ManagedBy`, `Component`, `Name` tags |

Total across all components: roughly **190 resources to add, 0 to change, 0 to destroy**. Any
"destroy" on a first run means something already exists that shouldn't — stop and investigate.

---

## Phase 6 — Apply, in order (🖥️, 45 min)

Same loop, `apply` instead of `plan`. Order matters: lower numbers first.

**macOS / Linux**

```bash
cd stacks

for C in 10-network 20-edge 30-registry 32-messaging 34-identity \
         36-secrets 38-email 40-data 50-iam 60-eks 70-tools; do
  echo "═══════════════ APPLY: $C ═══════════════"
  ( cd "$C" \
    && terraform init -input=false \
         -backend-config=../../envs/stage.backend.hcl \
         -backend-config="key=stage/$C.tfstate" \
    && terraform apply -input=false -auto-approve -var="environment=stage" ) || break
done
```

`|| break` stops at the first failure rather than pressing on into dependents.

**Windows (PowerShell)**

```powershell
cd stacks

$components = @(
  "10-network","20-edge","30-registry","32-messaging","34-identity",
  "36-secrets","38-email","40-data","50-iam","60-eks","70-tools"
)

foreach ($c in $components) {
  Write-Host "=============== APPLY: $c ===============" -ForegroundColor Green
  Push-Location $c
  terraform init -input=false `
    -backend-config=../../envs/stage.backend.hcl `
    -backend-config="key=stage/$c.tfstate"
  if ($LASTEXITCODE -ne 0) { Pop-Location; Write-Host "init failed on $c" -ForegroundColor Red; break }

  terraform apply -input=false -auto-approve -var="environment=stage"
  if ($LASTEXITCODE -ne 0) { Pop-Location; Write-Host "apply failed on $c" -ForegroundColor Red; break }
  Pop-Location
}
```

PowerShell does not stop on a failed native command, so the explicit `$LASTEXITCODE` checks are
what make this equivalent to bash's `|| break`. Without them the loop would charge on into
components whose dependencies never got created.

Prefer one at a time with a manual yes? That is the safer habit:

**macOS / Linux**

```bash
cd stacks/10-network
terraform init -input=false \
  -backend-config=../../envs/stage.backend.hcl \
  -backend-config="key=stage/10-network.tfstate"
terraform plan  -lock=false -var="environment=stage"   # read it
terraform apply -var="environment=stage"     # type yes
```

**Windows (PowerShell)**

```powershell
cd stacks\10-network
terraform init -input=false `
  -backend-config=../../envs/stage.backend.hcl `
  -backend-config="key=stage/10-network.tfstate"
terraform plan  -lock=false -var="environment=stage"   # read it
terraform apply -var="environment=stage"     # type yes
```

Backslashes are fine in `cd`, but leave the `-backend-config` paths with forward slashes —
Terraform wants those regardless of platform.

Slow ones: `40-data` ~20 min (RDS + Redis), `60-eks` ~15 min, `20-edge` ~6 min (CloudFront).

If one fails, fix and re-run **that component only**. Nothing else is touched.

---

## Phase 7 — DNS (🖥️ + wherever scribl.co is hosted, 20 min + waiting)

There is no Route 53 zone in this account, so DNS is manual.

**SES:**

**macOS / Linux**

```bash
cd ../38-email
terraform output -json dns_records | python3 -m json.tool
```

**Windows (PowerShell)** — no `python3` needed, PowerShell formats JSON itself:

```powershell
cd ..\38-email
terraform output -json dns_records | ConvertFrom-Json | Format-Table type, name, value

# or as a readable list
terraform output -json dns_records | ConvertFrom-Json | Format-List
```

Four records: 1 TXT at `_amazonses.stg.scribl.co` for ownership, and 3 DKIM CNAMEs. There is no
MAIL FROM domain, matching dev.

Two traps: most DNS UIs append the zone automatically, so enter
`<token>._domainkey.stg`  (the label before `.scribl.co`) not the full name; and DKIM CNAMEs must not be proxied
(Cloudflare orange cloud off).

Identical in both shells:

```
aws ses get-identity-verification-attributes --identities stg.scribl.co
aws ses get-identity-dkim-attributes --identities stg.scribl.co
```

**You are in the SES sandbox** until you ask not to be — 200 emails/day, only to verified
addresses. Verifying the domain does not change that. ☁️ SES → Account dashboard → Request
production access. 24–48 hours.

---

## Phase 8 — Certificate and CloudFront alias (☁️ then 🖥️, 15 min)

Terraform no longer manages ACM. Issue the certificate yourself:

☁️ **ACM → make sure the region selector says N. Virginia (us-east-1)** — CloudFront accepts
certificates from no other region — **→ Request certificate → `mweb.stage.scribl.co` → DNS
validation.** ACM gives you one CNAME. Publish it wherever `scribl.co` is hosted and wait for
the status to become ISSUED.

Check from either shell:

```
aws acm list-certificates --region us-east-1 --query "CertificateSummaryList[].[DomainName,Status]" --output table
```

Only once it shows ISSUED, paste the ARN into `config/main.tf`:

```hcl
# config/main.tf, stage block
cloudfront_certificate_arn = "arn:aws:acm:us-east-1:419717495525:certificate/..."
# cloudfront_aliases is already ["mweb.stage.scribl.co"] - it is simply not
# applied while the certificate ARN is empty.
```

The alias is deliberately gated. CloudFront returns `InvalidViewerCertificate` if you attach an
alternate domain name with no custom certificate, so an ungated alias would fail every apply
until the certificate existed.

PR → CI plans `20-edge` → merge → applied. In-place update, no distribution replacement.

Finally, point `mweb.stage.scribl.co` at the distribution as a CNAME:

```
cd stacks/20-edge
terraform output -raw cloudfront_domain_name        # d3xxxxxxxxxxx.cloudfront.net
```

---

## Phase 9 — Secrets and database (🖥️, 30 min)

**macOS / Linux**

```bash
chmod +x scripts/seed-secrets.sh
./scripts/seed-secrets.sh stage
```

**Windows (PowerShell)** — a PowerShell twin of the same script:

```powershell
.\scripts\seed-secrets.ps1 stage
```

If PowerShell refuses with "running scripts is disabled on this system", allow local scripts
for your user once:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

Everything is in private subnets, so reach the database through the tools host:

**macOS / Linux**

```bash
cd stacks/70-tools && terraform output -raw instance_id      # i-xxxx
cd ../40-data      && terraform output -raw db_proxy_endpoint

aws ssm start-session --target <INSTANCE_ID> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["<DB_PROXY_ENDPOINT>"],"portNumber":["5432"],"localPortNumber":["15432"]}'
```

**Windows (PowerShell)** — the SSM plugin must be installed first, and the JSON needs escaped
quotes because PowerShell strips them before the AWS CLI sees them:

```powershell
# one time only
winget install --id Amazon.SessionManagerPlugin -e
# reopen PowerShell afterwards

Push-Location stacks\70-tools
$instanceId = terraform output -raw instance_id
Pop-Location

Push-Location stacks\40-data
$dbHost = terraform output -raw db_proxy_endpoint
Pop-Location

aws ssm start-session --target $instanceId `
  --document-name AWS-StartPortForwardingSessionToRemoteHost `
  --parameters "{\`"host\`":[\`"$dbHost\`"],\`"portNumber\`":[\`"5432\`"],\`"localPortNumber\`":[\`"15432\`"]}"
```

If that quoting fights you — and it often does — write the parameters to a file instead, which
is far more robust:

```powershell
@{ host=@($dbHost); portNumber=@("5432"); localPortNumber=@("15432") } |
  ConvertTo-Json -Compress | Set-Content -Encoding ascii params.json

aws ssm start-session --target $instanceId `
  --document-name AWS-StartPortForwardingSessionToRemoteHost `
  --parameters file://params.json
```

Leave that running. In another terminal, `localhost:15432` is the database.

**macOS / Linux**

```bash
aws secretsmanager get-secret-value \
  --secret-id "$(terraform output -raw db_master_secret_arn)" \
  --query SecretString --output text | python3 -m json.tool

psql "postgresql://scribl_admin:<PASS>@localhost:15432/scribl?sslmode=require" -c '\l'
```

**Windows (PowerShell)**

```powershell
Push-Location stacks\40-data
$secretArn = terraform output -raw db_master_secret_arn
Pop-Location

$creds = aws secretsmanager get-secret-value --secret-id $secretArn `
           --query SecretString --output text | ConvertFrom-Json
$creds.username
$creds.password

# psql comes with the PostgreSQL client:  winget install --id PostgreSQL.PostgreSQL.17 -e
psql "postgresql://$($creds.username):$($creds.password)@localhost:15432/scribl?sslmode=require" -c "\l"
```

---

## Phase 10 — Kubernetes (🖥️, 30 min)

Identical in both shells:

```
aws eks update-kubeconfig --name scribl-stage-eks --region us-east-1
kubectl get nodes
```

On Windows the kubeconfig lands at `%USERPROFILE%\.kube\config`.

**Zero nodes is correct** on a fresh Auto Mode cluster — nodes appear when a pod needs
scheduling. If it hangs instead, you are outside the VPC and the API endpoint is private. Either
connect through the tools host, or temporarily set `eks_endpoint_public_access = true` with
`eks_public_access_cidrs = ["<your-ip>/32"]`.

```
kubectl create namespace scribl
```

Service accounts must be named exactly `scribl-api` and `scribl-admin-api` in namespace
`scribl` — both pod identity associations already exist and point at `scribl-api-pod`.

Push an image, apply your manifests, then read docs/04 for the NLB scheme annotation.

---

## Phase 11 — Wire up the two NLBs (🖥️, 20 min)

**macOS / Linux**

```bash
VPC=$(cd stacks/10-network && terraform output -raw vpc_id)
aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?VpcId=='$VPC'].{Name:LoadBalancerName,Scheme:Scheme,DNS:DNSName,Arn:LoadBalancerArn}" \
  --output table
```

**Windows (PowerShell)**

```powershell
Push-Location stacks\10-network
$vpc = terraform output -raw vpc_id
Pop-Location

aws elbv2 describe-load-balancers `
  --query "LoadBalancers[?VpcId=='$vpc'].{Name:LoadBalancerName,Scheme:Scheme,DNS:DNSName,Arn:LoadBalancerArn}" `
  --output table
```

PowerShell expands `$vpc` inside double quotes before the AWS CLI sees it, which is what you
want here.

Two entries. In `config/main.tf`:

```hcl
enable_api_gateway = true
nlb_arn            = "arn:...:loadbalancer/net/k8s-scribl-scriblap-..."   # PRODUCT NLB
admin_nlb_dns_name = "k8s-scribl-scriblad-....elb.amazonaws.com"         # ADMIN NLB
```

PR → plan → merge. CI applies `20-edge` (admin origin + 3 behaviours) and `80-api`.

---

## Phase 12 — How to access everything (🖥️)

| What | How |
| --- | --- |
| Tools host shell | `aws ssm start-session --target <id>` — no SSH key, no public IP |
| Database | SSM port-forward, Phase 9 |
| Redis | same port-forward, port 6379, TLS + auth token from `scribl/stage/redis/auth-token` |
| Kubernetes | `aws eks update-kubeconfig --name scribl-stage-eks` from inside the VPC |
| SPA | `cd stacks/20-edge && terraform output -raw cloudfront_domain_name` |
| API | `cd stacks/80-api && terraform output -raw invoke_url` |
| Secrets | `aws secretsmanager get-secret-value --secret-id scribl/stage/api` |
| Endpoints | `terraform output` in the relevant component |
| Logs | ☁️ CloudWatch → Log groups → `/aws/service-events/scribl-api` |
| Alarms | ☁️ CloudWatch → Alarms, or set `alarm_email` to get notified |

Everything in one go:

**macOS / Linux**

```bash
for C in stacks/*/; do
  echo "=== $(basename $C) ==="
  (cd "$C" && terraform output 2>/dev/null)
done
```

**Windows (PowerShell)**

```powershell
Get-ChildItem stacks -Directory | ForEach-Object {
  Write-Host "=== $($_.Name) ===" -ForegroundColor Cyan
  Push-Location $_.FullName
  terraform output 2>$null
  Pop-Location
}
```

---

## Phase 13 — Day-2

Never apply from your laptop after Phase 6.

**macOS / Linux**

```bash
git checkout -b bump-redis
vim config/main.tf
git commit -am "Bump stage Redis" && git push && gh pr create
# CI plans ONLY 40-data → review → merge → CI applies ONLY 40-data
```

**Windows (PowerShell)**

```powershell
git checkout -b bump-redis
notepad config\main.tf
git commit -am "Bump stage Redis"
git push --set-upstream origin bump-redis
gh pr create
```

Teardown, reverse order, Kubernetes first:

**macOS / Linux**

```bash
kubectl delete -f deploy/k8s/          # NLBs must go before the VPC
aws s3 rm "s3://$(cd stacks/20-edge && terraform output -raw app_bucket_name)" --recursive
aws s3 rm "s3://$(cd stacks/20-edge && terraform output -raw data_bucket_name)" --recursive

for C in 80-api 70-tools 60-eks 50-iam 40-data 38-email 36-secrets \
         34-identity 32-messaging 30-registry 20-edge 10-network; do
  (cd "stacks/$C" && terraform destroy -var="environment=stage")
done
```

**Windows (PowerShell)**

```powershell
kubectl delete -f deploy/k8s/          # NLBs must go before the VPC

Push-Location stacks\20-edge
$appBucket  = terraform output -raw app_bucket_name
$dataBucket = terraform output -raw data_bucket_name
Pop-Location

aws s3 rm "s3://$appBucket"  --recursive
aws s3 rm "s3://$dataBucket" --recursive

$reverse = @(
  "80-api","70-tools","60-eks","50-iam","40-data","38-email","36-secrets",
  "34-identity","32-messaging","30-registry","20-edge","10-network"
)

foreach ($c in $reverse) {
  Write-Host "=============== DESTROY: $c ===============" -ForegroundColor Red
  Push-Location "stacks\$c"
  terraform destroy -var="environment=stage"
  Pop-Location
}
```


---

## Appendix — Windows gotchas, collected

| Symptom | Cause | Fix |
| --- | --- | --- |
| `python3 : term not recognized` | Windows calls it `python` | use `python`, or the PowerShell JSON cmdlets shown above |
| `openssl : term not recognized` | not bundled with Windows | `winget install Git.Git`, then use Git Bash, or use the `.ps1` script |
| `running scripts is disabled on this system` | default ExecutionPolicy | `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned` |
| `SessionManagerPlugin is not found` | SSM plugin missing | `winget install --id Amazon.SessionManagerPlugin -e`, reopen PowerShell |
| The loop keeps going after a component fails | PowerShell ignores native exit codes | the `$LASTEXITCODE` checks in the Phase 6 loop are what stop it |
| `--parameters` JSON rejected by the AWS CLI | PowerShell strips the inner quotes | use the `file://params.json` form in Phase 9 |
| A backslash at end of line does nothing | that is bash's continuation, not PowerShell's | use a backtick `` ` `` |
| `terraform: command not found` right after install | PATH not refreshed | close and reopen PowerShell |
| Odd characters in terraform output | PowerShell 5.1 console encoding | `$OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8`, or use PowerShell 7 (`winget install Microsoft.PowerShell`) |
| Git turns LF into CRLF and shell scripts break in CI | `core.autocrlf` | `git config --global core.autocrlf input` before you clone |

That last one is worth doing before you push anything. The repo contains a bash script and YAML
workflows that run on Linux runners; CRLF line endings will break them in ways that are
annoying to diagnose.
