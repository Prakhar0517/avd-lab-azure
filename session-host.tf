resource "azurerm_windows_virtual_machine" "avd_vm" {
  count = var.vm_count
  name                = "avd-sh-0${count.index + 1}"
  location            = data.azurerm_resource_group.avd_rg.location
  resource_group_name = data.azurerm_resource_group.avd_rg.name
  size = var.vm_size

  admin_username = var.admin_username
  admin_password = var.admin_password

  network_interface_ids = [
    azurerm_network_interface.avd_nic[count.index].id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "windows-11"
    sku       = "win11-22h2-avd"
    version   = "latest"
  }

  tags = {
    workload = "avd"
    role     = "session-host"
  }
}


resource "azurerm_virtual_machine_extension" "vmext_dsc" {
  count = var.vm_count
  name                       = "avd-dsc-0${count.index + 1}"
  virtual_machine_id         = azurerm_windows_virtual_machine.avd_vm[count.index].id
  publisher                  = "Microsoft.Powershell"
  type                       = "DSC"
  type_handler_version       = "2.73"
  auto_upgrade_minor_version = true

  settings = <<SETTINGS
{
  "modulesUrl": "https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_1.0.02714.342.zip",
  "configurationFunction": "Configuration.ps1\\AddSessionHost",
  "properties": {
    "HostPoolName": "${azurerm_virtual_desktop_host_pool.hp.name}"
  }
}
SETTINGS

  protected_settings = <<PROTECTED_SETTINGS
{
  "properties": {
    "registrationInfoToken": "${azurerm_virtual_desktop_host_pool_registration_info.reginfo.token}"
  }
}
PROTECTED_SETTINGS

  depends_on = [
    azurerm_virtual_machine_extension.domain_join,
    azurerm_virtual_desktop_host_pool_registration_info.reginfo
  ]

  lifecycle {
    ignore_changes = [protected_settings]
  }
}

 
resource "azurerm_virtual_machine_extension" "domain_join" {
  count = var.vm_count
  name                 = "avd-sh-0${count.index + 1}-domainJoin"
  virtual_machine_id   = azurerm_windows_virtual_machine.avd_vm[count.index].id
  publisher            = "Microsoft.Compute"
  type                 = "JsonADDomainExtension"
  type_handler_version = "1.3"
  auto_upgrade_minor_version = true

  settings = <<SETTINGS
{
  "Name": "${var.domain_name}",
  "OUPath": "${var.ou_path}",
  "User": "${var.domain_user_upn}@${var.domain_name}",
  "Restart": "true",
  "Options": "3"
}
SETTINGS

  protected_settings = <<PROTECTED_SETTINGS
{
  "Password": "${var.domain_password}"
}
PROTECTED_SETTINGS
}

/*resource "azurerm_virtual_machine_extension" "fslogix_config" {
  count = var.vm_count
  name                 = "fslogix-config-${count.index}"
  virtual_machine_id   = azurerm_windows_virtual_machine.avd_vm[count.index].id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = <<SETTINGS
{
  "commandToExecute": "powershell -ExecutionPolicy Unrestricted -Command \"New-Item -Path 'HKLM:\\SOFTWARE\\FSLogix\\Profiles' -Force; Set-ItemProperty -Path 'HKLM:\\SOFTWARE\\FSLogix\\Profiles' -Name 'Enabled' -Value 1; Set-ItemProperty -Path 'HKLM:\\SOFTWARE\\FSLogix\\Profiles' -Name 'VHDLocations' -Value '\\\\\\\\${azurerm_storage_account.fslogix.name}.file.core.windows.net\\\\fslogix';\""
}
SETTINGS

  depends_on = [
    azurerm_storage_share.fslogix_share
  ]
}*/

