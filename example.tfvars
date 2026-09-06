# Example configuration. Copy to terraform.tfvars and adjust.

cluster_name = "demo-eks"
region       = "ap-south-1"
environment  = "dev"

# Narrow this to your office and CI egress ranges before using anything
# resembling this in production.
public_access_cidrs = ["0.0.0.0/0"]

irsa_roles = {
  # External Secrets Operator reading from Secrets Manager.
  external-secrets = {
    namespace       = "external-secrets"
    service_account = "external-secrets"
    policy_arns     = ["arn:aws:iam::aws:policy/SecretsManagerReadWrite"]
  }

  # Cluster autoscaler needs to describe and modify ASGs.
  cluster-autoscaler = {
    namespace       = "kube-system"
    service_account = "cluster-autoscaler"
    policy_arns     = []
  }
}
