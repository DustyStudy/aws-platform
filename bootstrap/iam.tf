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

locals {
  platform_owner = split("/", var.platform_repo)[0]
  platform_name  = split("/", var.platform_repo)[1]

  # The `sub` claim prefix GitHub puts in the token for the platform repo. The
  # immutable form pins exact numeric owner/repo IDs (see github_subject_format).
  platform_subject_prefix = (
    var.github_subject_format == "immutable"
    ? "repo:${local.platform_owner}@${var.github_owner_id}/${local.platform_name}@${var.platform_repo_id}"
    : "repo:${var.platform_repo}"
  )

  # App-team repos: their numeric repo IDs aren't known here, so the immutable
  # form pins the OWNER ID and wildcards the repo ID. That is safe because the
  # tenant-onboard trust also requires job_workflow_ref to be the platform's own
  # onboarding workflow on main - that condition is what narrows who can call it.
  app_team_subject_patterns = [
    for repo in var.app_team_repos :
    var.github_subject_format == "immutable"
    ? "repo:${split("/", repo)[0]}@${var.github_owner_id}/${split("/", repo)[1]}@*:*"
    : "repo:${repo}:*"
  ]
}

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
      values   = ["${local.platform_subject_prefix}:*"]
    }
  }
}

resource "aws_iam_role" "plan" {
  name                 = "github-actions-${var.project_name}-plan"
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600
}

# checkov:skip=CKV_AWS_355: every action below is a read-only Describe*/List*/
# Get* call - AWS defines these as "*"-only actions with no resource-level
# ARN scoping, so a narrower Resource wouldn't change what this role can do.
# checkov:skip=CKV_AWS_356: same - read-only APIs, not "restrictable" in AWS's
# own IAM reference despite the check's default assumption.
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
      "iam:GetInstanceProfile",
      "kms:DescribeKey",
      "kms:ListAliases",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:ListResourceTags",
      "logs:Describe*",
      "logs:ListTagsForResource",
      "logs:ListTagsLogGroup",
      "s3:GetBucket*",
      "s3:ListBucket",
      "sns:GetTopicAttributes",
      "sns:GetSubscriptionAttributes",
      "sns:ListTopics",
      "sns:ListTagsForResource",
      "sqs:GetQueueAttributes",
      "sqs:ListQueueTags",
      "events:Describe*",
      "events:List*",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:ListTagsForResource",
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

  # terraform plan takes the native S3 state lock (use_lockfile = true), which
  # writes and deletes a <key>.tflock object. Only lock objects - the plan role
  # still can't write the state itself.
  statement {
    sid       = "StateLock"
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = [for b in aws_s3_bucket.tfstate : "${b.arn}/*.tflock"]
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
        "${local.platform_subject_prefix}:ref:refs/heads/main",
        "${local.platform_subject_prefix}:environment:dev",
        "${local.platform_subject_prefix}:environment:prod",
      ]
    }
  }
}

resource "aws_iam_role" "apply" {
  name                 = "github-actions-${var.project_name}-apply"
  assume_role_policy   = data.aws_iam_policy_document.apply_trust.json
  max_session_duration = 3600
}

