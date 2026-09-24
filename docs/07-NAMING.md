# Naming convention

## The pattern

```
scribl-<environment>-<resource_type>
  │        │              │
  │        │              └── what the thing is: db, redis, eks, vpc, api ...
  │        └───────────────── stg | prod   (matches stg.scribl.co)
  └────────────────────────── project, always "scribl"
```

The environment token is **`stage`**, not `stage`, so resource names line up with the DNS names
(`stg.scribl.co`, `mweb.stg.scribl.co`) and with the dev account's `scribl-dev-*` pattern.
Directory names, state keys and GitHub Environments still say `stage`, because those are
human-facing rather than resource names. The token lives in `config/main.tf` as `name_token`.

Names below mirror the 2026-09-20 dev inventory with `dev` swapped for `stage`.

Your example, `scribl-<environment>-db`, is the anchor. Everything follows it.

The first two segments come from one place — `local.name_prefix` in `config/main.tf`:

```hcl
name_prefix = "${local.project}-${var.environment}"   # scribl-stage
```

No module ever hardcodes `scribl` or `stage`. Every resource name is
`"${var.name_prefix}-<type>"`, so renaming the project or adding an environment is a one-line
change.

## Full table (stage shown; swap `stage` for `prod`)

### Network
| Resource | Name |
| --- | --- |
| VPC | `scribl-stage-vpc` |
| Private subnet | `scribl-stage-subnet-private-us-east-1a` |
| Public subnet | `scribl-stage-subnet-public-us-east-1a` |
| Internet gateway | `scribl-stage-igw` |
| NAT gateway | `scribl-stage-nat-1` |
| NAT elastic IP | `scribl-stage-nat-eip-1` |
| Public route table | `scribl-stage-rtb-public` |
| Private route table | `scribl-stage-rtb-private-us-east-1a` |
| S3 gateway endpoint | `scribl-stage-vpce-s3` |
| Interface endpoint | `scribl-stage-vpce-ecr-api` |

### Security groups — `<prefix>-<what it protects>-sg`
| Resource | Name |
| --- | --- |
| Database | `scribl-stage-db-sg` |
| RDS Proxy | `scribl-stage-db-proxy-sg` |
| Redis | `scribl-stage-redis-sg` |
| Tools host / Client VPN | `scribl-stage-ec2` (inventory name) |
| VPC endpoints | `scribl-stage-vpce-sg` |
| Client VPN | `scribl-stage-vpn-sg` |

### Data
| Resource | Name |
| --- | --- |
| RDS instance | `scribl-stage-db` |
| DB subnet group | `scribl-stage-db-subnets` |
| DB parameter group | `scribl-stage-db-pg` |
| RDS Proxy | `scribl-stage-db-proxy` |
| Final snapshot | `scribl-stage-db-final` |
| Redis replication group | `scribl-stage-redis` |
| Redis subnet group | `scribl-stage-redis-subnets` |

### Compute
| Resource | Name |
| --- | --- |
| EKS cluster | `scribl-stage-eks` |
| Tools EC2 instance | `scribl-stage-tools-ec2` |
| Tools root volume | `scribl-stage-tools-ec2-volume` |
| Tools instance profile | `scribl-stage-tools-ec2-profile` |
| Tools key pair | `scribl-stage-tools-ec2-key` |

### Edge / storage
| Resource | Name |
| --- | --- |
| SPA bucket | `scribl-stage-app-k3m9x2` |
| Media bucket | `scribl-stage-data-k3m9x2` |
| CloudFront distribution | `scribl-stage-app` (comment) |
| Origin access control | `scribl-stage-app-oac` |
| WAF web ACL | `scribl-stage-cloudfront-waf` |
| API Gateway REST API | `scribl-stage-api` |
| API Gateway VPC link | `scribl-stage-api-vpclink` |
| Client VPN endpoint | `scribl-stage-vpn` |

S3 bucket names must be unique across **all of AWS**, not just your account, so something
unique has to go in the name. An account id would work but then the account number appears in
every bucket ARN, CloudTrail line, error message and screenshot, so a stable 6-character random
token is generated instead and kept in Terraform state forever. The same applies to the
Terraform state buckets created by `bootstrap/`.

**No AWS account number appears in any resource name.** It still appears inside IAM and Secrets
Manager *ARNs*, because AWS constructs ARNs that way and there is no option to leave it out.

If you would rather choose the token yourself, set `bucket_suffix` on the `storage-cdn` module
and the random one is ignored.

