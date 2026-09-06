# Node security group and control plane traffic rules.
#
# Managed node groups get an EKS-managed security group by default, which
# allows all traffic between nodes and the control plane. This file
# narrows that to the ports actually needed.

resource "aws_security_group" "node" {
  name        = "${var.cluster_name}-node"
  description = "EKS worker node security group"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.cluster_name}-node"

    # The in-tree cloud provider still looks for this tag when
    # reconciling load balancers.
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

# Pods on different nodes have to reach each other for any multi-node
# workload to function, so node-to-node is open within the group.
resource "aws_security_group_rule" "node_to_node" {
  type                     = "ingress"
  description              = "Node to node, all ports"
  security_group_id        = aws_security_group.node.id
  source_security_group_id = aws_security_group.node.id
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
}

# The kubelet API. This is how the control plane runs exec, logs and
# port-forward, and how the metrics server scrapes.
resource "aws_security_group_rule" "node_from_cluster_kubelet" {
  type                     = "ingress"
  description              = "Kubelet API from control plane"
  security_group_id        = aws_security_group.node.id
  source_security_group_id = aws_security_group.cluster.id
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
}

# Admission and conversion webhooks listen on high ports. Without this
# rule, installing anything with a webhook - cert-manager, most operators
# - fails with an opaque context deadline exceeded.
resource "aws_security_group_rule" "node_from_cluster_webhooks" {
  type                     = "ingress"
  description              = "Webhook ports from control plane"
  security_group_id        = aws_security_group.node.id
  source_security_group_id = aws_security_group.cluster.id
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
}

resource "aws_security_group_rule" "node_egress" {
  type              = "egress"
  description       = "Node outbound for image pulls and AWS APIs"
  security_group_id = aws_security_group.node.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

# Nodes reach the API server on 443. With a private endpoint this stays
# entirely inside the VPC.
resource "aws_security_group_rule" "cluster_from_node" {
  type                     = "ingress"
  description              = "API server from nodes"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.node.id
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
}
