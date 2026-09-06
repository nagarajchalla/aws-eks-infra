# VPC and subnet layout.
#
# Subnet CIDRs are derived from var.vpc_cidr with cidrsubnet() rather than
# hardcoded, so changing the VPC range does not mean editing every subnet.
#
# Private subnets are /20 (4091 usable addresses each), public are /24.
# The asymmetry is deliberate - public subnets hold only load balancers and
# NAT gateways, while private subnets hold every node and every pod IP.

locals {
  az_count = length(var.azs)

  # 10.0.0.0/20, 10.0.16.0/20, 10.0.32.0/20
  private_subnet_cidrs = [
    for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, 4, i)
  ]

  # 10.0.240.0/24, 10.0.241.0/24, 10.0.242.0/24
  # Taken from the top of the range so private subnets can be grown later
  # without colliding.
  public_subnet_cidrs = [
    for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, 8, 240 + i)
  ]
}

resource "aws_vpc" "this" {
  cidr_block         = var.vpc_cidr
  enable_dns_support = true

  # Required for EKS. Without it, private endpoint DNS resolution fails
  # and nodes cannot reach the API server.
  enable_dns_hostnames = true

  tags = {
    Name = "${var.cluster_name}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

resource "aws_subnet" "public" {
  count = local.az_count

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.cluster_name}-public-${var.azs[count.index]}"

    # Tells the AWS Load Balancer Controller it may place internet-facing
    # load balancers in these subnets. Without this tag, Ingress objects
    # provision nothing and fail with no obvious error.
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "private" {
  count = local.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${var.cluster_name}-private-${var.azs[count.index]}"

    # Equivalent tag for internal load balancers.
    "kubernetes.io/role/internal-elb" = "1"
  }
}
