###############################################################################
# Required
###############################################################################

variable "regions" {
  description = <<-EOT
    List of IBM Cloud regions to scan for VPCs.
    A Flow Log Collector and a same-region COS bucket are created for every VPC
    found in each listed region.
    Supported values: br-sao, us-south, us-east, ca-tor, eu-de, eu-gb, au-syd, jp-tok, jp-osa
  EOT
  type    = list(string)
  default = ["br-sao", "us-south"]

  validation {
    condition = alltrue([
      for r in var.regions :
      contains(["br-sao", "us-south", "us-east", "ca-tor", "eu-de", "eu-gb", "au-syd", "jp-tok", "jp-osa"], r)
    ])
    error_message = "Each region must be one of: br-sao, us-south, us-east, ca-tor, eu-de, eu-gb, au-syd, jp-tok, jp-osa."
  }
}

variable "resource_group_id" {
  description = "ID of the resource group that will own all resources created by this configuration."
  type        = string
}

###############################################################################
# COS
###############################################################################

variable "create_cos_instance" {
  description = "Set to true to create a new COS instance. Set to false to reuse an existing one (supply existing_cos_instance_id)."
  type        = bool
  default     = true
}

variable "cos_instance_name" {
  description = "Name for the new COS instance (used only when create_cos_instance = true)."
  type        = string
  default     = "cos-vpc-flow-logs-central"
}

variable "existing_cos_instance_id" {
  description = "CRN of an existing COS instance (used only when create_cos_instance = false)."
  type        = string
  default     = ""
}

variable "cos_bucket_name_prefix" {
  description = <<-EOT
    Prefix for the per-region COS bucket names.
    Each bucket is named <prefix>-<region>, e.g. enterprise-vpc-flowlogs-br-sao.
    Must be globally unique in IBM Cloud COS.
  EOT
  type    = string
  default = "enterprise-vpc-flowlogs"
}
