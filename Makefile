ENV ?= dev
TF   = terraform -chdir=terraform/environments/$(ENV)

.PHONY: fmt validate plan lint policy-test

fmt: ## terraform fmt across the whole repo
	terraform fmt -recursive

validate: ## init + validate the given ENV (default: dev)
	$(TF) init -input=false -backend=false
	$(TF) validate

plan: ## plan the given ENV against real state - requires AWS credentials
	$(TF) init -input=false
	$(TF) plan

lint: ## tflint across the whole repo
	tflint --init
	tflint --recursive --format compact

policy-test: ## run the conftest policy gate against a saved plan
	@test -f terraform/environments/$(ENV)/plan.json || \
		(echo "run 'make plan ENV=$(ENV)' and 'terraform show -json tfplan.binary > plan.json' first" && exit 1)
	conftest test terraform/environments/$(ENV)/plan.json -p policy/conftest
