variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster. Used as the name prefix for all resources."
  type        = string
}

variable "environment" {
  description = "Environment name, applied as a tag to every resource"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = <<-EOT
    CIDR block for the VPC. Size this generously: with the AWS VPC CNI
    every pod consumes a real VPC address, so the cluster runs out of
    pod IPs long before it runs out of node capacity.
  EOT
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "azs" {
  description = "Availability zones to spread subnets across. Three is the minimum for a production control plane."
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]

  validation {
    condition     = length(var.azs) >= 2
    error_message = "At least two availability zones are required by EKS."
  }
}

variable "single_nat_gateway" {
  description = <<-EOT
    Route all private subnets through one NAT gateway instead of one per AZ.
    Cheaper, but a single AZ failure removes outbound access for the whole
    cluster and nodes stop being able to pull images. Dev only.
  EOT
  type        = bool
  default     = false
}

variable "cluster_version" {
  description = "Kubernetes minor version for the control plane. Check the EKS supported version calendar before bumping - versions leave standard support after roughly 14 months."
  type        = string
  default     = "1.32"
}

variable "public_access_cidrs" {
  description = <<-EOT
    CIDR blocks allowed to reach the public API endpoint. Defaults to
    open, which is the single most common EKS misconfiguration - narrow
    this to office and CI egress ranges, or set
    cluster_endpoint_public_access = false and reach the API through a
    bastion or VPN instead.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_endpoint_public_access" {
  description = "Expose the Kubernetes API on a public endpoint in addition to the private one. Private access is always enabled."
  type        = bool
  default     = true
}

variable "cluster_log_retention_days" {
  description = "Retention for control plane logs. 90 days is a common compliance floor; CloudWatch charges by ingestion and storage, so indefinite retention gets expensive."
  type        = number
  default     = 90
}

variable "node_instance_types" {
  description = "Instance types for the managed node group. Multiple types improve capacity availability, especially with SPOT."
  type        = list(string)
  default     = ["t3.large"]
}

variable "node_group_min_size" {
  description = "Minimum nodes in the managed node group"
  type        = number
  default     = 2
}

variable "node_group_desired_size" {
  description = "Initial node count. Ignored on subsequent applies so the cluster autoscaler can own it."
  type        = number
  default     = 2
}

variable "node_group_max_size" {
  description = "Maximum nodes the group may scale to"
  type        = number
  default     = 6
}

variable "node_disk_size" {
  description = "EBS volume size per node in GiB. Container images and ephemeral storage share this volume; 20 GiB fills quickly and triggers disk-pressure evictions."
  type        = number
  default     = 50
}

variable "irsa_roles" {
  description = <<-EOT
    IAM roles bound to Kubernetes service accounts. Each entry creates a
    role whose trust policy admits exactly one service account in one
    namespace.

    Annotate the service account with the role ARN for it to take effect:
      eks.amazonaws.com/role-arn: <role_arn>
  EOT

  type = map(object({
    namespace       = string
    service_account = string
    policy_arns     = list(string)
  }))

  default = {}
}
