resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name_prefix}-${var.queue_name}-dlq"
  message_retention_seconds = var.retention_seconds
  sqs_managed_sse_enabled   = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-${var.queue_name}-dlq", Component = "messaging", Service = "sqs", Purpose = "dead-letter" })
}

resource "aws_sqs_queue" "main" {
  name                       = "${var.name_prefix}-${var.queue_name}"
  message_retention_seconds  = var.retention_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = merge(var.tags, { Name = "${var.name_prefix}-${var.queue_name}", Component = "messaging", Service = "sqs" })
}

resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.main.arn]
  })
}

###############################################################################
# Central alarm topic for the whole environment. Lives here because messaging
# is the earliest component that every other component can depend on.
###############################################################################
resource "aws_sns_topic" "alarms" {
  name = "${var.name_prefix}-cloudwatch-alarms"
  tags = merge(var.tags, { Name = "${var.name_prefix}-cloudwatch-alarms" })
}

resource "aws_sns_topic_subscription" "alarms_email" {
  count = var.alarm_email == "" ? 0 : 1

  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  alarm_name          = "${var.name_prefix}-sqs-dlq-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "Messages are landing in the dead-letter queue"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"

  dimensions = { QueueName = aws_sqs_queue.dlq.name }
  tags       = merge(var.tags, { Name = "${var.name_prefix}-sqs-dlq-alarm" })
}
