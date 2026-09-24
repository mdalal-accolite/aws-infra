output "domain" { value = aws_ses_domain_identity.this.domain }
output "domain_identity_arn" { value = aws_ses_domain_identity.this.arn }
output "dkim_tokens" { value = aws_ses_domain_dkim.this.dkim_tokens }
output "verification_token" { value = aws_ses_domain_identity.this.verification_token }

output "route53_managed" {
  description = "true = Terraform published the DNS records; false = you must publish them yourself."
  value       = local.use_route53
}

output "smtp_username" {
  description = "SMTP username. The password is in Secrets Manager, never in an output."
  value       = var.create_smtp_user ? aws_iam_access_key.smtp[0].id : null
}

output "smtp_endpoint" {
  value = "email-smtp.${var.region}.amazonaws.com:587"
}

# The records to publish. Read with:
#   terraform output -json dns_records | python3 -m json.tool
output "dns_records" {
  description = "DNS records required to verify the domain and enable DKIM."
  value = concat(
    [{
      type  = "TXT"
      name  = "_amazonses.${var.domain}"
      value = aws_ses_domain_identity.this.verification_token
      ttl   = 600
      note  = "Domain ownership verification"
    }],
    [for t in aws_ses_domain_dkim.this.dkim_tokens : {
      type  = "CNAME"
      name  = "${t}._domainkey.${var.domain}"
      value = "${t}.dkim.amazonses.com"
      ttl   = 600
      note  = "DKIM signing key"
    }]
  )
}
