# What differs from the dev account

Source: `AWS_RESOURCE_INVENTORY.md`, audit dated 2026-09-14, account `021914193398`.

Three categories: the private-subnet change you asked for, the things skipped on request, and a
handful of dev's own open items that were cheaper to fix in code than to reproduce and remember.

## 1. The private-subnet change

| | dev | stage / prod |
| --- | --- | --- |
| VPC | default VPC `vpc-0a67964a69c5f5aab`, `172.31.0.0/16` | purpose-built VPC, `10.20.0.0/16` (stage) / `10.30.0.0/16` (prod) |
| Subnets | 6, **all public**, one per AZ | 3 private `/20` + 3 public `/24`, across 3 AZs |
| Route tables | 1 main, `0.0.0.0/0` → IGW | 1 public (→ IGW) + 1 private per AZ (→ NAT) |
| NAT Gateway | none | 1 (stage) / 3, one per AZ (prod) |
| Internet Gateway | yes, reachable by everything | yes, but only the public subnets route to it |
| VPC endpoints | 1 (RDS Proxy PrivateLink) | S3 gateway + 12 interface endpoints |
| EKS nodes | public subnets | private subnets only |
| EKS API endpoint | public **and** private | private only (`eks_endpoint_public_access = false`) |
| RDS | `PubliclyAccessible: true` | `publicly_accessible = false`, private subnet group |
| Redis | public subnet, VPC-only SG | private subnets |
| EC2 tools host | public IP `98.89.26.42` | no public IP, SSM Session Manager only |
| Application NLB | internet-facing | **internal** (see docs/04) |
| Public entry points | API Gateway, NLB, EC2, RDS | API Gateway and CloudFront only |

### What "private" actually means for you

A private subnet is one whose route table has no `0.0.0.0/0` route to an internet gateway.
Resources there can still reach *out* (through NAT, for `docker pull`, OS updates, AWS APIs) but
nothing on the internet can start a connection *in*.

Three consequences to plan for:

1. **You cannot reach the database or Redis from your laptop** without a tunnel. Phase 5.1 shows
   the SSM port-forward. This is the intended trade-off.
2. **NAT Gateways cost money** — about $33/month each plus $0.045/GB processed. The 12 interface
   VPC endpoints exist to keep ECR pulls, Secrets Manager reads, and CloudWatch writes off the
   NAT path, which usually saves more than the endpoints cost. Trim the list in
   `modules/network/variables.tf` if you want to spend less.
3. **Inbound traffic has exactly two doors:** CloudFront (static SPA) and API Gateway (the API,
   via VPC Link to the internal NLB). Everything else is unreachable from outside. This is the
   biggest security gain of the change.

## 2. Skipped on request

| Skipped | Consequence |
| --- | --- |
| **ACM certificates** | Client VPN cannot be created — it requires a server certificate. `enable_client_vpn = false` by default. See docs/05 for the 15-minute fix if you want it. CloudFront and API Gateway keep using their AWS-default certificates, exactly as dev does. |
| **IAM users and groups** | The 9 users, `Bounteous-Admin` / `Bounteous-Dev` groups, and the `Enforce-MFA-For-IAM-Users` / `ModifyOnly_NoCreateDelete` policies are not recreated. Use SSO instead — docs/02. The CI apply role has an explicit `Deny` on all user and group actions, so this stays true. |

## 3. Dev's open items, fixed here

The inventory's own "Open items" list. Each was a one-line fix in Terraform, so leaving them
broken would have been a deliberate choice.

