###############################################################################
# SES domain identity + DKIM
#
# Verification is a DNS exercise. Terraform creates the identity and tells you
# which records to publish; AWS flips the identity to "verified" once it can
# see them. There is no Route 53 hosted zone in this account, so by default
# nothing here blocks on validation.
#
# Deliberately NOT here, matching the dev account:
#   - no custom MAIL FROM domain
#   - no configuration set
#   - no SNS event destination for bounces/complaints
#   - no email identities (domain only)
###############################################################################

locals {
  use_route53 = var.route53_zone_id != ""
}

resource "aws_ses_domain_identity" "this" {
  domain = var.domain
}

resource "aws_ses_domain_dkim" "this" {
  domain = aws_ses_domain_identity.this.domain
}

###############################################################################
# Route 53 records - only created when route53_zone_id is supplied
###############################################################################
resource "aws_route53_record" "verification" {
  count = local.use_route53 ? 1 : 0

  zone_id = var.route53_zone_id
  name    = "_amazonses.${var.domain}"
  type    = "TXT"
  ttl     = 600
  records = [aws_ses_domain_identity.this.verification_token]
}

resource "aws_route53_record" "dkim" {
  count = local.use_route53 ? 3 : 0

  zone_id = var.route53_zone_id
  name    = "${aws_ses_domain_dkim.this.dkim_tokens[count.index]}._domainkey.${var.domain}"
  type    = "CNAME"
  ttl     = 600
  records = ["${aws_ses_domain_dkim.this.dkim_tokens[count.index]}.dkim.amazonses.com"]
}

resource "aws_ses_domain_identity_verification" "this" {
  count = var.wait_for_verification && local.use_route53 ? 1 : 0

  domain     = aws_ses_domain_identity.this.id
  depends_on = [aws_route53_record.verification]
}

###############################################################################
# SMTP credentials
#
# SES SMTP auth is an IAM user whose secret access key is converted into an
# SMTP password by a documented signing algorithm. The AWS provider exposes
# that converted value as `ses_smtp_password_v4`, so Terraform can produce a
# usable credential pair without you touching the console.
#
# This is the one IAM *user* in the whole repo. It is a service credential with
# a single permission (ses:SendRawEmail) and no console access, which is why it
# is the documented exception to the no-IAM-users rule.
###############################################################################
resource "aws_iam_user" "smtp" {
  count = var.create_smtp_user ? 1 : 0

  name = "${var.name_prefix}-ses-smtp-user"
  path = "/service/"

  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-ses-smtp-user"
    Component = "email"
    Purpose   = "ses-smtp-credentials"
  })
}

resource "aws_iam_user_policy" "smtp" {
  count = var.create_smtp_user ? 1 : 0

  name = "ses-send"
  user = aws_iam_user.smtp[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "SendViaSmtp"
      Effect   = "Allow"
      Action   = ["ses:SendRawEmail"]
      Resource = [aws_ses_domain_identity.this.arn]
    }]
  })
}

resource "aws_iam_access_key" "smtp" {
  count = var.create_smtp_user ? 1 : 0
  user  = aws_iam_user.smtp[0].name
}

# The credentials land in Secrets Manager rather than in an output, so they are
# not printed by `terraform output`. They are still in Terraform state - treat
# the state bucket as sensitive.
resource "aws_secretsmanager_secret_version" "smtp" {
  count = var.create_smtp_user && var.smtp_secret_arn != "" ? 1 : 0

  secret_id = var.smtp_secret_arn

  secret_string = jsonencode({
    host     = "email-smtp.${var.region}.amazonaws.com"
    port     = 587
    security = "STARTTLS"
    username = aws_iam_access_key.smtp[0].id
    password = aws_iam_access_key.smtp[0].ses_smtp_password_v4
  })
}
