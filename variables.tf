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

variable "resource_group_name" {
  description = "Name of the IBM Cloud resource group that will own all resources (e.g. Default, RG-alvaro). The ID is resolved automatically via data source."
  type        = string
  default     = "Default"
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

variable "account_name" {
  description = <<-EOT
    Short identifier for the IBM Cloud account (e.g. acme-prod).
    Used to name the single COS bucket: vpc-flow-log-<account-name>.
    Must produce a globally unique bucket name in IBM Cloud COS.
  EOT
  type = string
}
