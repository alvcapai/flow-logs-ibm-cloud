###############################################################################
# IBM Cloud VPC Flow Logs – All-VPC Centralized Setup
#
# Designed to run inside an IBM Cloud Schematics workspace.
#
# What this does:
#   1. For every region in var.regions, discovers ALL VPCs in the account.
#   2. Creates one single-region COS bucket per region (same-region constraint).
#   3. Creates one account-level IAM authorization: Flow Log Collector → COS Writer.
#   4. Creates one VPC-scope Flow Log Collector per discovered VPC, pointing to
#      the matching regional bucket — all flow data centralizes in one COS instance.
#
# Authentication:
#   No API key is needed. When this code runs inside Schematics on the same
#   account being provisioned, Schematics provides the identity context
#   automatically — the IBM provider picks it up without any credential variable.
#
# Supported regions: br-sao, us-south, us-east, ca-tor, eu-de, eu-gb,
#                    au-syd, jp-tok, jp-osa
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
# No credentials needed: Schematics supplies the identity context automatically.
# Only the regions listed in var.regions are actually queried.
###############################################################################

provider "ibm" {
  alias  = "br_sao"
  region = "br-sao"
}

provider "ibm" {
  alias  = "us_south"
  region = "us-south"
}

provider "ibm" {
  alias  = "us_east"
  region = "us-east"
}

provider "ibm" {
  alias  = "ca_tor"
  region = "ca-tor"
}

provider "ibm" {
  alias  = "eu_de"
  region = "eu-de"
}

provider "ibm" {
  alias  = "eu_gb"
  region = "eu-gb"
}

provider "ibm" {
  alias  = "au_syd"
  region = "au-syd"
}

provider "ibm" {
  alias  = "jp_tok"
  region = "jp-tok"
}

provider "ibm" {
  alias  = "jp_osa"
  region = "jp-osa"
}

# Default provider (used by global resources: COS instance, IAM authorization)
provider "ibm" {
  region = var.regions[0]
}

###############################################################################
# 0. Resolve resource group name → ID
###############################################################################

data "ibm_resource_group" "target" {
  name = var.resource_group_name
}

###############################################################################
# 1. COS instance – single global instance that holds all regional buckets
###############################################################################

resource "ibm_resource_instance" "cos" {
  count             = var.create_cos_instance ? 1 : 0
  name              = var.cos_instance_name
  resource_group_id = data.ibm_resource_group.target.id
  service           = "cloud-object-storage"
  plan              = "standard"
  location          = "global"
}

locals {
  cos_instance_id = var.create_cos_instance ? ibm_resource_instance.cos[0].id : var.existing_cos_instance_id
}

###############################################################################
# 2. One COS bucket per account (single-region eu-de) shared by all regions
###############################################################################

