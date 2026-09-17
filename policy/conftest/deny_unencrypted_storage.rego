package main

import rego.v1

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_ecr_repository"
	enc := object.get(rc.change.after, "encryption_configuration", [])
	count(enc) == 0
	msg := sprintf("%s must set encryption_configuration (KMS)", [rc.address])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_ecr_repository"
	some cfg in rc.change.after.encryption_configuration
	cfg.encryption_type != "KMS"
	msg := sprintf("%s uses %q encryption - only KMS is allowed", [rc.address, cfg.encryption_type])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_s3_bucket_server_side_encryption_configuration"
	some rule in rc.change.after.rule
	default_enc := rule.apply_server_side_encryption_by_default[0]
	default_enc.sse_algorithm != "aws:kms"
	msg := sprintf("%s must use aws:kms encryption, not %q", [rc.address, default_enc.sse_algorithm])
}
