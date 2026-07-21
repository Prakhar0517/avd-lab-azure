# The vault lives in rg-terraform-state, created by "AVD ALL/" (see its
# keyvault.tf). This stack must stay independent of "AVD ALL/" state, so it's
# referenced here purely by its known name/RG via a data source — not a
# remote-state or output reference.
data "azurerm_key_vault" "avd_secrets" {
  name                = "kv-avdlab-5mwdto"
  resource_group_name = "rg-terraform-state"
}

# AVD ALL's vault has rbac_authorization_enabled = true (RBAC, not access
# policies) — mirror that authorization model here rather than adding an
# access policy.
resource "azurerm_role_assignment" "agent_kv_secrets_user" {
  scope                = data.azurerm_key_vault.avd_secrets.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_virtual_machine.build_agent.identity[0].principal_id
}
