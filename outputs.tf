output "key_vault_id" {
  value = module.kv.resource_id
}

output "metric_alert_ids" {
  value = module.kv.metric_alert_ids
}
