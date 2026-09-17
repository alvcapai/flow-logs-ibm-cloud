output "resource_group_id" {
  description = "Resolved hex ID of the resource group used for all resources."
  value       = data.ibm_resource_group.target.id
}

output "cos_instance_id" {
  description = "CRN of the central COS instance that holds all regional flow log buckets."
  value       = local.cos_instance_id
}

output "cos_bucket" {
  description = "Name of the single account-level COS bucket used for all flow log storage."
  value       = ibm_cos_bucket.flow_logs.bucket_name
}

output "iam_authorization_policy_id" {
  description = "ID of the account-level IAM authorization (Flow Log Collector → COS Writer)."
  value       = ibm_iam_authorization_policy.flow_logs_to_cos.id
}

output "flow_log_collectors" {
  description = "Map of '<region>/<vpc-id>' → collector ID for every VPC enrolled by this run."
  value = merge(
    { for k, v in ibm_is_flow_log.collectors_br_sao   : k => v.id },
    { for k, v in ibm_is_flow_log.collectors_us_south : k => v.id },
    { for k, v in ibm_is_flow_log.collectors_us_east  : k => v.id },
    { for k, v in ibm_is_flow_log.collectors_ca_tor   : k => v.id },
    { for k, v in ibm_is_flow_log.collectors_eu_de    : k => v.id },
    { for k, v in ibm_is_flow_log.collectors_eu_gb    : k => v.id },
    { for k, v in ibm_is_flow_log.collectors_au_syd   : k => v.id },
    { for k, v in ibm_is_flow_log.collectors_jp_tok   : k => v.id },
    { for k, v in ibm_is_flow_log.collectors_jp_osa   : k => v.id },
  )
}

output "flow_log_collectors_count" {
  description = "Number of Flow Log Collectors created by this run (excludes pre-existing ones)."
  value = (
    length(ibm_is_flow_log.collectors_br_sao)   +
    length(ibm_is_flow_log.collectors_us_south) +
    length(ibm_is_flow_log.collectors_us_east)  +
    length(ibm_is_flow_log.collectors_ca_tor)   +
    length(ibm_is_flow_log.collectors_eu_de)    +
    length(ibm_is_flow_log.collectors_eu_gb)    +
    length(ibm_is_flow_log.collectors_au_syd)   +
    length(ibm_is_flow_log.collectors_jp_tok)   +
    length(ibm_is_flow_log.collectors_jp_osa)
  )
}

output "vpcs_discovered" {
  description = "Map of '<region>/<vpc-id>' → VPC name for every VPC found during the run."
  value       = { for key, vpc in local.vpc_map_all : key => vpc.vpc_name }
}

output "vpcs_skipped" {
  description = "VPC IDs skipped because they already have a Flow Log Collector."
  value       = local.existing_collector_targets
}
