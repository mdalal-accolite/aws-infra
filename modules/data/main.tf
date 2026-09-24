###############################################################################
# RDS PostgreSQL
###############################################################################
resource "aws_db_subnet_group" "this" {
  name        = "${var.name_prefix}-db-subnets"
  description = "Private subnets for ${var.name_prefix} RDS"
  subnet_ids  = var.private_subnet_ids

  tags = merge(var.tags, { Name = "${var.name_prefix}-db-subnets" })
}

resource "aws_db_parameter_group" "this" {
  name        = "${var.name_prefix}-db-pg"
  family      = var.postgres_parameter_group_family
  description = "Parameter group for ${var.name_prefix} PostgreSQL"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name         = "log_min_duration_statement"
    value        = "1000"
    apply_method = "immediate"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-db-pg" })
}

# Enhanced Monitoring role (equivalent of dev's rds-monitoring-role)
resource "aws_iam_role" "rds_monitoring" {
  name = "rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_db_instance" "this" {
  identifier = "${var.name_prefix}-db"

  engine                     = "postgres"
  engine_version             = var.postgres_engine_version
  auto_minor_version_upgrade = true
  instance_class             = var.db_instance_class
  parameter_group_name       = aws_db_parameter_group.this.name

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true # uses the AWS-managed key alias/aws/rds

  db_name  = var.db_name
  username = var.db_master_username

  # RDS creates and rotates the master password in Secrets Manager itself, so
  # the password never lands in Terraform state.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = var.db_security_group_ids
  publicly_accessible    = false # <-- the key difference from the dev account
  multi_az               = var.db_multi_az
  port                   = 5432

  backup_retention_period = var.db_backup_retention_days
  backup_window           = "07:00-08:00"
  maintenance_window      = "sun:08:30-sun:09:30"
  copy_tags_to_snapshot   = true

  deletion_protection      = var.db_deletion_protection
  skip_final_snapshot      = var.db_skip_final_snapshot
  final_snapshot_identifier = var.db_skip_final_snapshot ? null : "${var.name_prefix}-db-final"

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  apply_immediately = true

  tags = merge(var.tags, {
    Name               = "${var.name_prefix}-db"
    Component          = "data"
    Service            = "rds-postgres"
    Tier               = "private"
    DataClassification = "confidential"
    Backup             = "required"
  })

  lifecycle {
    # RDS bumps the minor version during maintenance windows; don't fight it.
    ignore_changes = [engine_version]
  }
}

###############################################################################
# RDS Proxy
###############################################################################
resource "aws_iam_role" "db_proxy" {
  count = var.enable_rds_proxy ? 1 : 0
  name  = "${var.name_prefix}-db-proxy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "db_proxy" {
  count = var.enable_rds_proxy ? 1 : 0
  name  = "read-db-credentials"
  role  = aws_iam_role.db_proxy[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [aws_db_instance.this.master_user_secret[0].secret_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = "*"
        Condition = {
          StringEquals = { "kms:ViaService" = "secretsmanager.${data.aws_region.current.region}.amazonaws.com" }
        }
      }
    ]
  })
}

data "aws_region" "current" {}

