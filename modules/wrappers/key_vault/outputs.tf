output "resource_id" {
  value = module.avm_kv.resource_id
}

output "metric_alert_ids" {
  value = { for k, v in azurerm_monitor_metric_alert.kv : k => v.id }
}
