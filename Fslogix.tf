resource "random_string" "fs" {
  length  = 4
  upper   = false
  special = false
}

resource "azurerm_storage_account" "fslogix" {
  name                     = "stfslogix${random_string.fs.result}"
  resource_group_name      = data.azurerm_resource_group.avd_rg.name
  location                 = data.azurerm_resource_group.avd_rg.location

  account_tier             = "Standard"  
  account_replication_type = "LRS"

  tags = {
    workload = "avd"
    purpose  = "fslogix"
  }

  lifecycle {
   ignore_changes = [
     azure_files_authentication
   ]
  }
}


resource "azurerm_storage_share" "fslogix_share" {
  name                 = "fslogix"
  storage_account_id = azurerm_storage_account.fslogix.id
  quota                = 50
}

#resource "azurerm_role_assignment" "fslogix_access" {
#  scope                = azurerm_storage_account.fslogix.id
#  role_definition_name = "Storage File Data SMB Share Contributor"
#  principal_id         = "da25c46d-cb4f-4cfc-8536-1a52cfcfa94c"
#}

