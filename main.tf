data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "workload" {
  name     = var.workload_rg_name
  location = var.location
}

resource "azurerm_resource_group" "monitoring" {
  name     = var.monitoring_rg_name
  location = var.location
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# Action Group (team-owned in real life; POC creates it here)
resource "azurerm_monitor_action_group" "team" {
  name                = "ag-poc-kv-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.monitoring.name
  short_name          = "pockv"

  email_receiver {
    name          = "oncall"
    email_address = var.notification_email
  }
}

# Key Vault wrapper (wraps AVM) + alerts INSIDE the wrapper
module "kv" {
  source = "./modules/wrappers/key_vault"

  name                = "kvpoc${random_string.suffix.result}" # KV names must be globally unique
  resource_group_name = azurerm_resource_group.workload.name
  location            = var.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  tags = {}

  # Simplified, app-friendly monitoring contract
  monitoring = {
    enabled          = true
    profile          = var.monitoring_profile
    action_group_ids = [azurerm_monitor_action_group.team.id]
    resource_group_name = azurerm_resource_group.monitoring.name

    # Optional tuning. App teams only touch thresholds/enabled/severity if needed.
    overrides = {
      # Example:
      # ServiceApiLatency = { threshold = 1500, severity = 2, operator = "LessThan" }
      # ServiceApiHit     = { enabled  = true }
    }
  }
}
