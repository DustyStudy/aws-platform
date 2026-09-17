package main

import rego.v1

# Every cost/ownership-relevant resource must carry the platform's baseline
# tags. `default_tags` on the AWS provider covers most of this already -
# this gate exists to catch the resources that opt out of it (data sources,
# or a future resource block someone writes with `tags = {}` explicitly).

required_tags := {"Project", "Environment", "ManagedBy"}

taggable_types := {
	"aws_vpc", "aws_subnet", "aws_eks_cluster", "aws_eks_node_group",
	"aws_ecr_repository", "aws_iam_role", "aws_kms_key", "aws_sns_topic",
	"aws_cloudwatch_log_group", "aws_s3_bucket", "aws_prometheus_workspace",
	"aws_grafana_workspace", "aws_nat_gateway",
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type in taggable_types
	not _is_delete(rc)
	tags := object.get(rc.change.after, "tags_all", {})
	missing := required_tags - {t | some t in object.keys(tags)}
	count(missing) > 0
	msg := sprintf("%s is missing required tags: %v", [rc.address, missing])
}

_is_delete(rc) if rc.change.actions == ["delete"]
