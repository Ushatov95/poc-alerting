provider "azurerm" {
  features {}

  # Make local testing deterministic.
  subscription_id = var.subscription_id
}
