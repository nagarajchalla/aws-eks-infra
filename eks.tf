# EKS control plane.
#
# The API endpoint is private by default and additionally exposed
# publicly only to var.public_access_cidrs. Leaving the public endpoint
# open to 0.0.0.0/0 is the most common EKS misconfiguration - the
# endpoint is authenticated, but it puts the API server in front of the
# entire internet and every credential leak becomes immediately usable.

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------
# Control plane IAM role
# ---------------------------------------------------------------------

resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ---------------------------------------------------------------------
# Envelope encryption for Kubernetes secrets
#
# Without this, secrets are stored base64-encoded in etcd - which is
# encoding, not encryption. A customer-managed key also gives an audit
# trail in CloudTrail of every decrypt call.
# ---------------------------------------------------------------------

resource "aws_kms_key" "eks" {
  description             = "Envelope encryption key for ${var.cluster_name} secrets"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.cluster_name}-eks"
  target_key_id = aws_kms_key.eks.key_id
}

# ---------------------------------------------------------------------
# Control plane logging
#
# The log group is created here rather than letting EKS create it
# implicitly, so retention is under Terraform's control. EKS defaults to
# never expiring, which bills forever.
# ---------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.cluster_log_retention_days
  kms_key_id        = aws_kms_key.eks.arn
}

# ---------------------------------------------------------------------
# Cluster security group
# ---------------------------------------------------------------------

resource "aws_security_group" "cluster" {
  name        = "${var.cluster_name}-cluster"
  description = "EKS control plane security group"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.cluster_name}-cluster"
  }
}

resource "aws_security_group_rule" "cluster_egress" {
  type              = "egress"
  description       = "Control plane outbound to nodes and AWS APIs"
  security_group_id = aws_security_group.cluster.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

# ---------------------------------------------------------------------
# Cluster
# ---------------------------------------------------------------------

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.cluster_version

  vpc_config {
    # Control plane ENIs live in the private subnets only.
    subnet_ids              = aws_subnet.private[*].id
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = var.cluster_endpoint_public_access
    public_access_cidrs     = var.cluster_endpoint_public_access ? var.public_access_cidrs : null
  }

  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }

  # audit is the one that matters for incident response - it records who
  # called what against the API server. The others are cheap to keep on.
  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler",
  ]

  # The log group must exist before the cluster starts writing, and the
  # IAM policy must be attached before the control plane is created.
  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_cloudwatch_log_group.cluster,
  ]

  tags = {
    Name = var.cluster_name
  }
}
