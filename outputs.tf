output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets, ordered to match var.azs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets, ordered to match var.azs. Node groups and internal load balancers belong here."
  value       = aws_subnet.private[*].id
}

output "nat_gateway_ips" {
  description = "Public IPs of the NAT gateways. Useful when a third party needs to allowlist cluster egress."
  value       = aws_eip.nat[*].public_ip
}

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded CA certificate for the cluster, needed to build a kubeconfig"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "Security group attached to the control plane ENIs"
  value       = aws_security_group.cluster.id
}

output "node_role_arn" {
  description = "IAM role ARN assumed by worker nodes"
  value       = aws_iam_role.node.arn
}

output "configure_kubectl" {
  description = "Command to write a kubeconfig entry for this cluster"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.this.name}"
}
