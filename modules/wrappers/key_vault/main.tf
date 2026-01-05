module "avm_kv" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "~> 0.10"

  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tenant_id           = var.tenant_id
  sku_name            = var.sku_name
  enable_telemetry   = false

  tags = var.tags
}
