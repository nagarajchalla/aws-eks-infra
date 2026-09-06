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
