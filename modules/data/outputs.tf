output "db_instance_identifier" {
  value = aws_db_instance.this.identifier
}

output "db_endpoint" {
  value = aws_db_instance.this.address
}

output "db_port" {
  value = aws_db_instance.this.port
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "db_master_secret_arn" {
  description = "RDS-managed master credentials secret. Read this to build DATABASE_URL."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "db_proxy_endpoint" {
  value = var.enable_rds_proxy ? aws_db_proxy.this[0].endpoint : null
}

output "db_proxy_arn" {
  value = var.enable_rds_proxy ? aws_db_proxy.this[0].arn : null
}

output "redis_primary_endpoint" {
  value = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "redis_port" {
  value = aws_elasticache_replication_group.this.port
}

output "redis_auth_secret_arn" {
  value = var.redis_auth_token_enabled ? aws_secretsmanager_secret.redis_auth[0].arn : null
}

output "redis_replication_group_id" {
  value = aws_elasticache_replication_group.this.replication_group_id
}
