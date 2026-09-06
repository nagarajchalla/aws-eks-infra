# aws-eks-infra

![Terraform](https://github.com/Nagarajchalla/aws-eks-infra/actions/workflows/terraform.yml/badge.svg)

Terraform for an Amazon EKS cluster: VPC across three AZs, private node
groups, IRSA, secrets encryption, and control plane logging. Written to show
how I approach cluster infrastructure — the decisions matter more than the
resource list, so most of this README is about why things are the way they
are.

## What it builds

- VPC with public and private subnets in three availability zones
- One NAT gateway per AZ (or a single shared one, for dev)
- EKS control plane with a private endpoint, public access restricted by CIDR
- Managed node group in private subnets, on a launch template
- IRSA — OIDC provider plus per-service-account IAM roles
- KMS envelope encryption for Kubernetes secrets
- Control plane audit logging to CloudWatch with managed retention
- Security groups scoped to the ports EKS actually needs

## Usage

```hcl
module "eks" {
  source = "github.com/Nagarajchalla/aws-eks-infra"

  cluster_name = "demo-eks"
  region       = "ap-south-1"

  public_access_cidrs = ["203.0.113.0/24"]

  irsa_roles = {
    external-secrets = {
      namespace       = "external-secrets"
      service_account = "external-secrets"
      policy_arns     = ["arn:aws:iam::aws:policy/SecretsManagerReadWrite"]
    }
  }
}
```

Then:

```bash
aws eks update-kubeconfig --region ap-south-1 --name demo-eks
```

See `example.tfvars` for a fuller configuration.

## Design decisions

**Private subnets are /20, public are /24.** With the AWS VPC CNI every pod
consumes a real VPC address, not an overlay address. A /24 private subnet
runs out of pod IPs long before the nodes run out of CPU or memory, and the
failure mode is pods stuck in `ContainerCreating` with a
`failed to assign an IP address` event. Public subnets hold only load
balancers and NAT gateways, so they stay small.

**One NAT gateway per AZ.** A single shared gateway is cheaper, but it makes
every private subnet depend on one availability zone — if that AZ fails,
nodes in healthy AZs lose outbound access and stop being able to pull
images. Cross-AZ NAT traffic also bills as inter-AZ data transfer, which is
a quiet and surprisingly large line item at scale. `single_nat_gateway` is
there for dev, where the trade is fine.

**IMDS hop limit of 1.** The `AmazonEKS_CNI_Policy` grants ENI manipulation
to the node role, and any pod that can reach instance metadata inherits it.
A hop limit of 1 makes the metadata service unreachable from inside a
container. This is the single most important line in `nodes.tf` — IRSA is
pointless without it, because a pod that can take the node role directly has
no reason to bother with its own.

**IRSA trust policies use `StringEquals`, not `StringLike`.** The wildcard
form is a common shortcut and it means any service account in the cluster can
assume the role. The `aud` condition is also not optional: without it the
policy can be satisfied by a token issued for a different audience.

**Secrets encryption with a customer-managed key.** Without
`encryption_config`, Kubernetes secrets sit base64-encoded in etcd — that is
encoding, not encryption. A CMK also produces a CloudTrail record of every
decrypt call, which is what you want during an investigation.

**Webhook ports 1025–65535 open from the control plane to nodes.** Leave this
rule out and cert-manager, most operators, and anything else with an
admission or conversion webhook fails with `context deadline exceeded` and no
useful explanation.

**`ignore_changes` on `desired_size`.** Once the cluster autoscaler is
running it owns node count. Without this, every `terraform apply` scales the
group back to the value in the variable and silently undoes the autoscaler.

**No `image_id` in the launch template.** Leaving it out lets EKS inject the
current EKS-optimised AMI and the correct bootstrap user data. Pinning an AMI
means owning AMI patching by hand.

**The public endpoint defaults to `0.0.0.0/0`, and that is deliberate.**
It is the default because it is what people actually run, and leaving it
visible in `variables.tf` with a comment is more useful than hiding it. It
should be narrowed to office and CI egress ranges, or the public endpoint
turned off entirely and the API reached through a bastion.

## CI

`terraform fmt`, `terraform validate`, Checkov, and tfsec run on every push.
Findings upload as SARIF to the Security tab.

Policy scanning is report-only. A first Checkov run against any real module
produces enough findings that gating immediately just gets the workflow
disabled — the useful path is report, baseline the accepted findings, then
gate on new ones.

## Cost warning

This is not free to run. An EKS control plane is about $73/month, each NAT
gateway around $32/month plus data transfer, and two t3.large nodes roughly
$120/month. Budget $250–350/month for the default configuration.

`terraform init` and `terraform validate` cost nothing and need no
credentials, which is enough to work on this repo.

## Not included

- Remote state backend — S3 and DynamoDB, intentionally left to the caller
- Cluster autoscaler or Karpenter — the IRSA role is here, the deployment is not
- AWS Load Balancer Controller — subnet tags are set for it
- Multi-account structure — this assumes a single account

## Author

Nagaraj Challa — DevOps & Cloud Security Engineer
[LinkedIn](https://linkedin.com/in/nagaraj-challa)
