output "queue_arn" { value = aws_sqs_queue.main.arn }
output "queue_url" { value = aws_sqs_queue.main.id }
output "queue_name" { value = aws_sqs_queue.main.name }
output "dlq_arn" { value = aws_sqs_queue.dlq.arn }
output "alarm_topic_arn" { value = aws_sns_topic.alarms.arn }