# checkov:skip=CKV_AWS_356: the create/update actions below (ec2:CreateVpc,
# eks:CreateCluster, ...) don't take a resource ARN as input - the resource
# doesn't exist yet - so IAM requires "*" for them regardless of scoping
# intent. What IS scoped: region (condition below), the IAM/KMS/S3
# statements further down (role-name-prefix and bucket-ARN scoped), and the
# trust policy itself (only this repo's main branch / protected
# Environments can assume this role at all - see apply_trust above).
# checkov:skip=CKV_AWS_111: same reasoning - these are resource-creation
# writes, not unconstrained writes to arbitrary existing resources.
# checkov:skip=CKV_AWS_108: no data-plane/exfiltration-capable actions here
# (no s3:GetObject-on-*, no secretsmanager reads) - only control-plane
# create/manage actions for the platform's own infrastructure.
data "aws_iam_policy_document" "apply_permissions" {
  statement {
    sid    = "ManagePlatformResources"
    effect = "Allow"
    actions = [
      # VPC: subnets, routing, NAT, security groups, flow logs
      "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:ModifyVpcAttribute",
      "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:ModifySubnetAttribute",
      "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway", "ec2:AttachInternetGateway", "ec2:DetachInternetGateway",
      "ec2:AllocateAddress", "ec2:ReleaseAddress", "ec2:AssociateAddress", "ec2:DisassociateAddress",
      "ec2:CreateNatGateway", "ec2:DeleteNatGateway",
      "ec2:CreateRouteTable", "ec2:DeleteRouteTable", "ec2:CreateRoute", "ec2:DeleteRoute", "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable",
      "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupEgress", "ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress", "ec2:RevokeSecurityGroupIngress",
      "ec2:CreateFlowLogs", "ec2:DeleteFlowLogs",
      "ec2:CreateTags", "ec2:DeleteTags",
      "ec2:Describe*",
      # EKS: cluster, node groups, access entries
      "eks:CreateCluster", "eks:DeleteCluster", "eks:UpdateClusterConfig", "eks:UpdateClusterVersion",
      "eks:CreateNodegroup", "eks:DeleteNodegroup", "eks:UpdateNodegroupConfig", "eks:UpdateNodegroupVersion",
      "eks:CreateAccessEntry", "eks:DeleteAccessEntry", "eks:AssociateAccessPolicy", "eks:DisassociateAccessPolicy",
      "eks:CreateAddon", "eks:DeleteAddon", "eks:UpdateAddon", "eks:UpdateAccessEntry",
      "eks:TagResource", "eks:UntagResource",
      "eks:Describe*", "eks:List*",
      # ECR: tenant repositories
      "ecr:CreateRepository", "ecr:DeleteRepository", "ecr:PutLifecyclePolicy", "ecr:DeleteLifecyclePolicy", "ecr:PutImageScanningConfiguration",
      "ecr:GetLifecyclePolicy", "ecr:ListTagsForResource", "ecr:TagResource", "ecr:UntagResource", "ecr:Describe*",
      # Karpenter's interruption-handling plumbing
      "sqs:CreateQueue", "sqs:DeleteQueue", "sqs:SetQueueAttributes", "sqs:TagQueue", "sqs:UntagQueue",
      "sqs:GetQueueAttributes", "sqs:GetQueueUrl", "sqs:ListQueueTags",
      "events:PutRule", "events:DeleteRule", "events:PutTargets", "events:RemoveTargets", "events:DescribeRule",
      "events:ListTargetsByRule", "events:ListTagsForResource", "events:TagResource", "events:UntagResource",
      # Logs: log groups + the metric filters observability defines
      "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy", "logs:DeleteRetentionPolicy",
      "logs:AssociateKmsKey", "logs:DisassociateKmsKey",
      "logs:TagResource", "logs:UntagResource", "logs:TagLogGroup", "logs:ListTagsForResource", "logs:ListTagsLogGroup",
      "logs:PutMetricFilter", "logs:DeleteMetricFilter",
      "logs:Describe*",
      # AMP's logging_configuration delivers through CloudWatch Logs vended logs
      "logs:CreateLogDelivery", "logs:GetLogDelivery", "logs:UpdateLogDelivery", "logs:DeleteLogDelivery", "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      # Alerting + cross-service observability
      "sns:CreateTopic", "sns:DeleteTopic", "sns:SetTopicAttributes", "sns:GetTopicAttributes", "sns:Subscribe", "sns:Unsubscribe",
      "sns:GetSubscriptionAttributes", "sns:SetSubscriptionAttributes", "sns:TagResource", "sns:UntagResource", "sns:ListTagsForResource",
      "cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms", "cloudwatch:DescribeAlarms",
      "cloudwatch:ListTagsForResource", "cloudwatch:TagResource", "cloudwatch:UntagResource",
      "aps:CreateWorkspace", "aps:DeleteWorkspace", "aps:UpdateWorkspaceAlias", "aps:TagResource", "aps:UntagResource", "aps:ListTagsForResource",
      "aps:CreateScraper", "aps:DeleteScraper", "aps:UpdateScraper", "aps:ListScrapers",
      "aps:CreateLoggingConfiguration", "aps:UpdateLoggingConfiguration", "aps:DeleteLoggingConfiguration", "aps:Describe*",
      "grafana:CreateWorkspace", "grafana:DeleteWorkspace", "grafana:UpdateWorkspace", "grafana:UpdateWorkspaceConfiguration",
      "grafana:TagResource", "grafana:UntagResource", "grafana:ListTagsForResource", "grafana:Describe*",
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
      "iam:ListInstanceProfilesForRole",
      "iam:CreateOpenIDConnectProvider",
      "iam:GetOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:TagOpenIDConnectProvider",
      "iam:UntagOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:PassRole",
    ]
    resources = [
      # Environment name_prefixes ("platform-dev-*"/"platform-prod-*" -
      # see terraform/environments/*/main.tf's locals.name_prefix) and
      # per-service tenant roles ("tenant-<team>-<service>").
      "arn:aws:iam::${local.account_id}:role/platform-*",
      "arn:aws:iam::${local.account_id}:role/tenant-*",
      "arn:aws:iam::${local.account_id}:oidc-provider/*",
    ]
  }

  # A fresh account has none of the service-linked roles EKS, managed node
  # groups, Auto Scaling and Spot need; the first cluster create makes them.
  # Scoped to exactly those services - not iam:CreateServiceLinkedRole on *.
  statement {
    sid       = "CreatePlatformServiceLinkedRoles"
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/aws-service-role/*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values = [
        "eks.amazonaws.com",
        "eks-nodegroup.amazonaws.com",
        "autoscaling.amazonaws.com",
        "spot.amazonaws.com",
        "elasticloadbalancing.amazonaws.com",
        "grafana.amazonaws.com",
        "scraper.aps.amazonaws.com",
      ]
    }
  }

  statement {
    sid    = "ManageKarpenterNodeInstanceProfile"
    effect = "Allow"
    actions = [
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:GetInstanceProfile",
      "iam:TagInstanceProfile",
      "iam:UntagInstanceProfile",
    ]
    resources = ["arn:aws:iam::${local.account_id}:instance-profile/platform-*"]
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
      "kms:UntagResource",
      "kms:ListAliases",
      "kms:GetKeyRotationStatus",
      "kms:ListResourceTags",
      "kms:ListGrants",
      "kms:Decrypt",
      "kms:GenerateDataKey",
    ]
    resources = ["*"]
  }

  # EKS secrets encryption and KMS-encrypted ECR repos both create a grant on
  # the key as the calling principal. Only grants AWS services use on our
  # behalf - not arbitrary grants to other principals.
  statement {
    sid       = "GrantKeysToAWSServices"
    effect    = "Allow"
    actions   = ["kms:CreateGrant"]
    resources = ["*"]
    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
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
      values   = local.app_team_subject_patterns
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

# checkov:skip=CKV_AWS_355: DescribeRepositories/GetRole/ListRoles are
# read-only, "*"-only APIs (see the same reasoning on plan_permissions
# above) - this role never writes anything; onboarding lands via a PR, not
# a direct apply (see .github/workflows/onboard-service.yml).
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
