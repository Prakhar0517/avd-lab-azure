resource "azurerm_public_ip" "image_builder_pip" {
  name                = "pip_${var.environment}_img_${var.location_short}_001"
  location            = data.azurerm_resource_group.avd_rg.location
  resource_group_name = data.azurerm_resource_group.avd_rg.name

  allocation_method = "Static"
  sku               = "Standard"

  tags = {
    workload = "image-builder"
  }

}
resource "azurerm_network_interface" "image_builder_nic" {
  name                = "nic_${var.environment}_img_${var.location_short}_001"
  location            = data.azurerm_resource_group.avd_rg.location
  resource_group_name = data.azurerm_resource_group.avd_rg.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.avd_session_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.image_builder_pip.id
  }

  tags = {
    workload = "image-builder"
  }
}

resource "azurerm_windows_virtual_machine" "image_builder" {

  name                = "img-${var.environment}-avd-${var.location_short}-001"
  computer_name       = "imgavd01"
  location            = data.azurerm_resource_group.avd_rg.location
  resource_group_name = data.azurerm_resource_group.avd_rg.name

  size = "Standard_B2s"

  admin_username = var.admin_username
  admin_password = var.admin_password

  network_interface_ids = [
    azurerm_network_interface.image_builder_nic.id
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
    workload = "image-builder"
  }
}

resource "azurerm_virtual_machine_extension" "image_builder_domain_join" {

  name                 = "img-${var.environment}-domainJoin"
  virtual_machine_id   = azurerm_windows_virtual_machine.image_builder.id
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