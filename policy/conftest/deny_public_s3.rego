package main

import rego.v1

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_s3_bucket_public_access_block"
	after := rc.change.after
	some field in ["block_public_acls", "block_public_policy", "ignore_public_acls", "restrict_public_buckets"]
	after[field] == false
	msg := sprintf("%s sets %s = false - all four public-access-block settings must be true", [rc.address, field])
}
