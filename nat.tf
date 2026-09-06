# NAT gateways and routing for private subnet egress.
#
# One NAT gateway per AZ by default. A single shared gateway is cheaper,
# but it makes every private subnet depend on one availability zone: if
# that AZ fails, nodes in healthy AZs lose outbound access and can no
# longer pull images or reach AWS APIs. var.single_nat_gateway exists for
# dev environments where that trade is acceptable.

locals {
  nat_gateway_count = var.single_nat_gateway ? 1 : local.az_count
}

resource "aws_eip" "nat" {
  count = local.nat_gateway_count

  domain = "vpc"

  tags = {
    Name = "${var.cluster_name}-nat-${count.index}"
  }
}

resource "aws_nat_gateway" "this" {
  count = local.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.cluster_name}-nat-${count.index}"
  }

  # The gateway is unusable until the IGW has a route, and Terraform does
  # not infer that ordering on its own.
  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.cluster_name}-public"
  }
}

resource "aws_route_table_association" "public" {
  count = local.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# One route table per private subnet, so each can egress through the NAT
# gateway in its own AZ. Cross-AZ NAT traffic is billed as inter-AZ data
# transfer, which is a quiet and surprisingly large line item at scale.
resource "aws_route_table" "private" {
  count = local.az_count

  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[var.single_nat_gateway ? 0 : count.index].id
  }

  tags = {
    Name = "${var.cluster_name}-private-${var.azs[count.index]}"
  }
}

resource "aws_route_table_association" "private" {
  count = local.az_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