### Containers, messaging, identity, email
| Resource | Name |
| --- | --- |
| ECR repo | `scribl-mobile-app-stage`, `meta-scribl-mobile-app-stage` (env as a **suffix** here, so the repo sorts next to its dev twin) |
| SQS queue | `scribl-stage-push-nudge` |
| SQS dead-letter queue | `scribl-stage-push-nudge-dlq` |
| SNS alarm topic | `scribl-stage-cloudwatch-alarms` |
| Cognito mobile pool | `scribl-mobile-stage` (dev pattern: app-then-env) |
| Cognito admin pool | `scribl-admin-stage` |
| Cognito mobile client | `Scribl Mobile App` |
| Cognito admin SPA client | `admin-spa` |
| Cognito admin BFF client | `admin-bff` |
| Cognito hosted-UI domain | `scribl-stage-admin-auth` |
| SES configuration set | `scribl-stage-ses-config-set` |
| SES event destination | `scribl-stage-ses-bounces` |

Note the dev account's ECR repos are `scribl-mobile-app` with no environment segment, which is
exactly the ambiguity this convention removes — you could not tell a dev image from a prod one.

### IAM roles — always `-role` suffixed
| Resource | Name |
| --- | --- |
| EKS cluster role | `scribl-stage-eks-cluster-role` |
| EKS node role | `scribl-stage-eks-node-role` |
| CloudWatch agent role | `scribl-stage-eks-cloudwatch-agent-role` |
| App pod role | `scribl-api-pod` (inventory name; each env is its own account) |
| CI app deploy role | `scribl-github-api-deploy` |
| CI web release role | `scribl-github-web-release` |
| DB monitoring role | `rds-monitoring-role` (inventory name) |
| RDS Proxy role | `scribl-stage-db-proxy-role` |
| Tools EC2 role | `scribl-stage-tools-ec2-role` |
| Terraform plan role | `scribl-stage-tf-plan-role` |
| Terraform apply role | `scribl-stage-tf-apply-role` |

### Email and edge
| Resource | Name |
| --- | --- |
| Certificate | `mweb.stg.scribl.co`, `mapi.stg.scribl.co` (the domain *is* the name) |
| SES domain identity | `stg.scribl.co` |
| SES MAIL FROM | `mail.stg.scribl.co` |
| SES configuration set | `scribl-stage-ses-config-set` |
| CloudFront log bucket | `scribl-stage-cdn-logs-<token>` |

### Alarms — `<prefix>-<subject>-<metric>-alarm`
`scribl-stage-db-cpu-alarm`, `scribl-stage-db-storage-alarm`,
`scribl-stage-db-connections-alarm`, `scribl-stage-redis-memory-alarm`,
`scribl-stage-sqs-dlq-alarm`, `scribl-stage-api-error-rate-high`

## Three documented exceptions

**1. Secrets Manager uses slashes, not dashes.**

```
scribl/stage/api
scribl/stage/admin-api/database-url
scribl/stage/ses/smtp-credentials
```

This is deliberate. A slash hierarchy means one IAM statement covers the whole environment:

```
Resource = "arn:aws:secretsmanager:us-east-1:419717495525:secret:scribl/stage/*"
```

With dashes you would need a wildcard that also matches `scribl-stage-something-else`, which is
looser than you want for secrets. The prefix is still `scribl/<environment>/`, so the convention
holds — only the separator differs.

**2. CloudWatch log group paths are dictated by AWS.**

`/aws/eks/scribl-stage-eks/cluster` and `/aws/api-gateway/scribl-stage`. AWS chooses the
`/aws/<service>/` prefix; the part we control still follows the convention.

**3. Terraform state keys are per component, not per resource.**

`stage/10-network.tfstate`, `stage/40-data.tfstate`. See doc 08.

## Renaming is destructive — do it before you build

Most AWS resources cannot be renamed. Terraform handles a name change by **destroying and
recreating**. For an RDS instance or a Cognito user pool that means data loss.

Nothing is deployed yet, so the names above cost you nothing today. Once stage is live, treat
names as immutable. If you must rename something later, the safe route is
`terraform state mv` combined with a snapshot and a maintenance window — not a casual PR.

## Adding a resource later

1. Put it in the right module under `modules/`, naming it `"${var.name_prefix}-<type>"`.
2. Add the type to the table above.
3. If it does not fit an existing component, add a new `stacks/NN-<name>/` directory.
