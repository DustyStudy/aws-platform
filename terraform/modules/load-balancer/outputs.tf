output "arn" {
  value = aws_lb.this.arn
}

output "arn_suffix" {
  value = aws_lb.this.arn_suffix
}

output "dns_name" {
  value = aws_lb.this.dns_name
}

output "zone_id" {
  value = aws_lb.this.zone_id
}

output "security_group_id" {
  description = "ALB security group (null for an NLB). Targets should allow ingress from this."
  value       = try(aws_security_group.this[0].id, null)
}

output "target_group_arns" {
  value = { for k, v in aws_lb_target_group.this : k => v.arn }
}

output "https_listener_arn" {
  description = "Attach path/host routing rules to this listener."
  value       = aws_lb_listener.tls.arn
}
