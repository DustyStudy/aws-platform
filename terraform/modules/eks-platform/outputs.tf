output "cluster_name" {
  value = aws_eks_cluster.this.name

  # Everything in-cluster (tenant namespaces, providers, add-ons downstream)
  # reads this output, so this orders their destroy before the networking
  # add-ons'. The VPC CNI's network policy components clear a finalizer on
  # every NetworkPolicy; removed first, tenant namespaces never finish deleting.
  depends_on = [
    aws_eks_addon.vpc_cni,
    aws_eks_addon.kube_proxy,
    aws_eks_addon.coredns,
  ]
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  value     = aws_eks_cluster.this.certificate_authority[0].data
  sensitive = true
}

output "cluster_arn" {
  value = aws_eks_cluster.this.arn
}

output "cluster_security_group_id" {
  value = aws_security_group.cluster.id
}

output "cluster_primary_security_group_id" {
  description = "The security group EKS creates for the cluster - on the control plane ENIs, managed nodes and Karpenter nodes alike."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.cluster.arn
}

output "oidc_provider_url" {
  value = aws_iam_openid_connect_provider.cluster.url
}

output "node_role_arn" {
  value = aws_iam_role.node.arn
}