resource "aws_db_proxy" "this" {
  count = var.enable_rds_proxy ? 1 : 0

  name                   = "${var.name_prefix}-db-proxy"
  engine_family          = "POSTGRESQL"
  role_arn               = aws_iam_role.db_proxy[0].arn
  vpc_subnet_ids         = var.private_subnet_ids
  vpc_security_group_ids = var.db_proxy_security_group_ids
  require_tls            = true
  idle_client_timeout    = 1800
  debug_logging          = false

  auth {
    auth_scheme = "SECRETS"
    iam_auth    = "DISABLED"
    secret_arn  = aws_db_instance.this.master_user_secret[0].secret_arn
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-db-proxy" })
}

resource "aws_db_proxy_default_target_group" "this" {
  count         = var.enable_rds_proxy ? 1 : 0
  db_proxy_name = aws_db_proxy.this[0].name

  connection_pool_config {
    connection_borrow_timeout    = 120
    max_connections_percent      = 90
    max_idle_connections_percent = 50
  }
}

resource "aws_db_proxy_target" "this" {
  count = var.enable_rds_proxy ? 1 : 0

  db_proxy_name          = aws_db_proxy.this[0].name
  target_group_name      = aws_db_proxy_default_target_group.this[0].name
  db_instance_identifier = aws_db_instance.this.identifier
}

###############################################################################
# ElastiCache Redis
###############################################################################
resource "aws_elasticache_subnet_group" "this" {
  name        = "${var.name_prefix}-redis-subnets"
  description = "Private subnets for ${var.name_prefix} Redis"
  subnet_ids  = var.private_subnet_ids

  tags = merge(var.tags, { Name = "${var.name_prefix}-redis-subnets" })
}

resource "random_password" "redis_auth" {
  count   = var.redis_auth_token_enabled ? 1 : 0
  length  = 48
  special = false # ElastiCache auth tokens must be alphanumeric
}

resource "aws_secretsmanager_secret" "redis_auth" {
  count       = var.redis_auth_token_enabled ? 1 : 0
  name        = "${replace(var.name_prefix, "-", "/")}/redis/auth-token"
  description = "ElastiCache Redis AUTH token for ${var.name_prefix}"

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "redis_auth" {
  count         = var.redis_auth_token_enabled ? 1 : 0
  secret_id     = aws_secretsmanager_secret.redis_auth[0].id
  secret_string = random_password.redis_auth[0].result
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.name_prefix}-redis"
  description          = "Redis cache for ${var.name_prefix}"

  engine         = "redis"
  engine_version = var.redis_engine_version
  node_type      = var.redis_node_type

  num_cache_clusters         = var.redis_num_nodes
  automatic_failover_enabled = var.redis_num_nodes > 1
  multi_az_enabled           = var.redis_num_nodes > 1

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = var.redis_security_group_ids
  port               = 6379

  at_rest_encryption_enabled = true
  transit_encryption_enabled = var.redis_transit_encryption_enabled
  auth_token                 = var.redis_auth_token_enabled ? random_password.redis_auth[0].result : null

  maintenance_window       = "sun:10:00-sun:11:00"
  snapshot_retention_limit = 1
  apply_immediately        = true

  tags = merge(var.tags, {
    Name               = "${var.name_prefix}-redis"
    Component          = "data"
    Service            = "elasticache-redis"
    Tier               = "private"
    DataClassification = "internal"
  })

  lifecycle {
    ignore_changes = [engine_version]
  }
}

###############################################################################
# Alarms (the dev account has none at all)
###############################################################################
resource "aws_cloudwatch_metric_alarm" "db_cpu" {
  count = var.alarm_topic_arn == "" ? 0 : 1

  alarm_name          = "${var.name_prefix}-db-cpu-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS CPU above 80% for 15 minutes"
  alarm_actions       = [var.alarm_topic_arn]
  ok_actions          = [var.alarm_topic_arn]
  treat_missing_data  = "notBreaching"

  dimensions = { DBInstanceIdentifier = aws_db_instance.this.identifier }
  tags       = merge(var.tags, { Name = "${var.name_prefix}-db-cpu-alarm" })
}

resource "aws_cloudwatch_metric_alarm" "db_storage" {
  count = var.alarm_topic_arn == "" ? 0 : 1

  alarm_name          = "${var.name_prefix}-db-storage-alarm"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 10737418240 # 10 GiB
  alarm_description   = "Less than 10 GiB free storage on RDS"
  alarm_actions       = [var.alarm_topic_arn]
  treat_missing_data  = "notBreaching"

  dimensions = { DBInstanceIdentifier = aws_db_instance.this.identifier }
  tags       = merge(var.tags, { Name = "${var.name_prefix}-db-storage-alarm" })
}

resource "aws_cloudwatch_metric_alarm" "db_connections" {
  count = var.alarm_topic_arn == "" ? 0 : 1

  alarm_name          = "${var.name_prefix}-db-connections-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 400
  alarm_description   = "Unusually high connection count - check for a connection leak"
  alarm_actions       = [var.alarm_topic_arn]
  treat_missing_data  = "notBreaching"

  dimensions = { DBInstanceIdentifier = aws_db_instance.this.identifier }
  tags       = merge(var.tags, { Name = "${var.name_prefix}-db-connections-alarm" })
}

resource "aws_cloudwatch_metric_alarm" "redis_memory" {
  count = var.alarm_topic_arn == "" ? 0 : 1

  alarm_name          = "${var.name_prefix}-redis-memory-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "DatabaseMemoryUsagePercentage"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Redis memory usage above 80%"
  alarm_actions       = [var.alarm_topic_arn]
  treat_missing_data  = "notBreaching"

  dimensions = { ReplicationGroupId = aws_elasticache_replication_group.this.replication_group_id }
  tags       = merge(var.tags, { Name = "${var.name_prefix}-redis-memory-alarm" })
}
