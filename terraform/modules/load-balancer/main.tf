locals {
  is_alb = var.type == "application"

  default_tg = coalesce(var.default_target_group, sort(keys(var.target_groups))[0])
}

resource "aws_security_group" "this" {
  count = local.is_alb ? 1 : 0

  name_prefix = "${var.name_prefix}-alb-"
  description = "${var.name_prefix} ALB"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name_prefix}-alb" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  for_each = local.is_alb ? toset(var.allowed_ingress_cidrs) : toset([])

  security_group_id = aws_security_group.this[0].id
  description       = "HTTPS"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# Also allow port 80 only so the redirect listener can answer; it never
# forwards anything.
resource "aws_vpc_security_group_ingress_rule" "http_redirect" {
  for_each = local.is_alb ? toset(var.allowed_ingress_cidrs) : toset([])

  security_group_id = aws_security_group.this[0].id
  description       = "HTTP (redirect to HTTPS only)"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

locals {
  egress_pairs = local.is_alb ? {
    for pair in setproduct(keys(var.target_security_groups), keys(var.target_groups)) :
    "${pair[0]}:${pair[1]}" => { sg = var.target_security_groups[pair[0]], tg = pair[1] }
  } : {}
}

resource "aws_vpc_security_group_egress_rule" "to_targets" {
  for_each = local.egress_pairs

  security_group_id            = aws_security_group.this[0].id
  description                  = "To targets (${each.value.tg})"
  referenced_security_group_id = each.value.sg
  ip_protocol                  = "tcp"
  from_port                    = var.target_groups[each.value.tg].port
  to_port                      = var.target_groups[each.value.tg].port
}

resource "aws_lb" "this" {
  name               = "${var.name_prefix}-${local.is_alb ? "alb" : "nlb"}"
  load_balancer_type = var.type
  internal           = var.internal
  subnets            = var.subnet_ids
  security_groups    = local.is_alb ? [aws_security_group.this[0].id] : null

  enable_deletion_protection       = var.deletion_protection
  enable_cross_zone_load_balancing = true

  # ALB-only attributes; the provider ignores them for NLBs.
  idle_timeout               = local.is_alb ? var.idle_timeout : null
  drop_invalid_header_fields = local.is_alb
  desync_mitigation_mode     = local.is_alb ? "strictest" : null
  enable_http2               = local.is_alb ? true : null

  access_logs {
    bucket  = var.access_logs_bucket
    prefix  = var.access_logs_prefix
    enabled = true
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-${local.is_alb ? "alb" : "nlb"}" })
}

resource "aws_lb_target_group" "this" {
  for_each = var.target_groups

  name_prefix = substr(each.key, 0, 6)
  vpc_id      = var.vpc_id
  port        = each.value.port
  protocol    = coalesce(each.value.protocol, local.is_alb ? "HTTP" : "TCP")
  target_type = each.value.target_type

  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = local.is_alb ? each.value.health_check.path : null
    matcher             = local.is_alb ? each.value.health_check.matcher : null
    interval            = each.value.health_check.interval
    healthy_threshold   = each.value.health_check.healthy_threshold
    unhealthy_threshold = each.value.health_check.unhealthy_threshold
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "tls" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = local.is_alb ? "HTTPS" : "TLS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[local.default_tg].arn
  }

  tags = var.tags
}

resource "aws_lb_listener" "http_redirect" {
  count = local.is_alb ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = var.tags
}

resource "aws_wafv2_web_acl_association" "this" {
  count = local.is_alb && var.associate_waf ? 1 : 0

  resource_arn = aws_lb.this.arn
  web_acl_arn  = var.waf_acl_arn
}

# --- Alarms (ALB) ------------------------------------------------------------
# Target 5xx = the app is failing; ELB 5xx = the LB itself is (no healthy
# targets, capacity). They page differently, so they alarm separately.

resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  count = local.is_alb ? 1 : 0

  alarm_name          = "${var.name_prefix}-alb-target-5xx"
  alarm_description   = "Targets behind ${aws_lb.this.name} are returning 5xx. Runbook: ${var.runbook_url}"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = { LoadBalancer = aws_lb.this.arn_suffix }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  threshold           = 10
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions
  tags          = var.tags
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  for_each = var.target_groups

  alarm_name        = "${var.name_prefix}-${local.is_alb ? "alb" : "nlb"}-${each.key}-unhealthy-hosts"
  alarm_description = "Target group ${each.key} has unhealthy targets. Runbook: ${var.runbook_url}"
  namespace         = local.is_alb ? "AWS/ApplicationELB" : "AWS/NetworkELB"
  metric_name       = "UnHealthyHostCount"
  dimensions = {
    LoadBalancer = aws_lb.this.arn_suffix
    TargetGroup  = aws_lb_target_group.this[each.key].arn_suffix
  }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions
  tags          = var.tags
}
