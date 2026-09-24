# SES: verifying a domain and sending mail

Component: `stacks/38-email`. Module: `modules/ses`.

## What Terraform creates

| Resource | Name | Purpose |
| --- | --- | --- |
| `aws_ses_domain_identity` | your domain | the identity you send from |
| `aws_ses_domain_dkim` | — | generates 3 DKIM signing tokens |
| `aws_ses_domain_mail_from` | `mail.<domain>` | custom bounce domain, so bounces come back to you rather than to `amazonses.com` |
| `aws_sesv2_configuration_set` | `scribl-stage-ses-config-set` | TLS required, reputation metrics on |
| `aws_sesv2_configuration_set_event_destination` | `scribl-stage-ses-bounces` | bounces and complaints go to the SNS alarm topic |
| `aws_ses_email_identity` | optional | a single verified address, useful in the sandbox |
| `aws_route53_record` ×6 | — | only if you set `ses_route53_zone_id` |

The app pod's IAM role (`scribl-stage-api-pod-role`) gets `ses:SendEmail`,
`ses:SendRawEmail`, and `ses:SendTemplatedEmail`, scoped to this domain identity and
configuration set. That wiring is automatic: `50-iam` reads `38-email`'s state.

## Configure it

In `config/main.tf`, the `stage` block:

```hcl
ses_domain              = "stage.scribl.example"   # >>> the domain to verify <<<
ses_mail_from_subdomain = "mail"                   # gives mail.stage.scribl.example
ses_route53_zone_id     = ""                       # see the two paths below
ses_notification_email  = ""                       # optional single sender
enable_ses              = true
```

## Path A — DNS is in Route 53 (Terraform does everything)

Find the zone id:

```bash
aws route53 list-hosted-zones-by-name \
  --query "HostedZones[?Name=='scribl.example.'].Id" --output text
# /hostedzone/Z1234567890ABC  -> use just Z1234567890ABC
```

Set it:

```hcl
ses_route53_zone_id = "Z1234567890ABC"
```

Apply. Terraform publishes the DKIM CNAMEs, the MAIL FROM MX and SPF records, and a starter
DMARC record, then waits for AWS to confirm verification (usually 2–10 minutes, occasionally up
to 45).

```bash
cd stacks/38-email
terraform init -input=false \
  -backend-config=../../envs/stage.backend.hcl \
  -backend-config="key=stage/38-email.tfstate"
terraform apply -var="environment=stage"
```

Note: the dev account has **no** hosted zones, so unless you have added one, you are on Path B.

## Path B — DNS is somewhere else (Cloudflare, GoDaddy, your registrar)

Leave `ses_route53_zone_id = ""`. Terraform creates the identity and hands you the records:

```bash
cd stacks/38-email
terraform apply -var="environment=stage"
terraform output -json dns_records | python3 -m json.tool
```

You get six records, roughly:

| Type | Name | Value |
| --- | --- | --- |
| CNAME | `<token1>._domainkey.stage.scribl.example` | `<token1>.dkim.amazonses.com` |
| CNAME | `<token2>._domainkey.stage.scribl.example` | `<token2>.dkim.amazonses.com` |
| CNAME | `<token3>._domainkey.stage.scribl.example` | `<token3>.dkim.amazonses.com` |
| MX | `mail.stage.scribl.example` | `10 feedback-smtp.us-east-1.amazonses.com` |
| TXT | `mail.stage.scribl.example` | `v=spf1 include:amazonses.com ~all` |
| TXT | `_dmarc.stage.scribl.example` | `v=DMARC1; p=none;` |

Publish all six in your DNS provider. Two gotchas that cost people an afternoon:

- Many DNS UIs **append the zone automatically**. If the zone is `scribl.example`, enter the
  DKIM name as `<token>._domainkey.stage`, not the full name — otherwise you create
  `<token>._domainkey.stage.scribl.example.scribl.example`.
- If DKIM CNAMEs are proxied (Cloudflare's orange cloud), verification fails. Set them to
  DNS-only.

Then watch for verification:

```bash
aws ses get-identity-verification-attributes --identities stage.scribl.example
aws ses get-identity-dkim-attributes --identities stage.scribl.example
```

Wait for `VerificationStatus: Success` and `DkimVerificationStatus: Success`. Nothing in
Terraform needs re-running; AWS flips the status on its own once it can see the records.

## You are in the sandbox until you ask not to be

This is the single most common SES surprise. A brand new account can only send **to addresses
it has already verified**, capped at 200 messages a day. Verifying your sending domain does not
change that.

```bash
aws sesv2 get-account --query '{Sandbox:ProductionAccessEnabled,Quota:SendQuota}'
# ProductionAccessEnabled: false  =>  you are in the sandbox
```

To get out, open a request in the SES console (**Account dashboard → Request production
access**) or via Support. Expect 24–48 hours. They ask what you send, to whom, and how you
handle bounces and unsubscribes — answer specifically, since vague answers get rejected.

While you wait, set `ses_notification_email` to an address you control; Terraform verifies it as
a single identity so you have somewhere to test against.

## Sending from the application

No credentials to manage — the pod assumes `scribl-stage-api-pod-role` via EKS Pod Identity and
the AWS SDK picks it up.

```javascript
import { SESv2Client, SendEmailCommand } from "@aws-sdk/client-sesv2";

const ses = new SESv2Client({ region: process.env.AWS_REGION });

await ses.send(new SendEmailCommand({
  FromEmailAddress: `no-reply@${process.env.SES_DOMAIN}`,
  ConfigurationSetName: process.env.SES_CONFIGURATION_SET,
  Destination: { ToAddresses: [recipient] },
  Content: {
    Simple: {
      Subject: { Data: "Welcome to Scribl" },
      Body: { Html: { Data: html }, Text: { Data: text } },
    },
  },
}));
```

Set these env vars in the Deployment from the component outputs:

```bash
cd stacks/38-email
terraform output -raw ses_domain                  # SES_DOMAIN
terraform output -raw ses_configuration_set_name  # SES_CONFIGURATION_SET
```

Always pass `ConfigurationSetName`. Without it you get no delivery metrics and no bounce
events, which means you find out about a reputation problem when AWS pauses your sending.

## If you need SMTP instead of the API

Some frameworks only speak SMTP. SES SMTP credentials are an IAM user with a derived password,
and IAM users are deliberately out of scope for this repo. Generate them once in the console
(**SES → SMTP settings → Create SMTP credentials**) and store them in the secret Terraform
already created for the purpose:

```bash
aws secretsmanager put-secret-value \
  --secret-id scribl/stage/ses/smtp-credentials \
  --secret-string '{"username":"AKIA...","password":"...","host":"email-smtp.us-east-1.amazonaws.com","port":587}'
```

Prefer the API if you can. It needs no long-lived credential at all.

## Cost

$0.10 per thousand emails, plus $0.12 per GB of attachments. Receiving is free for the first
thousand. For a stage environment this rounds to nothing.

## Turning it off

```hcl
enable_ses = false
```

Then apply `38-email`. Removing the domain identity does not delete your DNS records — clean
those up yourself.
