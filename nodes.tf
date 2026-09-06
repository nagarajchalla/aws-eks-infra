# Managed node group.
#
# Nodes run in the private subnets and reach the internet through the NAT
# gateways. They are never directly addressable from outside the VPC.

# ---------------------------------------------------------------------
# Node IAM role
#
# These three managed policies are the minimum EKS requires. The CNI
# policy is the uncomfortable one - it grants ENI manipulation to every
# node, and by extension to any pod that can reach the node's instance
# metadata. IMDSv2 with a hop limit of 1 (set in the launch template
# below) is what stops pods from reaching it.
# ---------------------------------------------------------------------

resource "aws_iam_role" "node" {
  name = "${var.cluster_name}-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ---------------------------------------------------------------------
# Launch template
#
# No image_id or instance_type is set here on purpose. Leaving them out
# lets EKS inject the current EKS-optimised AMI and the correct bootstrap
# user data. Pinning an AMI here means owning AMI upgrades by hand.
# ---------------------------------------------------------------------

resource "aws_launch_template" "node" {
  name_prefix = "${var.cluster_name}-node-"

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.node_disk_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 only - blocks SSRF-style credential theft

    # A hop limit of 1 means the metadata service is unreachable from
    # inside a container, so a compromised pod cannot assume the node
    # role. This is the single highest-value line in this file.
    http_put_response_hop_limit = 1
  }

  monitoring {
    enabled = true
  }

  vpc_security_group_ids = [aws_security_group.node.id]

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "${var.cluster_name}-node"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------
# Node group
# ---------------------------------------------------------------------

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-default"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = aws_subnet.private[*].id

  instance_types = var.node_instance_types
  capacity_type  = "ON_DEMAND"

  scaling_config {
    min_size     = var.node_group_min_size
    desired_size = var.node_group_desired_size
    max_size     = var.node_group_max_size
  }

  # Allow one node to be unavailable at a time during version upgrades,
  # so a rolling upgrade cannot take out the whole group at once.
  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  lifecycle {
    # Once the cluster autoscaler is running it owns desired_size.
    # Without this, every terraform apply would scale the group back to
    # the value in the variable.
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]

  tags = {
    Name = "${var.cluster_name}-default"
  }
}
