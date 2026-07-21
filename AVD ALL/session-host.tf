resource "azurerm_windows_virtual_machine" "avd_vm" {
  count               = var.vm_count
  name                = format("vm-%s-%s-%s-%s-%02d", var.environment, var.project, var.workload, var.location_short, count.index + 1)
  computer_name       = format("avd%02d", count.index + 1)
  location            = azurerm_resource_group.avd_rg[0].location
  resource_group_name = azurerm_resource_group.avd_rg[0].name
  size                = var.vm_size

  admin_username = var.admin_username
  admin_password = azurerm_key_vault_secret.admin_password.value

  network_interface_ids = [
    azurerm_network_interface.avd_nic[count.index].id
  ]
  tags = local.common_tags


  # Required for Entra ID join — managed identity used by AADLoginForWindows
  identity {
    type = "SystemAssigned"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  # Golden image from the Shared Image Gallery, built by image-pipeline.yml.
  # Pinned via var.golden_image_version — see compute-gallery.tf.
  source_image_id = data.azurerm_shared_image_version.golden.id
}

# ── Entra ID Join Extension ───────────────────────────────────────────────────
# Replaces the old JsonADDomainExtension. Joins VMs directly to Entra ID
# (no domain controller, no adjoinuser account, no LDAP credentials needed).
resource "azurerm_virtual_machine_extension" "aad_join" {
  count                      = var.vm_count
  name                       = format("avd-sh-%02d-aadJoin", count.index + 1)
  virtual_machine_id         = azurerm_windows_virtual_machine.avd_vm[count.index].id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADLoginForWindows"
  type_handler_version       = "2.0"
  auto_upgrade_minor_version = true

  depends_on = [azurerm_windows_virtual_machine.avd_vm]
}

# ── AVD DSC Extension ─────────────────────────────────────────────────────────
# Registers session hosts with the AVD host pool using the registration token.
# Now depends on aad_join (previously depended on domain_join).
resource "azurerm_virtual_machine_extension" "vmext_dsc" {
  count                      = var.vm_count
  name                       = format("avd-dsc-%02d", count.index + 1)
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
    "HostPoolName": "${azurerm_virtual_desktop_host_pool.hp.name}",
    "aadJoin": true
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
    azurerm_virtual_machine_extension.aad_join,
    azurerm_virtual_desktop_host_pool_registration_info.reginfo
  ]

  lifecycle {
    ignore_changes = [protected_settings]
  }
}

# ── VM User Login Role Assignment ─────────────────────────────────────────────
# Required for Entra ID joined VMs — users must have this role to RDP in.
# On domain-joined VMs this was handled automatically by AD group membership.
resource "azurerm_role_assignment" "vm_user_login" {
  count                = var.vm_count
  scope                = azurerm_windows_virtual_machine.avd_vm[count.index].id
  role_definition_name = "Virtual Machine User Login"
  principal_id         = var.avd_users_group_object_id
}
