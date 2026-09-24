# Things in the dev inventory that are deliberately NOT in Terraform

You asked: if adding something would cause errors during `terraform apply`, leave it out and
report it separately. This is that report. Everything below exists in the dev account
(`021914193398`) per the 2026-09-20 audit and is **not** in this repo.

Each entry says why, and what to do instead.

---

## A. Would fail or hang the apply

### A1. SNS APNs platform applications — REMOVED at your request

Dev has `app/APNS/scribl-ios-apns-prod` and `app/APNS_SANDBOX/scribl-ios-apns-dev`.

`aws_sns_platform_application` requires `platform_credential` — an Apple `.p8` signing key plus
key id, team id and bundle id. You said you do not have those, so the resource **and** the
matching IAM grant have been removed from the repo entirely rather than left as dead config.

**Do instead:** create both platform applications in the SNS console when you have the Apple
key. Then add an `sns:CreatePlatformEndpoint` / `sns:Publish` statement to
`modules/iam/main.tf`'s `api_pod` policy, scoped to their ARNs. Roughly ten lines; ask and I
will write it.

### A2. ACM certificates — REMOVED at your request

Previously `stacks/25-certificates` requested Amazon-issued certificates for
`mweb.stage.scribl.co` and `mapi.stage.scribl.co`. The whole component and its module are gone,
and CloudFront no longer references ACM except through one optional ARN you supply.

**Do instead:** ☁️ ACM → Request certificate, **in us-east-1** (CloudFront accepts no other
region), DNS validation. Publish the CNAME ACM gives you. Once ISSUED, paste the ARN into
`cloudfront_certificate_arn` in `config/main.tf`.

### A3. The CloudFront alternate domain, until a certificate exists

`cloudfront_aliases` is already set to `["mweb.stage.scribl.co"]`, but it is only applied when
`cloudfront_certificate_arn` is non-empty.

This gate is not caution, it is a hard AWS constraint: attaching an alternate domain name to a
distribution that uses the default `*.cloudfront.net` certificate fails with
`InvalidViewerCertificate`. An ungated alias would break every apply until the certificate
existed.

### A4. The admin API CloudFront origin and its three behaviours

Written and ready, gated behind `admin_nlb_dns_name`.

The admin NLB (`k8s-scribl-scriblad-cbbeca205c`) is created by Kubernetes when you apply the
admin API's `Service`, not by Terraform. Referencing a DNS name that does not exist yet fails
with `InvalidArgument: The parameter Origin DomainName does not refer to a valid S3 bucket or
custom origin`.

**Do instead:** deploy the admin pod, get the NLB DNS name, set `admin_nlb_dns_name`, apply
`20-edge`. The `/v1/admin/*`, `/admin` and `/admin/*` behaviours appear at the correct
precedences.

### A5. API Gateway VPC Link and routes

Same reason, already covered: `80-api` is gated behind `enable_api_gateway` + `nlb_arn`,
because the product NLB is also Kubernetes-created. See docs/04.

### A6. Client VPN

`90-vpn` needs two imported ACM certificates (`server.domain.tld`, `client1.domain.tld` in
dev). Without them `aws_ec2_client_vpn_endpoint` fails on a missing
`server_certificate_arn`. Disabled by default. See docs/05.

---

## B. Deliberately excluded by your instructions

| Item in dev | Why excluded |
| --- | --- |
| 10 IAM users, 3 groups, `Enforce-MFA-For-IAM-Users`, `ModifyOnly_NoCreateDelete` | You asked to ignore IAM users and groups. Use IAM Identity Center. The CI apply role has an explicit `Deny` on all user/group actions. |
| `AWSSESSendingGroupDoNotRename` group | A group, still excluded. The SMTP **user** is now created (see below) but without a group. |
| SES email identities (`scribl_team@bounteous.com`, four `@bounteous.com` addresses) | You said: domain only, no email identities. Only `stg.scribl.co` is managed. |
| SES custom MAIL FROM domain | Removed at your request. Bounces return via `amazonses.com`, as they do in dev. |
| SES configuration set and bounce/complaint routing to SNS | The dev inventory shows neither, and you asked to add only what dev has. Without a configuration set you get no per-message delivery metrics — worth adding later. |
| `GitHubActions-ECR-Push-Role` (trusts `repo:ScriblOrg/*`) | Org-wide wildcard trust. Replaced by two per-purpose roles with explicit subjects. |

