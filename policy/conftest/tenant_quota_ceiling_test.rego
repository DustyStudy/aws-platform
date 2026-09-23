package main

import rego.v1

quota(hard) := {"resource_changes": [{
	"address": "module.tenant[\"t\"].kubernetes_resource_quota.this",
	"type": "kubernetes_resource_quota",
	"change": {"after": {"spec": [{"hard": hard}]}},
}]}

test_within_ceiling_allowed if {
	count(deny) == 0 with input as quota({"limits.cpu": "4", "limits.memory": "8Gi"})
}

test_millicores_and_mebibytes_allowed if {
	count(deny) == 0 with input as quota({"limits.cpu": "1500m", "limits.memory": "512Mi"})
}

test_cpu_above_ceiling_denied if {
	count(deny) == 1 with input as quota({"limits.cpu": "32", "limits.memory": "8Gi"})
}

test_millicores_above_ceiling_denied if {
	count(deny) == 1 with input as quota({"limits.cpu": "20000m", "limits.memory": "8Gi"})
}

test_memory_in_ti_above_ceiling_denied if {
	count(deny) == 1 with input as quota({"limits.cpu": "4", "limits.memory": "1Ti"})
}

# The live failure this policy used to miss: limits silently dropped as null.
test_missing_limits_denied if {
	count(deny) == 2 with input as quota({"pods": "20"})
}

test_unknown_unit_denied if {
	count(deny) == 1 with input as quota({"limits.cpu": "4", "limits.memory": "8G"})
}
