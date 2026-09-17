output "amp_workspace_id" {
  value = aws_prometheus_workspace.this.id
}

output "amp_workspace_endpoint" {
  value = aws_prometheus_workspace.this.prometheus_endpoint
}

output "grafana_workspace_endpoint" {
  value = var.create_grafana_workspace ? aws_grafana_workspace.this[0].endpoint : null
}

output "sns_topic_arn" {
  value = aws_sns_topic.platform_alerts.arn
}
