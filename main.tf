terraform {
  backend "azurerm" {
    resource_group_name  = "avd"
    storage_account_name = "storageterraform0517"
    container_name       = "tfstate"
    key                  = "avd-demo.tfstate"
  }
}

provider "azurerm" {
  features {}
}

data "azurerm_resource_group" "avd_rg" {
  name = "avd"
}

resource "azurerm_virtual_desktop_workspace" "ws" {
  name                = "ws-avd-demo"
  location            = data.azurerm_resource_group.avd_rg.location
  resource_group_name = data.azurerm_resource_group.avd_rg.name
  friendly_name       = "Demo Workspace"
}

resource "azurerm_virtual_desktop_host_pool" "hp" {
  name                = "hp-avd-demo"
  location            = data.azurerm_resource_group.avd_rg.location
  resource_group_name = data.azurerm_resource_group.avd_rg.name

  type                     = "Pooled"
  load_balancer_type       = "BreadthFirst"
  maximum_sessions_allowed = 10
  
  start_vm_on_connect = true

  custom_rdp_properties = "enablecredsspsupport:i:1;videoplaybackmode:i:1;audiomode:i:0;devicestoredirect:s:*;drivestoredirect:s:;redirectclipboard:i:0;redirectcomports:i:1;redirectprinters:i:0;redirectsmartcards:i:1;redirectwebauthn:i:1;usbdevicestoredirect:s:;use multimon:i:1;enablerdsaadauth:i:1"

}

resource "azurerm_virtual_desktop_application_group" "dag" {
  name                = "dag-avd-demo"
  location            = data.azurerm_resource_group.avd_rg.location
  resource_group_name = data.azurerm_resource_group.avd_rg.name

  host_pool_id = azurerm_virtual_desktop_host_pool.hp.id
  type         = "Desktop"
}

resource "azurerm_virtual_desktop_workspace_application_group_association" "assoc" {
  workspace_id         = azurerm_virtual_desktop_workspace.ws.id
  application_group_id = azurerm_virtual_desktop_application_group.dag.id
}

resource "azurerm_role_assignment" "avd_user_access" {
  scope                = azurerm_virtual_desktop_application_group.dag.id
  role_definition_name = "Desktop Virtualization User"
  principal_id         = "da25c46d-cb4f-4cfc-8536-1a52cfcfa94c"
}
