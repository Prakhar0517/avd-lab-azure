output "location_short" {
  description = "The Azure region"
  value       = data.azurerm_resource_group.avd_rg.location
}

/*output "Compute_Gallery" {
  description = "Azure Compute Gallery"
  value       = azurerm_shared_image_gallery.sig.name
}*/

output "azure_virtual_desktop_host_pool" {
  description = "Name of the Azure Virtual Desktop host pool"
  value       = azurerm_virtual_desktop_host_pool.hp.name
}

output "azurerm_virtual_desktop_application_group" {
  description = "Name of the Azure Virtual Desktop DAG"
  value       = azurerm_virtual_desktop_application_group.dag.name
}

output "azurerm_virtual_desktop_workspace" {
  description = "Name of the Azure Virtual Desktop workspace"
  value       = azurerm_virtual_desktop_workspace.ws.name
}

output "session_host_count" {
  description = "The number of VMs created"
  value       = var.vm_count
}

output "dnsservers" {
  description = "Custom DNS configuration"
  value       = azurerm_virtual_network.avd_vnet.dns_servers
}

/*output "vnetrange" {
  description = "Address range for deployment vnet"
  value       = data.azurerm_virtual_network.vnet.address_space
}*/


output "gallery_id" {
  value = azurerm_shared_image_gallery.sig.id
}

output "image_definition_id" {
  value = azurerm_shared_image.avd_image_def.id
}
