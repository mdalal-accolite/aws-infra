# scribl-infra

Terraform for the Scribl platform. One repository, two environments (`stage` and `prod`), each
in its own AWS account. Rebuilt from the `AWS_RESOURCE_INVENTORY.md` audit of the dev account,
with two deliberate changes: **everything runs in private subnets**, and the infrastructure is
split into **independently deployable components** so a change to one resource only runs the
pipeline for that resource.

## Read the docs in order

| Doc | What it covers |
| --- | --- |
| [docs/01-PHASES.md](docs/01-PHASES.md) | **Start here.** Every phase, every command |
| [docs/02-IAM-AND-GITHUB-ACCESS.md](docs/02-IAM-AND-GITHUB-ACCESS.md) | Roles, policies, OIDC |
| [docs/03-CHANGES-FROM-DEV.md](docs/03-CHANGES-FROM-DEV.md) | Diff versus the dev account |
| [docs/04-KUBERNETES-AND-NLB.md](docs/04-KUBERNETES-AND-NLB.md) | The manual step before API Gateway |
| [docs/05-CLIENT-VPN.md](docs/05-CLIENT-VPN.md) | Getting into the private network |
| [docs/06-TAGGING.md](docs/06-TAGGING.md) | The tagging model |
| [docs/07-NAMING.md](docs/07-NAMING.md) | **Naming convention**, full table |
| [docs/08-COMPONENTS-AND-PIPELINE.md](docs/08-COMPONENTS-AND-PIPELINE.md) | **Per-component state and CI** |
| [docs/09-SES-EMAIL.md](docs/09-SES-EMAIL.md) | **SES domain verification and sending** |
| [docs/10-VALUES-TO-CHANGE.md](docs/10-VALUES-TO-CHANGE.md) | **Every value you must set yourself** |
| [docs/11-NOT-IN-TERRAFORM.md](docs/11-NOT-IN-TERRAFORM.md) | **What is in dev but not here, and why** |
| [docs/12-RUNBOOK-STAGE.md](docs/12-RUNBOOK-STAGE.md) | **Stage: dry run, build, access. Commands for macOS/Linux *and* Windows** |

## Repository map

```
.
├── config/                     ← EVERY environment-specific value lives here
│   └── main.tf                   one block for stage, one for prod
│
├── envs/
│   ├── stage.backend.hcl       state bucket for stage  (419717495525)
│   └── prod.backend.hcl        state bucket for prod   (882781045478)
│
├── scripts/
│   ├── seed-secrets.sh         writes the real Secrets Manager values, once (bash)
│   └── seed-secrets.ps1        the same thing on Windows (PowerShell)
│
├── bootstrap/                  run ONCE per AWS account, from your laptop
│                               creates: state bucket, GitHub OIDC provider,
│                               tf-plan role, tf-apply role
│
├── stacks/                     13 components, each with its OWN state file
│   ├── 10-network/             VPC, subnets, NAT, endpoints, security groups
│   ├── 20-edge/                S3, CloudFront (4 behaviours), OAC, WAF, logs
│   ├── 30-registry/            ECR
│   ├── 32-messaging/           SQS, DLQ, SNS alarm topic
│   ├── 34-identity/            Cognito pools and clients
│   ├── 36-secrets/             Secrets Manager, API GW log group
│   ├── 38-email/               SES domain, DKIM, MAIL FROM, config set
│   ├── 40-data/                RDS Postgres 18, RDS Proxy, Redis, alarms
│   ├── 50-iam/                 app pod role, CI deploy roles
│   ├── 60-eks/                 EKS Auto Mode, add-ons, pod identity
│   ├── 70-tools/               KiwiTCMS EC2 host
│   ├── 80-api/                 API Gateway, VPC link
│   └── 90-vpn/                 Client VPN (optional)
│
├── modules/                    reusable building blocks; you rarely edit these
│   ├── network/  data/  eks/  ec2-tools/  storage-cdn/
│   ├── ecr/  messaging/  cognito/  secrets/  ses/
│   └── iam/  api-gateway/  client-vpn/
│
└── .github/workflows/
    ├── terraform-plan.yml        plans only the components a PR touches
    ├── terraform-apply.yml       applies only those, in dependency order
    └── terraform-component.yml   manual: one component, plan/apply/destroy
```

## Naming

```
scribl-<environment>-<resource_type>
```

`scribl-stage-db`, `scribl-stage-vpc`, `scribl-stage-eks`, `scribl-stage-redis`,
`scribl-stage-api-pod-role`. **No AWS account number appears in any resource name** — S3
buckets use a stable random token instead. Full table in [docs/07-NAMING.md](docs/07-NAMING.md).

## The 60-second version

```bash
# 1. once per AWS account, from your laptop, as an admin
cd bootstrap
cp terraform.tfvars.stage.example terraform.tfvars
terraform init && terraform apply

# 2. put the state bucket in envs/stage.backend.hcl
#    put the account id and your SES domain in config/main.tf

# 3. build stage, component by component
cd ../stacks
for C in 10-network 20-edge 30-registry 32-messaging 34-identity \
         36-secrets 38-email 40-data 50-iam 60-eks 70-tools; do
  ( cd "$C" \
    && terraform init -input=false \
         -backend-config=../../envs/stage.backend.hcl \
         -backend-config="key=stage/$C.tfstate" \
    && terraform apply -input=false -auto-approve -var="environment=stage" ) || break
done
```

After that first build you never loop again — edit a file, open a PR, and CI plans just the
affected component.

## Changing one thing later

```bash
# change the Redis instance size
vim config/main.tf          # redis_node_type
git commit -am "Bump stage Redis to cache.t4g.small" && git push && gh pr create
# CI plans 40-data. Merge. CI applies 40-data. Nothing else runs.
```

## Not in here on purpose

- **ACM certificates.** Skipped as requested, so `90-vpn` is disabled by default — a Client VPN
  endpoint cannot exist without a server certificate. See docs/05.
- **IAM users and groups.** Skipped as requested. Human access comes from AWS IAM Identity
  Center (SSO). The CI apply role has an explicit `Deny` on all user and group actions, so this
  stays true even if someone adds an `aws_iam_user` resource. See docs/02.

## Rough monthly cost, stage

| Item | USD/month |
| --- | --- |
| EKS control plane | 73 |
| EKS Auto Mode nodes (2 small) | 60–120 |
| RDS `db.r8g.large`, single-AZ, 100 GiB gp3 | 230 |
| RDS Proxy | 22 |
| NAT Gateway ×1 + data processing | 35–60 |
| 12 interface VPC endpoints | 85 |
| EC2 `c8i.xlarge` tools host | 145 |
| ElastiCache `cache.t4g.micro` | 12 |
| CloudFront, S3, SQS, Cognito, SES, logs | 15–40 |
| **Total** | **≈ 680–790** |

Cheapest levers: `enable_tools_ec2 = false`, `db_instance_class = "db.t4g.large"`, and trim
`interface_endpoints` in `modules/network/variables.tf`.
