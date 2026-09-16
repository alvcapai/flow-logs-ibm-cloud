###############################################################################
# IBM Cloud VPC Flow Logs – All-VPC Centralized Setup via Schematics Workspace
#
# What this does:
#   1. For every region in var.regions, discovers ALL VPCs in the account.
#   2. Creates one single-region COS bucket per region (same-region constraint).
#   3. Creates one account-level IAM authorization: Flow Log Collector → COS Writer.
#   4. Creates one VPC-scope Flow Log Collector per discovered VPC, pointing to
#      the matching regional bucket — all flow data centralizes in one COS instance.
#   5. Wraps everything in an IBM Cloud Schematics workspace.
#
# Supported regions: br-sao, us-south, us-east, ca-tor, eu-de, eu-gb,
#                    au-syd, jp-tok, jp-osa
# To add a region: add the alias block + its data source below and include
# the region in var.regions.
###############################################################################

terraform {
  required_version = ">= 1.5"
  required_providers {
    ibm = {
      source  = "IBM-Cloud/ibm"
      version = ">= 1.66"
    }
  }
}

###############################################################################
# Provider – one alias per supported IBM Cloud region
# Only the regions listed in var.regions are actually used.
###############################################################################

provider "ibm" {
  alias            = "br_sao"
  region           = "br-sao"
  ibmcloud_api_key = var.ibmcloud_api_key
}

provider "ibm" {
  alias            = "us_south"
  region           = "us-south"
  ibmcloud_api_key = var.ibmcloud_api_key
}

provider "ibm" {
  alias            = "us_east"
  region           = "us-east"
  ibmcloud_api_key = var.ibmcloud_api_key
}

provider "ibm" {
  alias            = "ca_tor"
  region           = "ca-tor"
  ibmcloud_api_key = var.ibmcloud_api_key
}

provider "ibm" {
  alias            = "eu_de"
  region           = "eu-de"
  ibmcloud_api_key = var.ibmcloud_api_key
}

provider "ibm" {
  alias            = "eu_gb"
  region           = "eu-gb"
  ibmcloud_api_key = var.ibmcloud_api_key
}

provider "ibm" {
  alias            = "au_syd"
  region           = "au-syd"
  ibmcloud_api_key = var.ibmcloud_api_key
}

provider "ibm" {
  alias            = "jp_tok"
  region           = "jp-tok"
  ibmcloud_api_key = var.ibmcloud_api_key
}

provider "ibm" {
  alias            = "jp_osa"
  region           = "jp-osa"
  ibmcloud_api_key = var.ibmcloud_api_key
}

# Default provider (required by global resources: COS instance, IAM, Schematics)
provider "ibm" {
  region           = var.regions[0]
  ibmcloud_api_key = var.ibmcloud_api_key
}

###############################################################################
# 1. COS instance – single global instance that holds all regional buckets
###############################################################################

resource "ibm_resource_instance" "cos" {
  count             = var.create_cos_instance ? 1 : 0
  name              = var.cos_instance_name
  resource_group_id = var.resource_group_id
  service           = "cloud-object-storage"
  plan              = "standard"
  location          = "global"
}

locals {
  cos_instance_id = var.create_cos_instance ? ibm_resource_instance.cos[0].id : var.existing_cos_instance_id
}

###############################################################################
# 2. One COS bucket per region  (single-region = same region as its VPCs)
###############################################################################

resource "ibm_cos_bucket" "flow_logs" {
  for_each = toset(var.regions)

  bucket_name          = "${var.cos_bucket_name_prefix}-${each.key}"
  resource_instance_id = local.cos_instance_id
  single_site_location = each.key
  storage_class        = "standard"
}

###############################################################################
# 3. IAM service-to-service authorization (account-level, created once)
#    Grants every Flow Log Collector in the account Writer access to the COS instance.
###############################################################################

resource "ibm_iam_authorization_policy" "flow_logs_to_cos" {
  source_service_name         = "is"
  source_resource_type        = "flow-log-collector"
  target_service_name         = "cloud-object-storage"
  target_resource_instance_id = local.cos_instance_id
  roles                       = ["Writer"]

  description = "Allow all VPC Flow Log Collectors in the account to write to the centralized COS instance"
}

###############################################################################
# 4. Discover all VPCs per region
#    One data source per supported region; filtered to active regions below.
###############################################################################

