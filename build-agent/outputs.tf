output "public_ip_address" {
  description = "Public IP address of vm-build-agent-01"
  value       = azurerm_public_ip.agent_pip.ip_address
}

output "principal_id" {
  description = "Object ID of the VM's system-assigned managed identity — grant this access to any other resource the agent needs (additional Key Vaults, ACR, etc.)"
  value       = azurerm_linux_virtual_machine.build_agent.identity[0].principal_id
}
