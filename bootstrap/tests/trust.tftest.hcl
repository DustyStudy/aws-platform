# Mocked-provider tests for the three GitHub OIDC trust policies. No AWS account.
#
# GitHub emits the OIDC `sub` as repo:OWNER@OWNER_ID/REPO@REPO_ID:<suffix> for
# repositories with use_immutable_subject (true for recently created repos). A
# trust condition written for the classic repo:OWNER/REPO:<suffix> form never
# matches, so none of the CI roles could ever be assumed - and nothing errors.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
}

mock_provider "tls" {
  mock_data "tls_certificate" {
    defaults = {
      certificates = [{ sha1_fingerprint = "6938fd4d98bab03faadb97b34396831e3780aea1" }]
    }
  }
}

variables {
  platform_repo    = "acme/aws-platform"
  github_owner_id  = "1001"
  platform_repo_id = "2002"
  app_team_repos   = ["acme/*"]
}

run "plan_role_trusts_the_immutable_subject" {
  command = plan

  assert {
    condition = toset(one([
      for c in data.aws_iam_policy_document.plan_trust.statement[0].condition :
      c if c.variable == "token.actions.githubusercontent.com:sub"
    ]).values) == toset(["repo:acme@1001/aws-platform@2002:*"])
    error_message = "plan role must trust repo:acme@1001/aws-platform@2002:* (GitHub's immutable subject), with exact IDs."
  }
}

run "apply_role_trusts_only_main_and_its_environments" {
  command = plan

  assert {
    condition = toset(one([
      for c in data.aws_iam_policy_document.apply_trust.statement[0].condition :
      c if c.variable == "token.actions.githubusercontent.com:sub"
      ]).values) == toset([
      "repo:acme@1001/aws-platform@2002:ref:refs/heads/main",
      "repo:acme@1001/aws-platform@2002:environment:dev",
      "repo:acme@1001/aws-platform@2002:environment:prod",
    ])
    error_message = "apply role must trust exactly main + the dev/prod environments, in immutable form."
  }
}

run "tenant_onboard_role_pins_the_owner_id" {
  command = plan

  assert {
    condition = toset(one([
      for c in data.aws_iam_policy_document.tenant_onboard_trust.statement[0].condition :
      c if c.variable == "token.actions.githubusercontent.com:sub"
    ]).values) == toset(["repo:acme@1001/*@*:*"])
    error_message = "app-team repos are matched by owner ID (their repo IDs aren't known here); the job_workflow_ref condition is what narrows them."
  }
}

run "no_wildcard_owner_or_repo_id_for_the_platform_repo" {
  command = plan

  assert {
    condition = alltrue([
      for c in data.aws_iam_policy_document.plan_trust.statement[0].condition :
      c.variable != "token.actions.githubusercontent.com:sub" || !anytrue([for v in c.values : strcontains(v, "@*")])
    ])
    error_message = "The platform repo's IDs must be exact, never a wildcard."
  }
}

run "classic_format_is_still_available" {
  command = plan

  variables {
    github_subject_format = "classic"
    github_owner_id       = ""
    platform_repo_id      = ""
  }

  assert {
    condition = toset(one([
      for c in data.aws_iam_policy_document.plan_trust.statement[0].condition :
      c if c.variable == "token.actions.githubusercontent.com:sub"
    ]).values) == toset(["repo:acme/aws-platform:*"])
    error_message = "classic mode should keep the repo:owner/repo:<suffix> form."
  }
}

run "immutable_format_requires_both_ids" {
  command = plan

  variables {
    platform_repo_id = ""
  }

  expect_failures = [var.github_subject_format]
}

run "rejects_non_numeric_ids" {
  command = plan

  variables {
    github_owner_id = "acme"
  }

  expect_failures = [var.github_owner_id]
}

run "rejects_app_repos_owned_by_someone_else_under_immutable" {
  command = plan

  variables {
    app_team_repos = ["someone-else/app"]
  }

  expect_failures = [var.app_team_repos]
}
