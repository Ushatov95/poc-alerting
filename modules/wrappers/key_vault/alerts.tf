locals {
  # ---------------------------------------------------------------------------
  # Basic monitoring inputs (application-team config)
  # ---------------------------------------------------------------------------
  monitoring_enabled = try(var.monitoring.enabled, false)
  profile            = lower(try(var.monitoring.profile, "prod"))
  # profile = try(var.monitoring.profile, lower(try(var.tags.env, "prod"))) # alternative: env-based profiles instead of explicit specifying

  # Attach one or many action groups to each alert rule.
  # Using a set ensures stable ordering in plans
  action_group_ids   = toset(try(var.monitoring.action_group_ids, []))

  # Where the ALERT RULE resources are created.
  # This is independent from the Key Vault resource group.
  alerts_rg_name = coalesce(try(var.monitoring.resource_group_name, null), var.resource_group_name)

  # ---------------------------------------------------------------------------
  # Important Terraform nuance:
  # monitoring.overrides is typed as map(object(... optional attributes ...)).
  # When a caller sets only one field (e.g., threshold), other optional fields
  # may become "null" and would overwrite the baseline if we merge() directly.
  #
  # To prevent baseline values being overwritten by nulls, we strip nulls from
  # each override object before merge().
  # ---------------------------------------------------------------------------
  overrides_raw = try(var.monitoring.overrides, {})
  overrides = {
    for alert_name, o in local.overrides_raw :
    alert_name => { for k, v in o : k => v if v != null }
  }

  # ---------------------------------------------------------------------------
  # AMBA-aligned Key Vault metric alert definitions (excluding Activity Log alerts)
  #
  # Keys here are the ONLY names application teams need to reference in overrides:
  # - Availability
  # - SaturationShoebox
  # - ServiceApiHit
  # - ServiceApiLatency
  # - ServiceApiResult
  #
  # Each alert is represented as a flat object so we can safely merge overrides.
  # ---------------------------------------------------------------------------
  amba_kv = {
    Availability = {
      mode          = "static"
      enabled       = true
      severity      = 1
      frequency     = "PT1M"
      window_size   = "PT5M"
      auto_mitigate = false
      description   = "Vault requests availability"

      metric_namespace = "Microsoft.KeyVault/vaults"
      metric_name      = "Availability"
      aggregation      = "Average"
      operator         = "LessThan"
      threshold        = 90
    }

    SaturationShoebox = {
      mode          = "static"
      enabled       = true
      severity      = 1
      frequency     = "PT1M"
      window_size   = "PT5M"
      auto_mitigate = false
      description   = "Vault capacity used"

      metric_namespace = "Microsoft.KeyVault/vaults"
      metric_name      = "SaturationShoebox"
      aggregation      = "Average"
      operator         = "GreaterThan"
      threshold        = 75
    }

    ServiceApiHit = {
      mode          = "static"
      enabled       = true
      severity      = 3
      frequency     = "PT5M"
      window_size   = "PT5M"
      auto_mitigate = false
      description   = "Number of total service api hits"

      metric_namespace = "Microsoft.KeyVault/vaults"
      metric_name      = "ServiceApiHit"
      aggregation      = "Average"
      operator         = "GreaterThanOrEqual"
      threshold        = 80
    }

    ServiceApiLatency = {
      mode          = "static"
      enabled       = true
      severity      = 3
      frequency     = "PT5M"
      window_size   = "PT5M"
      auto_mitigate = false
      description   = "Overall latency of service api requests"

      metric_namespace = "Microsoft.KeyVault/vaults"
      metric_name      = "ServiceApiLatency"
      aggregation      = "Average"
      operator         = "GreaterThan"
      threshold        = 1000
    }

    ServiceApiResult = {
      mode          = "dynamic"
      enabled       = true
      severity      = 2
      frequency     = "PT5M"
      window_size   = "PT5M"
      auto_mitigate = false
      description   = "Number of total service api results"

      metric_namespace         = "Microsoft.KeyVault/vaults"
      metric_name              = "ServiceApiResult"
      aggregation              = "Average"
      operator                 = "GreaterThan"
      alert_sensitivity        = "Medium"
      evaluation_total_count   = 4
      evaluation_failure_count = 4
    }
  }

  # ---------------------------------------------------------------------------
  # Profiles define environment defaults (dev/test/prod) without changing
  # the underlying AMBA definitions. Keep this small and predictable.
  # ---------------------------------------------------------------------------
  profile_overrides = {
    dev = {
      # Reduce noise in development environments.
      SaturationShoebox = { enabled = false }
      ServiceApiHit     = { enabled = false }
    }
    test = {
      # Test still wants core health signals, but typically less traffic noise.
      ServiceApiHit = { enabled = false }
    }
    prod = {
      # Production uses AMBA defaults
    }
  }

  overlay_raw = lookup(local.profile_overrides, local.profile, {})
  overlay     = { for alert_name, o in local.overrides_raw : alert_name => { for k, v in o : k => v if v != null } }

  # ---------------------------------------------------------------------------
  # Merge order (lowest to highest precedence):
  # 1) AMBA baseline (platform-owned)
  # 2) profile override (dev/test/prod defaults)
  # 3) application override (per-deployment tuning)
  # ---------------------------------------------------------------------------
  merged = {
    for alert_name, base in local.amba_kv :
    alert_name => merge(
      base,
      lookup(local.overlay, alert_name, {}),
      try(local.overrides[alert_name], {})
    )
  }

  # If monitoring is off, create no alert rules at all.
  # If monitoring is on, create the full set (and use each.value.enabled to enable/disable).
  effective = local.monitoring_enabled ? local.merged : {}
}

resource "azurerm_monitor_metric_alert" "kv" {
  for_each = local.effective

  name                = "alert-${var.name}-${each.key}"
  resource_group_name = local.alerts_rg_name
  scopes              = [module.avm_kv.resource_id]

  description   = try(each.value.description, null)
  severity      = each.value.severity
  enabled       = coalesce(try(each.value.enabled, null), true)
  frequency     = each.value.frequency
  window_size   = each.value.window_size
  auto_mitigate = each.value.auto_mitigate

  target_resource_type     = "Microsoft.KeyVault/vaults"
  target_resource_location = var.location

  dynamic "criteria" {
    for_each = each.value.mode == "static" ? [1] : []
    content {
      metric_namespace = each.value.metric_namespace
      metric_name      = each.value.metric_name
      aggregation      = each.value.aggregation
      operator         = each.value.operator
      threshold        = each.value.threshold
    }
  }

  dynamic "dynamic_criteria" {
    for_each = each.value.mode == "dynamic" ? [1] : []
    content {
      metric_namespace         = each.value.metric_namespace
      metric_name              = each.value.metric_name
      aggregation              = each.value.aggregation
      operator                 = each.value.operator
      alert_sensitivity        = each.value.alert_sensitivity
      evaluation_total_count   = each.value.evaluation_total_count
      evaluation_failure_count = each.value.evaluation_failure_count
    }
  }

  dynamic "action" {
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }

  tags = merge(var.tags, {
    managed_by    = "terraform"
    alert_profile = local.profile
    alert_name    = each.key
  })
}