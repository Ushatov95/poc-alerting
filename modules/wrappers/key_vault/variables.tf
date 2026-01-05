variable "name" {
  description = "Key Vault name (must be globally unique)."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group where the Key Vault itself is deployed."
  type        = string
}

variable "location" {
  description = "Azure region for the Key Vault."
  type        = string
}

variable "tenant_id" {
  description = "Tenant ID for the Key Vault."
  type        = string
}

variable "sku_name" {
  description = "Key Vault SKU: standard or premium."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.sku_name)
    error_message = "sku_name must be standard or premium."
  }
}

variable "tags" {
  description = "Tags applied to Key Vault and alert rules."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Application-team-facing monitoring contract (kept intentionally small)
#
# Key design goals:
# - The application team should NOT have to understand metric namespaces,
#   alert criteria schemas, dynamic thresholds, etc.
# - They only decide:
#   1) whether monitoring is enabled
#   2) where notifications go (Action Group IDs)
#   3) which profile to use (dev/test/prod)
#   4) optional per-alert tuning (threshold/severity/enabled)
# -----------------------------------------------------------------------------
variable "monitoring" {
  description = <<DESC
Monitoring configuration for this Key Vault.

Example:
monitoring = {
  enabled             = true
  profile             = "prod"
  action_group_ids    = [data.azurerm_monitor_action_group.team.id]
  resource_group_name = "rg-monitoring" # optional (where alert RULES are created)
  overrides = {
    ServiceApiLatency = { threshold = 1500 }
    ServiceApiHit     = { enabled = false }
  }
}
DESC

  type = object({
    enabled = optional(bool, false)

    # Profiles define default enablement / noise reduction without changing alert definitions.
    # Implemented in alerts.tf via local.profile_overrides.
    profile = optional(string, "prod") # dev|test|prod

    # Action group IDs attached to ALL alerts created by this wrapper.
    action_group_ids = optional(set(string), [])

    # Where the alert RULE resources are created (commonly a central monitoring RG).
    # If omitted, defaults to the workload resource_group_name.
    resource_group_name = optional(string)

    # Per-alert overrides keyed by alert name (e.g., "ServiceApiLatency").
    # Only set the fields you actually want to change.
    overrides = optional(map(object({
      enabled     = optional(bool)
      severity    = optional(number) # 0..4
      frequency   = optional(string) # ISO8601 duration e.g. PT5M
      window_size = optional(string) # ISO8601 duration e.g. PT15M
      threshold   = optional(number) # static criteria only
      operator    = optional(string) # static criteria only
      description = optional(string)

      # Dynamic threshold options (used by ServiceApiResult in AMBA)
      alert_sensitivity        = optional(string) # Low|Medium|High
      evaluation_total_count   = optional(number)
      evaluation_failure_count = optional(number)
    })), {})
  })

  default = {}

  validation {
    condition     = contains(["dev", "test", "prod"], lower(try(var.monitoring.profile, "prod")))
    error_message = "monitoring.profile must be one of: dev, test, prod."
  }

  validation {
    condition     = try(var.monitoring.enabled, false) == false || length(try(var.monitoring.action_group_ids, [])) > 0
    error_message = "When monitoring.enabled=true, monitoring.action_group_ids must be non-empty."
  }
}
