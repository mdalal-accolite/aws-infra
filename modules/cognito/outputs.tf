output "mobile_pool_id" { value = aws_cognito_user_pool.mobile.id }
output "mobile_pool_arn" { value = aws_cognito_user_pool.mobile.arn }
output "mobile_client_id" { value = aws_cognito_user_pool_client.mobile.id }
output "admin_pool_id" { value = aws_cognito_user_pool.admin.id }
output "admin_pool_arn" { value = aws_cognito_user_pool.admin.arn }
output "admin_spa_client_id" { value = aws_cognito_user_pool_client.admin_spa.id }
output "admin_bff_client_id" { value = aws_cognito_user_pool_client.admin_bff.id }
output "admin_bff_client_secret" {
  value     = aws_cognito_user_pool_client.admin_bff.client_secret
  sensitive = true
}
output "admin_domain" { value = aws_cognito_user_pool_domain.admin.domain }
output "pool_arns" {
  value = [aws_cognito_user_pool.mobile.arn, aws_cognito_user_pool.admin.arn]
}
