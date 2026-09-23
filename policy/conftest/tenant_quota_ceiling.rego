package main

import rego.v1

# The tenant-namespace module lets a team set its own ResourceQuota, up to a
# point - a platform-wide ceiling that can't be raised by editing an
# environment's tfvars alone. Raising the ceiling itself means changing this
# file, which goes through the same PR review as everything else, so it
# can't be quietly bypassed by a single onboarding PR.
#
# Fails closed: a quota with no CPU/memory limit at all, or a value in a unit
# this policy can't parse, is denied rather than waved through.

cpu_limit_ceiling := 16

memory_limit_ceiling_gi := 32

quotas contains rc if {
	some rc in input.resource_changes
	rc.type == "kubernetes_resource_quota"
	rc.change.after != null
}

# "4" -> 4, "500m" -> 0.5
cpu_cores(v) := to_number(trim_suffix(v, "m")) / 1000 if endswith(v, "m")

cpu_cores(v) := to_number(v) if regex.match(`^[0-9.]+$`, v)

memory_gi(v) := to_number(trim_suffix(v, "Mi")) / 1024 if endswith(v, "Mi")

memory_gi(v) := to_number(trim_suffix(v, "Gi")) if endswith(v, "Gi")

memory_gi(v) := to_number(trim_suffix(v, "Ti")) * 1024 if endswith(v, "Ti")

deny contains msg if {
	some rc in quotas
	some key in ["limits.cpu", "limits.memory"]
	not rc.change.after.spec[0].hard[key]
	msg := sprintf("%s sets no %s - a tenant quota without it is unlimited", [rc.address, key])
}

deny contains msg if {
	some rc in quotas
	v := rc.change.after.spec[0].hard["limits.cpu"]
	not cpu_cores(v)
	msg := sprintf("%s limits.cpu=%v is not a unit this policy understands (cores or millicores)", [rc.address, v])
}

deny contains msg if {
	some rc in quotas
	v := rc.change.after.spec[0].hard["limits.memory"]
	not memory_gi(v)
	msg := sprintf("%s limits.memory=%v is not a unit this policy understands (Mi, Gi or Ti)", [rc.address, v])
}

deny contains msg if {
	some rc in quotas
	v := rc.change.after.spec[0].hard["limits.cpu"]
	cpu_cores(v) > cpu_limit_ceiling
	msg := sprintf("%s requests limits.cpu=%v, above the %v-vCPU platform ceiling - needs a platform-team review", [rc.address, v, cpu_limit_ceiling])
}

deny contains msg if {
	some rc in quotas
	v := rc.change.after.spec[0].hard["limits.memory"]
	memory_gi(v) > memory_limit_ceiling_gi
	msg := sprintf("%s requests limits.memory=%v, above the %vGi platform ceiling - needs a platform-team review", [rc.address, v, memory_limit_ceiling_gi])
}
