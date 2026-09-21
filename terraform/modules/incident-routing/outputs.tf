output "topic_arns" {
  description = "Map sev1..sev4 -> SNS topic ARN. Pass topic_arns[\"sev2\"] etc. as alarm_actions on any alarm."
  value       = { for k, v in aws_sns_topic.this : k => v.arn }
}

output "pager_dlq_arn" {
  value = aws_sqs_queue.pager_dlq.arn
}
