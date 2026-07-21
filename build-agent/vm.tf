resource "azurerm_linux_virtual_machine" "build_agent" {
  name                = "vm-build-agent-01"
  computer_name       = "vm-build-agent-01"
  location            = azurerm_resource_group.build_agent.location
  resource_group_name = azurerm_resource_group.build_agent.name
  size                = "Standard_B2s"

  admin_username                  = "prakhar"
  disable_password_authentication = true

  admin_ssh_key {
    username   = "prakhar"
    public_key = var.admin_ssh_public_key
  }

  network_interface_ids = [
    azurerm_network_interface.agent_nic.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 64
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Grants read access to kv-avdlab-5mwdto (keyvault.tf) so cloud-init can
  # pull the agent PAT without any secret ever living in Terraform state or
  # this repo.
  identity {
    type = "SystemAssigned"
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
    vault_name      = "kv-avdlab-5mwdto"
    pat_secret_name = "ado-agent-pat"
    ado_org_url     = "https://dev.azure.com/prakhar0517"
    agent_pool      = "linux-build"
    agent_name      = "vm-build-agent-01"
  }))

  tags = local.common_tags
}

resource "azurerm_dev_test_global_vm_shutdown_schedule" "build_agent_shutdown" {
  virtual_machine_id = azurerm_linux_virtual_machine.build_agent.id
  location           = azurerm_resource_group.build_agent.location
  enabled            = true

  daily_recurrence_time = "2300"
  timezone              = "India Standard Time"

  notification_settings {
    enabled = false
  }

  tags = local.common_tags
}