---

## C. Not Terraform's to own

| Item in dev | Why |
| --- | --- |
| Both NLBs and their 4 target groups | Created by the Kubernetes load balancer controller. Terraform would fight it. docs/04. |
| SGs `k8s-traffic-*`, `k8s-scribl-scriblap-*`, `k8s-scribl-scriblad-*` | Same controller. |
| EKS SG `eks-cluster-sg-scribl-dev-eks-*` | Created and managed by EKS itself; exposed as an output. |
| `AmazonEKSAutoClusterRole`, `AmazonEKSAutoNodeRole` | Equivalents are created under our own names (`scribl-stage-eks-cluster-role`, `-node-role`). |
| `AmazonEKSPodIdentityAmazonVPCCNIRole` | EKS Auto Mode manages VPC CNI itself — no addon, no role. This is also why dev's `coredns` addon sits in `UPDATE_FAILED`. |
| ~13 service-linked roles | AWS creates each automatically on first use. |
| `OrganizationAccountAccessRole` | Created by AWS Organizations. |
| CloudFormation stack `AWS-QuickSetup-SSM-*` and its roles | Console scaffolding. |
| `AmazonAPIGatewayPushToCloudWatchLogs` | Account-level API Gateway logging role; set once per account in the console. **You must create this or API Gateway access logs silently do nothing.** See the runbook. |
| Container Insights / RDS / RDSOSMetrics log groups | Created by the services themselves. |
| X-Ray `Default` group and sampling rule | AWS defaults, not creatable. |
| Elastic IP `35.172.189.92` | RDS-managed on the proxy ENI. Our NAT EIPs are the ones to allowlist. |
| Key pair `scribl-dev` | SSM Session Manager needs none. Set `tools_public_key_openssh` if you want one. |

---

## D. Not copied on purpose (dev flaws)

Fixed rather than reproduced. Full list in `docs/03-CHANGES-FROM-DEV.md`. The important ones:

| dev | here |
| --- | --- |
| `scribl-dev-ec2` SG allows 5432 from `0.0.0.0/0`, and RDS is `PubliclyAccessible: true` — the audit's top-priority finding | RDS is private, 5432 only from the VPC CIDR |
| Redis: no transit encryption, no at-rest encryption, no auth token | all three on |
| Tools host root EBS unencrypted | encrypted |
| No ECR lifecycle policy, 46 images accumulated | untagged expire at 7 days, keep newest 30 |
| Only one alarm (API error rate) | that one **plus** RDS CPU / storage / connections, Redis memory, SQS DLQ depth |
| Client VPN connection logging disabled | enabled |
| Mobile Cognito callback points at `d84l1y8p4kdic.cloudfront.net`, a different environment | per-environment variable, no stale default |
| `mapi.dev.scribl.co` cert shows `InUseBy` in account `392220576650` | we issue our own `mapi.stg.scribl.co`; nothing cross-account |
| No REGIONAL WAF | still none — see below |

---

## E-pre. The one IAM user that IS created

`scribl-stage-ses-smtp-user`, path `/service/`, created by `modules/ses`.

SES SMTP authentication has no other form: the username is an IAM access key id and the
password is that key's secret run through a documented v4 signing transform. The AWS provider
exposes the transformed value as `ses_smtp_password_v4`, so Terraform can produce a working
credential pair.

It is a service credential, not a person: one permission (`ses:SendRawEmail` on the domain
identity), no console password, no group, no MFA. The credentials are written to
`scribl/stage/ses/smtp-credentials` rather than to a Terraform output, so `terraform output`
never prints them. They are still in Terraform state — the state bucket is the sensitive thing
to protect.

The CI apply role was updated to permit this: it may manage users and access keys **only** under
`arn:aws:iam::419717495525:user/service/*`, and everything else about human identities stays
explicitly denied.

## E. Known gaps, matching dev, not yet addressed

- **No REGIONAL WAF web ACL.** API Gateway and the NLBs have no WAF. Only the CloudFront-scoped
  ACL exists. Adding one is straightforward if you want it.
- **No secret rotation.** Except the RDS master password, which is RDS-managed and rotatable
  with one API call because we use `manage_master_user_password`.
- **Shield Advanced not subscribed.** $3,000/month; not something to enable by accident.
- **No customer-managed KMS keys.** AWS-managed keys only, same as dev.