| dev finding | fixed how | how to revert |
| --- | --- | --- |
| RDS `PubliclyAccessible: true` | `publicly_accessible = false` | not configurable — this was the point of the exercise |
| RDS deletion protection off | `false` in stage, `true` in prod | `db_deletion_protection` |
| Tools host root EBS volume unencrypted | `encrypted = true` | hardcoded; encryption is free |
| Redis: no transit encryption, no at-rest encryption, no auth token | all three on, token in Secrets Manager | `redis_transit_encryption_enabled`, `redis_auth_token_enabled` in `modules/data/variables.tf` |
| Neither ECR repo has a lifecycle policy | untagged images expire at 7 days, keep newest 30 | `ecr_keep_last_n_images` |
| ECR `scanOnPush: false` | `scan_on_push = true` | `modules/app-services/main.tf` |
| **No CloudWatch alarms anywhere** | 4 alarms + an SNS topic: RDS CPU, RDS free storage, Redis memory, SQS DLQ depth | set `alarm_email` to actually receive them |
| Mobile Cognito callback points at a CloudFront domain from another environment | callback URLs are explicit variables per environment | `cognito_callback_urls_mobile` |
| `GitHubActions-ECR-Push-Role` trusts `repo:ScriblOrg/*` | replaced with per-purpose roles and explicit subjects | `github_allowed_subjects` |
| `coredns` add-on stuck in `UPDATE_FAILED` | not installed — EKS Auto Mode manages CoreDNS, kube-proxy and VPC CNI itself, off-cluster. Installing them as add-ons on an Auto Mode cluster is what produced dev's failure. | `addons` in `modules/eks/variables.tf` |
| Secrets have no rotation | still none, but the RDS master password is now RDS-managed (`manage_master_user_password`), so it can be rotated with one API call and never appears in Terraform state | — |

### One change worth calling out

**Redis now requires TLS and a password.** Dev's Redis accepts plaintext, unauthenticated
connections from anywhere in the VPC. This build turns on transit encryption, at-rest
encryption, and an auth token stored at `scribl/<env>/redis/auth-token`.

Your application's Redis client has to be updated: `rediss://` instead of `redis://`, plus the
password. If that is not ready yet, set both flags to `false` in
`modules/data/variables.tf`, apply, and turn them on when the app is ready. Changing them later
**replaces the cache cluster** — fine for a cache, but it is a brief outage.

## 3b. Added, not present in dev at all

| Added | Why |
| --- | --- |
| **SES** domain identity, DKIM, custom MAIL FROM, configuration set | dev has no SES at all. See docs/09. |
| SES bounce/complaint events routed to SNS | so a reputation problem surfaces before AWS pauses sending |
| `scribl/<env>/ses/smtp-credentials` secret | a place for SMTP credentials if the app needs SMTP |
| 13 independent Terraform states | dev is console-built; this gives per-component pipeline runs. See docs/08. |
| Consistent `scribl-<env>-<type>` naming | dev mixes `scribl-mobile-app` (no env) with `scribl-dev-db`. See docs/07. |
| `scribl-stage-db-connections-alarm` | catches connection leaks, which RDS Proxy can mask |

## 4. Deliberately not recreated

| dev resource | why not |
| --- | --- |
| CloudFormation stack `AWS-QuickSetup-SSM-LocalDeploymentRolesStack` | AWS console scaffolding, not application infrastructure |
| `AWS-QuickSetup-SSM-*` roles, `AWSSystemsManagerDefaultEC2InstanceManagementRole` | same |
| `OrganizationAccountAccessRole` | created automatically by AWS Organizations when the account is created |
| ~12 service-linked roles | AWS creates each one automatically the first time the service is used |
| Elastic IP `35.172.189.92` | that was RDS-managed on the proxy's ENI. The new EIPs are the NAT Gateways', and they are the addresses to give third parties for allowlisting: `terraform output nat_gateway_public_ips` |
| Key pair `scribl-dev` | SSM Session Manager needs no SSH key. Set `tools_public_key_openssh` if you want one anyway. |
| NLB `k8s-scribl-scriblap-*` and its target group | Kubernetes creates these, not Terraform. See docs/04. |
| Route 53 | dev has no hosted zones, so there is nothing to copy |
| Lambda | dev has none; the admin backend is an EKS pod |
| SNS topics | dev has none. This repo adds one, for alarms. |
| Customer-managed KMS keys | dev uses only AWS-managed keys, and so does this. Switching to CMKs is a defensible upgrade but was not part of the ask. |
