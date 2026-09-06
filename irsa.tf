# IAM Roles for Service Accounts (IRSA).
#
# Without this, a pod that needs AWS permissions gets them from the node
# role - which means every other pod on that node gets them too. IRSA
# gives each service account its own role, scoped by a trust policy that
# only that service account can satisfy.
#
# This is the reason for http_put_response_hop_limit = 1 on the launch
# template. IRSA only helps if pods cannot reach instance metadata and
# grab the node role directly.

data "tls_certificate" "oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]

  tags = {
    Name = "${var.cluster_name}-oidc"
  }
}

locals {
  oidc_provider = replace(aws_iam_openid_connect_provider.this.url, "https://", "")
}

# ---------------------------------------------------------------------
# Trust policy builder
#
# The sub condition pins the role to one namespace and one service
# account. Using StringLike with a wildcard here - a common shortcut -
# would let any service account in the cluster assume the role.
#
# The aud condition is not optional. Without it the trust policy can be
# satisfied by tokens issued for a different audience.
# ---------------------------------------------------------------------

data "aws_iam_policy_document" "irsa_trust" {
  for_each = var.irsa_roles

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.this.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider}:sub"
      values   = ["system:serviceaccount:${each.value.namespace}:${each.value.service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "irsa" {
  for_each = var.irsa_roles

  name               = "${var.cluster_name}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.irsa_trust[each.key].json

  tags = {
    Name           = "${var.cluster_name}-${each.key}"
    ServiceAccount = "${each.value.namespace}/${each.value.service_account}"
  }
}

resource "aws_iam_role_policy_attachment" "irsa" {
  for_each = {
    for pair in flatten([
      for name, cfg in var.irsa_roles : [
        for arn in cfg.policy_arns : {
          key      = "${name}:${arn}"
          role     = name
          policy   = arn
        }
      ]
    ]) : pair.key => pair
  }

  role       = aws_iam_role.irsa[each.value.role].name
  policy_arn = each.value.policy
}
