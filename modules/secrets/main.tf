###############################################################################
# Terraform creates the secret *containers* with placeholder values. Real
# values are written once, by hand or by a pipeline, and Terraform then ignores
# them - so applies never overwrite what you put there.
###############################################################################
locals {
  # Mirrors the 2026-09-20 dev inventory, section 14.
  app_secrets = {
    "api"                             = "Product API runtime secrets (DATABASE_URL, INTERNAL_JOB_SECRET)"
    "db-proxy/credentials"            = "RDS Proxy's own auth credentials"
    "db/database-url"                 = "DB connection string via the RDS Proxy"
    "migrate/database-url"            = "Migration job DB connection string (direct, bypasses the proxy)"
    "admin-api/idp-client-secret"     = "admin-bff Cognito confidential client secret"
    "admin-api/session-cookie-secret" = "Admin portal session-cookie signing secret"
    "admin-api/origin-verify"         = "CloudFront to admin-origin shared header secret"
    "ses/smtp-credentials"            = "SES SMTP host/port/username/password, written by the email component"
  }
}

resource "aws_secretsmanager_secret" "app" {
  for_each = local.app_secrets

  name                    = "${var.secret_prefix}/${each.key}"
  description             = each.value
  recovery_window_in_days = 7

  tags = merge(var.tags, { Name = "${var.secret_prefix}/${each.key}" })
}

resource "aws_secretsmanager_secret_version" "app_placeholder" {
  # ses/smtp-credentials is populated by the 38-email component, so it gets no
  # placeholder - a placeholder would be overwritten on every email apply.
  for_each = { for k, v in aws_secretsmanager_secret.app : k => v if k != "ses/smtp-credentials" }

  secret_id     = each.value.id
  secret_string = jsonencode({ PLACEHOLDER = "set-me-after-apply" })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# Pre-populate the admin-bff client secret when the identity component has
# already run and passed it in.
resource "aws_secretsmanager_secret_version" "admin_bff_client_secret" {
  count = var.admin_bff_client_secret == "" ? 0 : 1

  secret_id = aws_secretsmanager_secret.app["admin-api/idp-client-secret"].id

  secret_string = jsonencode({
    client_id     = var.admin_bff_client_id
    client_secret = var.admin_bff_client_secret
  })

  depends_on = [aws_secretsmanager_secret_version.app_placeholder]
}

# API Gateway access logs need their log group to exist before the stage does.
resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/api-gateway/${var.name_prefix}"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, { Name = "/aws/api-gateway/${var.name_prefix}" })
}

###############################################################################
# Service-event log groups and the error-rate alarm that dev has (section 19)
###############################################################################
resource "aws_cloudwatch_log_group" "service_events" {
  for_each = toset(["scribl-api", "scribl-admin-api"])

  name              = "/aws/service-events/${each.value}"
  retention_in_days = var.service_event_log_retention_days

  tags = merge(var.tags, {
    Name      = "/aws/service-events/${each.value}"
    Component = "observability"
    Service   = each.value
  })
}

# pino logs at level >= 50 are errors. One metric filter per log group feeds a
# single alarm, matching dev's scribl-api-error-rate-high.
resource "aws_cloudwatch_log_metric_filter" "error_level" {
  for_each = aws_cloudwatch_log_group.service_events

  name           = "${var.name_prefix}-${each.key}-error-level"
  log_group_name = each.value.name
  pattern        = "{ $.level >= 50 }"

  metric_transformation {
    name          = "ErrorLogLines"
    namespace     = "${var.name_prefix}/application"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "api_error_rate" {
  count = var.alarm_topic_arn == "" ? 0 : 1

  alarm_name          = "${var.name_prefix}-api-error-rate-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ErrorLogLines"
  namespace           = "${var.name_prefix}/application"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "An error-level log line was emitted by the product or admin API in the last 5 minutes"
  alarm_actions       = [var.alarm_topic_arn]
  treat_missing_data  = "notBreaching"

  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-api-error-rate-high"
    Component = "observability"
  })

  depends_on = [aws_cloudwatch_log_metric_filter.error_level]
}
