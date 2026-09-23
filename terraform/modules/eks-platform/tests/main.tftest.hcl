mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
  mock_data "aws_region" {
    defaults = {
      name = "us-east-1"
    }
  }
  mock_resource "aws_eks_cluster" {
    defaults = {
      arn = "arn:aws:eks:us-east-1:111122223333:cluster/test-eks"
      identity = [{
        oidc = [{ issuer = "https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE" }]
      }]
    }
  }
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::111122223333:role/test"
    }
  }
  mock_resource "aws_iam_instance_profile" {
    defaults = {
      arn = "arn:aws:iam::111122223333:instance-profile/test"
    }
  }
  mock_resource "aws_sqs_queue" {
    defaults = {
      arn = "arn:aws:sqs:us-east-1:111122223333:test"
    }
  }
  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:us-east-1:111122223333:key/test"
    }
  }
}

mock_provider "tls" {
  mock_data "tls_certificate" {
    defaults = {
      certificates = [{ sha1_fingerprint = "0000000000000000000000000000000000000000" }]
    }
  }
}

mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  cluster_name       = "test-eks"
  vpc_id             = "vpc-1"
  private_subnet_ids = ["subnet-a", "subnet-b"]
}

run "network_policy_is_enforced" {
  command = plan

  assert {
    condition     = jsondecode(aws_eks_addon.vpc_cni.configuration_values).enableNetworkPolicy == "true"
    error_message = "The VPC CNI must enforce NetworkPolicy, or tenant default-deny policies are decoration."
  }
}

run "coredns_tolerates_system_taint" {
  command = plan

  assert {
    condition = anytrue([
      for t in jsondecode(aws_eks_addon.coredns.configuration_values).tolerations : t.key == "platform-system"
    ])
    error_message = "CoreDNS must tolerate the platform-system taint - every initial node carries it."
  }
}

run "endpoint_private_by_default" {
  command = plan

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_public_access == false
    error_message = "The API endpoint must be private unless explicitly opened."
  }
}

run "public_endpoint_requires_allowlist" {
  command = plan

  variables {
    endpoint_public_access = true
    public_access_cidrs    = []
  }

  expect_failures = [var.public_access_cidrs]
}
