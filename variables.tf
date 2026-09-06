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
