# ---------------------------------------------------------------------------
# Three roles, three blast radii:
#   plan            - read-only, assumable from any branch/PR in the platform repo
#   apply           - read/write, assumable only from main (or a protected
#                     GitHub Environment for prod), used by terraform-apply.yml
#   tenant-onboard  - narrow, assumable only from the pinned reusable
#                     onboarding workflow (via workflow_ref), and only from
#                     app-team repos. It can create/update tenant-scoped
#                     resources (ECR repos, IRSA roles, IAM policies) named
#                     tenant-*; it cannot touch the VPC, EKS control plane, or
#                     any other team's resources.
# ---------------------------------------------------------------------------

locals {
  account_id = data.aws_caller_identity.current.account_id
}

# --- plan -------------------------------------------------------------------

data "aws_iam_policy_document" "plan_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.platform_repo}:*"]
    }
  }
}

resource "aws_iam_role" "plan" {
  name                 = "github-actions-${var.project_name}-plan"
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "plan_permissions" {
  statement {
    sid    = "ReadPlatformResources"
    effect = "Allow"
    actions = [
      "ec2:Describe*",
      "eks:Describe*",
      "eks:List*",
      "rds:Describe*",
      "rds:List*",
      "ecr:Describe*",
      "ecr:List*",
      "ecr:GetLifecyclePolicy",
      "ecr:GetRepositoryPolicy",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:GetOpenIDConnectProvider",
      "iam:ListOpenIDConnectProviders",
      "kms:DescribeKey",
      "kms:ListAliases",
      "logs:Describe*",
      "s3:GetBucket*",
      "s3:ListBucket",
      "sns:GetTopicAttributes",
      "sns:ListTopics",
      "aps:Describe*",
      "aps:List*",
      "grafana:Describe*",
      "grafana:List*",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ReadState"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [for b in aws_s3_bucket.tfstate : b.arn]
  }
  statement {
    sid       = "ReadStateObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = [for b in aws_s3_bucket.tfstate : "${b.arn}/*"]
  }

  statement {
    sid       = "DecryptState"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.tfstate.arn]
  }
}

resource "aws_iam_role_policy" "plan" {
  name   = "plan-permissions"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan_permissions.json
}

# --- apply --------------------------------------------------------------

data "aws_iam_policy_document" "apply_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # main-branch pushes (auto-apply to dev) and any ref while running inside
    # a protected GitHub Environment (prod's required-reviewer gate lives on
    # the Environment, not here - this condition only narrows *which repo*).
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.platform_repo}:ref:refs/heads/main",
        "repo:${var.platform_repo}:environment:dev",
        "repo:${var.platform_repo}:environment:prod",
      ]
    }
  }
}

resource "aws_iam_role" "apply" {
  name                 = "github-actions-${var.project_name}-apply"
  assume_role_policy   = data.aws_iam_policy_document.apply_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "apply_permissions" {
  statement {
    sid    = "ManagePlatformResources"
    effect = "Allow"
    actions = [
      "ec2:*",
      "eks:*",
      "rds:*",
      "ecr:*",
      "logs:*",
      "sns:*",
      "aps:*",
      "grafana:*",
      "elasticloadbalancing:*",
      "autoscaling:*",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid    = "ManagePlatformIAM"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:CreateOpenIDConnectProvider",
      "iam:GetOpenIDConnectProvider",
      "iam:CreateServiceLinkedRole",
      "iam:PassRole",
    ]
    resources = [
      "arn:aws:iam::${local.account_id}:role/${var.project_name}-*",
      "arn:aws:iam::${local.account_id}:role/tenant-*",
      "arn:aws:iam::${local.account_id}:oidc-provider/*",
    ]
  }

  statement {
    sid    = "ManageKMS"
    effect = "Allow"
    actions = [
      "kms:CreateKey",
      "kms:CreateAlias",
      "kms:DeleteAlias",
      "kms:DescribeKey",
      "kms:EnableKeyRotation",
      "kms:GetKeyPolicy",
      "kms:PutKeyPolicy",
      "kms:ScheduleKeyDeletion",
      "kms:TagResource",
      "kms:ListAliases",
      "kms:Decrypt",
      "kms:GenerateDataKey",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ManageState"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket", "s3:DeleteObject"]
    resources = concat([for b in aws_s3_bucket.tfstate : b.arn], [for b in aws_s3_bucket.tfstate : "${b.arn}/*"])
  }
}

resource "aws_iam_role_policy" "apply" {
  name   = "apply-permissions"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply_permissions.json
}

# --- tenant-onboard -----------------------------------------------------
#
# Assumable only by the reusable workflow file itself (workflow_ref), not by
# any workflow an app team writes - so a caller repo can invoke the golden
# path but can't fork the workflow to grant itself more access.

data "aws_iam_policy_document" "tenant_onboard_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for repo in var.app_team_repos : "repo:${repo}:*"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:job_workflow_ref"
      values   = ["${var.platform_repo}/${var.onboarding_workflow_path}@refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "tenant_onboard" {
  name                 = "github-actions-${var.project_name}-tenant-onboard"
  assume_role_policy   = data.aws_iam_policy_document.tenant_onboard_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "tenant_onboard_permissions" {
  # The onboarding workflow only opens a PR against this repo (see
  # .github/workflows/onboard-service.yml) - it never applies Terraform
  # directly. This role exists so the workflow can read enough state to
  # validate the request (e.g. that a namespace name isn't already taken)
  # without needing the broad `apply` role.
  statement {
    sid    = "ReadTenantResources"
    effect = "Allow"
    actions = [
      "ecr:DescribeRepositories",
      "iam:GetRole",
      "iam:ListRoles",
    ]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }
}

resource "aws_iam_role_policy" "tenant_onboard" {
  name   = "tenant-onboard-permissions"
  role   = aws_iam_role.tenant_onboard.id
  policy = data.aws_iam_policy_document.tenant_onboard_permissions.json
}
