
provider "azurerm" {
  features {
    key_vault {
      # Lab convenience: since purge_protection_enabled = false on the vault
      # (keyvault.tf), a destroy/recreate cycle would otherwise fail with a
      # "soft-deleted vault with this name already exists" name conflict.
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state" # changed from "avd"
    storage_account_name = "storageterraform0517"
    container_name       = "tfstate"
    key                  = "avd-demo.tfstate"
  }
}

resource "azurerm_virtual_desktop_workspace" "ws" {
  name                = "ws-avd-demo"
  location            = azurerm_resource_group.avd_rg[0].location
  resource_group_name = azurerm_resource_group.avd_rg[0].name
  friendly_name       = "Demo Workspace"
  tags                = local.common_tags
}

resource "azurerm_virtual_desktop_host_pool" "hp" {
  name                = "hp-avd-demo"
  location            = azurerm_resource_group.avd_rg[0].location
  resource_group_name = azurerm_resource_group.avd_rg[0].name

  type                     = "Pooled"
  load_balancer_type       = "BreadthFirst"
  maximum_sessions_allowed = 2

  start_vm_on_connect = true

  custom_rdp_properties = "enablecredsspsupport:i:1;videoplaybackmode:i:1;audiomode:i:0;devicestoredirect:s:*;drivestoredirect:s:;redirectclipboard:i:0;redirectcomports:i:1;redirectprinters:i:0;redirectsmartcards:i:1;redirectwebauthn:i:1;usbdevicestoredirect:s:;use multimon:i:1;enablerdsaadauth:i:1"
  tags                  = local.common_tags
}

resource "azurerm_virtual_desktop_application_group" "dag" {
  name                = "dag-avd-demo"
  location            = azurerm_resource_group.avd_rg[0].location
  resource_group_name = azurerm_resource_group.avd_rg[0].name

  host_pool_id = azurerm_virtual_desktop_host_pool.hp.id
  type         = "Desktop"
}

resource "azurerm_virtual_desktop_workspace_application_group_association" "assoc" {
  workspace_id         = azurerm_virtual_desktop_workspace.ws.id
  application_group_id = azurerm_virtual_desktop_application_group.dag.id
}

/*resource "azurerm_role_assignment" "avd_user_access" {
  scope                = azurerm_virtual_desktop_application_group.dag.id
  role_definition_name = "Desktop Virtualization User"
  principal_id         = "da25c46d-cb4f-4cfc-8536-1a52cfcfa94c"
}*/
