output "cos_instance_id" {
  description = "CRN of the central COS instance that holds all regional flow log buckets."
  value       = local.cos_instance_id
}

output "cos_buckets" {
  description = "Map of region → COS bucket name created for flow log storage."
  value       = { for region, bucket in ibm_cos_bucket.flow_logs : region => bucket.bucket_name }
}

output "iam_authorization_policy_id" {
  description = "ID of the account-level IAM authorization (Flow Log Collector → COS Writer)."
  value       = ibm_iam_authorization_policy.flow_logs_to_cos.id
}

output "flow_log_collectors" {
  description = "Map of '<region>/<vpc-id>' → collector ID for every VPC enrolled."
  value       = { for key, col in ibm_is_flow_log.collectors : key => col.id }
}

output "flow_log_collectors_count" {
  description = "Total number of Flow Log Collectors created across all regions."
  value       = length(ibm_is_flow_log.collectors)
}

output "vpcs_discovered" {
  description = "Map of '<region>/<vpc-id>' → VPC name for every VPC found during the run."
  value       = { for key, vpc in local.vpc_map : key => vpc.vpc_name }
}
