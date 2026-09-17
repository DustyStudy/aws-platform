package main

import rego.v1

# The tenant-namespace module lets a team set its own ResourceQuota, up to a
# point - a platform-wide ceiling that can't be raised by editing an
# environment's tfvars alone. Raising the ceiling itself means changing this
# file, which goes through the same PR review as everything else, so it
# can't be quietly bypassed by a single onboarding PR.

cpu_limit_ceiling := 16

memory_limit_ceiling_gi := 32

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "kubernetes_resource_quota"
	hard := rc.change.after.spec[0].hard
	cpu := to_number(hard["limits.cpu"])
	cpu > cpu_limit_ceiling
	msg := sprintf("%s requests limits.cpu=%v, above the %v-vCPU platform ceiling - needs a platform-team review", [rc.address, hard["limits.cpu"], cpu_limit_ceiling])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "kubernetes_resource_quota"
	hard := rc.change.after.spec[0].hard
	mem := hard["limits.memory"]
	endswith(mem, "Gi")
	gi := to_number(trim_suffix(mem, "Gi"))
	gi > memory_limit_ceiling_gi
	msg := sprintf("%s requests limits.memory=%v, above the %vGi platform ceiling - needs a platform-team review", [rc.address, mem, memory_limit_ceiling_gi])
}
