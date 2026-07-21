resource "azurerm_virtual_desktop_application_group" "rag" {
  name                = "rag-avd-demo"
  location            = azurerm_resource_group.avd_rg[0].location
  resource_group_name = azurerm_resource_group.avd_rg[0].name

  host_pool_id = azurerm_virtual_desktop_host_pool.hp.id
  type         = "RemoteApp"
}

resource "azurerm_virtual_desktop_application" "notepad" {
  name                         = "notepad"
  application_group_id         = azurerm_virtual_desktop_application_group.rag.id
  friendly_name                = "Notepad"
  path                         = "C:\\Windows\\System32\\notepad.exe"
  command_line_argument_policy = "DoNotAllow"
  show_in_portal               = true
}
resource "azurerm_virtual_desktop_workspace_application_group_association" "rag_assoc" {
  workspace_id         = azurerm_virtual_desktop_workspace.ws.id
  application_group_id = azurerm_virtual_desktop_application_group.rag.id
}
resource "azurerm_role_assignment" "rag_user_access" {
  scope                = azurerm_virtual_desktop_application_group.rag.id
  role_definition_name = "Desktop Virtualization User"
  principal_id         = "da25c46d-cb4f-4cfc-8536-1a52cfcfa94c"
}