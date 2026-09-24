output "secret_arns" { value = { for k, s in aws_secretsmanager_secret.app : k => s.arn } }
output "secret_names" { value = { for k, s in aws_secretsmanager_secret.app : k => s.name } }
output "api_gateway_log_group_arn" { value = aws_cloudwatch_log_group.api_gateway.arn }
output "api_gateway_log_group_name" { value = aws_cloudwatch_log_group.api_gateway.name }
output "service_event_log_group_names" {
  value = { for k, g in aws_cloudwatch_log_group.service_events : k => g.name }
}