resource "ibm_cos_bucket" "flow_logs" {
  bucket_name          = "${var.cos_bucket_name_prefix}-flow-logs"
  resource_instance_id = ibm_resource_instance.cos.id
  region_location      = "eu-de"      # was single_region_location
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
#    One data source per supported region; only regions in var.regions are used.
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
  # Map region → VPC list. Regions absent from var.regions yield an empty list.
  region_vpcs = {
    "br-sao"   = contains(var.regions, "br-sao") ? try(data.ibm_is_vpcs.br_sao.vpcs, []) : []
    "us-south" = contains(var.regions, "us-south") ? try(data.ibm_is_vpcs.us_south.vpcs, []) : []
    "us-east"  = contains(var.regions, "us-east") ? try(data.ibm_is_vpcs.us_east.vpcs, []) : []
    "ca-tor"   = contains(var.regions, "ca-tor") ? try(data.ibm_is_vpcs.ca_tor.vpcs, []) : []
    "eu-de"    = contains(var.regions, "eu-de") ? try(data.ibm_is_vpcs.eu_de.vpcs, []) : []
    "eu-gb"    = contains(var.regions, "eu-gb") ? try(data.ibm_is_vpcs.eu_gb.vpcs, []) : []
    "au-syd"   = contains(var.regions, "au-syd") ? try(data.ibm_is_vpcs.au_syd.vpcs, []) : []
    "jp-tok"   = contains(var.regions, "jp-tok") ? try(data.ibm_is_vpcs.jp_tok.vpcs, []) : []
    "jp-osa"   = contains(var.regions, "jp-osa") ? try(data.ibm_is_vpcs.jp_osa.vpcs, []) : []
  }

  # Full map: "<region>/<vpc-id>" → { region, vpc_id, vpc_name }
  vpc_map_all = merge([
    for region, vpcs in local.region_vpcs : {
      for vpc in vpcs :
      "${region}/${vpc.id}" => {
        region   = region
        vpc_id   = vpc.id
        vpc_name = vpc.name
      }
    }
  ]...)

  # IDs of VPCs that already have a Flow Log Collector — exclude to avoid
  # "duplicate FLC" errors. Indexed by vpc target ID for fast lookup.
  existing_collector_targets = toset(flatten([
    for region in var.regions : [
      for flc in try(local.existing_flcs[region], []) : flc.target
    ]
  ]))

  existing_flcs = {
    "br-sao"   = contains(var.regions, "br-sao") ? try(data.ibm_is_flow_logs.existing_br_sao.flow_log_collectors, []) : []
    "us-south" = contains(var.regions, "us-south") ? try(data.ibm_is_flow_logs.existing_us_south.flow_log_collectors, []) : []
    "us-east"  = contains(var.regions, "us-east") ? try(data.ibm_is_flow_logs.existing_us_east.flow_log_collectors, []) : []
    "ca-tor"   = contains(var.regions, "ca-tor") ? try(data.ibm_is_flow_logs.existing_ca_tor.flow_log_collectors, []) : []
    "eu-de"    = contains(var.regions, "eu-de") ? try(data.ibm_is_flow_logs.existing_eu_de.flow_log_collectors, []) : []
    "eu-gb"    = contains(var.regions, "eu-gb") ? try(data.ibm_is_flow_logs.existing_eu_gb.flow_log_collectors, []) : []
    "au-syd"   = contains(var.regions, "au-syd") ? try(data.ibm_is_flow_logs.existing_au_syd.flow_log_collectors, []) : []
    "jp-tok"   = contains(var.regions, "jp-tok") ? try(data.ibm_is_flow_logs.existing_jp_tok.flow_log_collectors, []) : []
    "jp-osa"   = contains(var.regions, "jp-osa") ? try(data.ibm_is_flow_logs.existing_jp_osa.flow_log_collectors, []) : []
  }

  # Final map: only VPCs that do NOT already have a collector
  vpc_map = {
    for key, vpc in local.vpc_map_all :
    key => vpc
    if !contains(local.existing_collector_targets, vpc.vpc_id)
  }

  # Per-region sub-maps for static provider assignment
  vpc_map_br_sao   = { for k, v in local.vpc_map : k => v if v.region == "br-sao" }
  vpc_map_us_south = { for k, v in local.vpc_map : k => v if v.region == "us-south" }
  vpc_map_us_east  = { for k, v in local.vpc_map : k => v if v.region == "us-east" }
  vpc_map_ca_tor   = { for k, v in local.vpc_map : k => v if v.region == "ca-tor" }
  vpc_map_eu_de    = { for k, v in local.vpc_map : k => v if v.region == "eu-de" }
  vpc_map_eu_gb    = { for k, v in local.vpc_map : k => v if v.region == "eu-gb" }
  vpc_map_au_syd   = { for k, v in local.vpc_map : k => v if v.region == "au-syd" }
  vpc_map_jp_tok   = { for k, v in local.vpc_map : k => v if v.region == "jp-tok" }
  vpc_map_jp_osa   = { for k, v in local.vpc_map : k => v if v.region == "jp-osa" }
}

###############################################################################
# 4b. Discover existing Flow Log Collectors (to skip VPCs already covered)
###############################################################################

data "ibm_is_flow_logs" "existing_br_sao" { provider = ibm.br_sao }
data "ibm_is_flow_logs" "existing_us_south" { provider = ibm.us_south }
data "ibm_is_flow_logs" "existing_us_east" { provider = ibm.us_east }
data "ibm_is_flow_logs" "existing_ca_tor" { provider = ibm.ca_tor }
data "ibm_is_flow_logs" "existing_eu_de" { provider = ibm.eu_de }
data "ibm_is_flow_logs" "existing_eu_gb" { provider = ibm.eu_gb }
data "ibm_is_flow_logs" "existing_au_syd" { provider = ibm.au_syd }
data "ibm_is_flow_logs" "existing_jp_tok" { provider = ibm.jp_tok }
data "ibm_is_flow_logs" "existing_jp_osa" { provider = ibm.jp_osa }

