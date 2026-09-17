package main

import rego.v1

# 0.0.0.0/0 ingress is allowed only for the ports a public ALB actually
# needs. Everything else - including a wide-open SSH or a debug port left in
# a security group - fails the plan instead of just getting flagged.

allowed_public_ports := {80, 443}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_vpc_security_group_ingress_rule"
	after := rc.change.after
	after.cidr_ipv4 == "0.0.0.0/0"
	not after.from_port in allowed_public_ports
	msg := sprintf("%s is open to 0.0.0.0/0 on port %v - only 80/443 may be public", [rc.address, after.from_port])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_security_group"
	some ingress in object.get(rc.change.after, "ingress", [])
	"0.0.0.0/0" in object.get(ingress, "cidr_blocks", [])
	not ingress.from_port in allowed_public_ports
	msg := sprintf("%s has an inline ingress rule open to 0.0.0.0/0 on port %v", [rc.address, ingress.from_port])
}