data "ibm_is_vpcs" "br_sao" {
  provider = ibm.br_sao
}
data "ibm_is_vpcs" "us_south" {
  provider = ibm.us_south
}
data "ibm_is_vpcs" "us_east" {
  provider = ibm.us_east
}
data "ibm_is_vpcs" "ca_tor" {
  provider = ibm.ca_tor
}
data "ibm_is_vpcs" "eu_de" {
  provider = ibm.eu_de
}
data "ibm_is_vpcs" "eu_gb" {
  provider = ibm.eu_gb
}
data "ibm_is_vpcs" "au_syd" {
  provider = ibm.au_syd
}
data "ibm_is_vpcs" "jp_tok" {
  provider = ibm.jp_tok
}
data "ibm_is_vpcs" "jp_osa" {
  provider = ibm.jp_osa
}

locals {
  # Map region → list of VPCs returned by the data source for that region.
  # Regions not present in var.regions produce an empty list, so their VPCs
  # are excluded from vpc_map without causing errors.
  region_vpcs = {
    "br-sao"   = contains(var.regions, "br-sao")   ? try(data.ibm_is_vpcs.br_sao.vpcs,   []) : []
    "us-south" = contains(var.regions, "us-south") ? try(data.ibm_is_vpcs.us_south.vpcs, []) : []
    "us-east"  = contains(var.regions, "us-east")  ? try(data.ibm_is_vpcs.us_east.vpcs,  []) : []
    "ca-tor"   = contains(var.regions, "ca-tor")   ? try(data.ibm_is_vpcs.ca_tor.vpcs,   []) : []
    "eu-de"    = contains(var.regions, "eu-de")    ? try(data.ibm_is_vpcs.eu_de.vpcs,    []) : []
    "eu-gb"    = contains(var.regions, "eu-gb")    ? try(data.ibm_is_vpcs.eu_gb.vpcs,    []) : []
    "au-syd"   = contains(var.regions, "au-syd")   ? try(data.ibm_is_vpcs.au_syd.vpcs,   []) : []
    "jp-tok"   = contains(var.regions, "jp-tok")   ? try(data.ibm_is_vpcs.jp_tok.vpcs,   []) : []
    "jp-osa"   = contains(var.regions, "jp-osa")   ? try(data.ibm_is_vpcs.jp_osa.vpcs,   []) : []
  }

  # Flat map: "<region>/<vpc-id>" → { region, vpc_id, vpc_name }
  # Used as the for_each key for ibm_is_flow_log.collectors.
  vpc_map = merge([
    for region, vpcs in local.region_vpcs : {
      for vpc in vpcs :
      "${region}/${vpc.id}" => {
        region   = region
        vpc_id   = vpc.id
        vpc_name = vpc.name
      }
    }
  ]...)
}

###############################################################################
# 5. Flow Log Collector – one per discovered VPC
###############################################################################

resource "ibm_is_flow_log" "collectors" {
  for_each = local.vpc_map

  name           = "flowlog-${each.value.vpc_name}"
  target         = each.value.vpc_id
  active         = true
  storage_bucket = ibm_cos_bucket.flow_logs[each.value.region].bucket_name

  depends_on = [ibm_iam_authorization_policy.flow_logs_to_cos]
}

###############################################################################
# 6. Schematics workspace
###############################################################################

resource "ibm_schematics_workspace" "flow_logs" {
  name           = var.schematics_workspace_name
  description    = "Centralized VPC Flow Logs – all VPCs across ${length(var.regions)} region(s)"
  location       = var.schematics_location
  resource_group = var.resource_group_id
  tags           = var.tags

  template_type = "terraform_v1.5"

  template_git_url    = var.git_repo_url
  template_git_branch = var.git_repo_branch
  template_git_folder = var.git_repo_folder

  template_inputs {
    name   = "ibmcloud_api_key"
    value  = var.ibmcloud_api_key
    type   = "string"
    secure = true
  }

  template_inputs {
    name  = "regions"
    value = jsonencode(var.regions)
    type  = "string"
  }

  template_inputs {
    name  = "resource_group_id"
    value = var.resource_group_id
    type  = "string"
  }

  template_inputs {
    name  = "cos_bucket_name_prefix"
    value = var.cos_bucket_name_prefix
    type  = "string"
  }

  template_inputs {
    name  = "schematics_workspace_name"
    value = var.schematics_workspace_name
    type  = "string"
  }
}