###############################################################################
# 5. Flow Log Collector – one per VPC, with explicit provider per region
#    Terraform requires static provider references, so one resource block
#    per region, each with its own for_each sub-map.
###############################################################################

resource "ibm_is_flow_log" "collectors_br_sao" {
  for_each = local.vpc_map_br_sao
  provider = ibm.br_sao

  name           = "flowlog-${each.value.vpc_name}"
  target         = each.value.vpc_id
  active         = true
  storage_bucket = ibm_cos_bucket.flow_logs.bucket_name

  depends_on = [ibm_iam_authorization_policy.flow_logs_to_cos]
}

resource "ibm_is_flow_log" "collectors_us_south" {
  for_each = local.vpc_map_us_south
  provider = ibm.us_south

  name           = "flowlog-${each.value.vpc_name}"
  target         = each.value.vpc_id
  active         = true
  storage_bucket = ibm_cos_bucket.flow_logs.bucket_name

  depends_on = [ibm_iam_authorization_policy.flow_logs_to_cos]
}

resource "ibm_is_flow_log" "collectors_us_east" {
  for_each = local.vpc_map_us_east
  provider = ibm.us_east

  name           = "flowlog-${each.value.vpc_name}"
  target         = each.value.vpc_id
  active         = true
  storage_bucket = ibm_cos_bucket.flow_logs.bucket_name

  depends_on = [ibm_iam_authorization_policy.flow_logs_to_cos]
}

resource "ibm_is_flow_log" "collectors_ca_tor" {
  for_each = local.vpc_map_ca_tor
  provider = ibm.ca_tor

  name           = "flowlog-${each.value.vpc_name}"
  target         = each.value.vpc_id
  active         = true
  storage_bucket = ibm_cos_bucket.flow_logs.bucket_name

  depends_on = [ibm_iam_authorization_policy.flow_logs_to_cos]
}

resource "ibm_is_flow_log" "collectors_eu_de" {
  for_each = local.vpc_map_eu_de
  provider = ibm.eu_de

  name           = "flowlog-${each.value.vpc_name}"
  target         = each.value.vpc_id
  active         = true
  storage_bucket = ibm_cos_bucket.flow_logs.bucket_name

  depends_on = [ibm_iam_authorization_policy.flow_logs_to_cos]
}

resource "ibm_is_flow_log" "collectors_eu_gb" {
  for_each = local.vpc_map_eu_gb
  provider = ibm.eu_gb

  name           = "flowlog-${each.value.vpc_name}"
  target         = each.value.vpc_id
  active         = true
  storage_bucket = ibm_cos_bucket.flow_logs.bucket_name

  depends_on = [ibm_iam_authorization_policy.flow_logs_to_cos]
}

resource "ibm_is_flow_log" "collectors_au_syd" {
  for_each = local.vpc_map_au_syd
  provider = ibm.au_syd

  name           = "flowlog-${each.value.vpc_name}"
  target         = each.value.vpc_id
  active         = true
  storage_bucket = ibm_cos_bucket.flow_logs.bucket_name

  depends_on = [ibm_iam_authorization_policy.flow_logs_to_cos]
}

resource "ibm_is_flow_log" "collectors_jp_tok" {
  for_each = local.vpc_map_jp_tok
  provider = ibm.jp_tok

  name           = "flowlog-${each.value.vpc_name}"
  target         = each.value.vpc_id
  active         = true
  storage_bucket = ibm_cos_bucket.flow_logs.bucket_name

  depends_on = [ibm_iam_authorization_policy.flow_logs_to_cos]
}

resource "ibm_is_flow_log" "collectors_jp_osa" {
  for_each = local.vpc_map_jp_osa
  provider = ibm.jp_osa

  name           = "flowlog-${each.value.vpc_name}"
  target         = each.value.vpc_id
  active         = true
  storage_bucket = ibm_cos_bucket.flow_logs.bucket_name

  depends_on = [ibm_iam_authorization_policy.flow_logs_to_cos]
}
