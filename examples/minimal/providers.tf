provider "azurerm" {
  features {}

  storage_use_azuread = true
  use_oidc            = true
}

# azapi drives the Microsoft.Web/connections resources; it authenticates exactly like azurerm
# (OIDC in CI, az CLI locally).
provider "azapi" {
  use_oidc = true
}
