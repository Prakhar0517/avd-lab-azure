# The AVD resource group lives in "AVD ALL/"'s state. This stack must stay
# independent of that state, so it's referenced here purely by its known
# name via a data source - not a remote-state or output reference.
data "azurerm_resource_group" "avd" {
  name = "rg-test-tf-rg-demo-avd-eus"
}

# Lets Packer build/capture images using the agent's system-assigned Managed
# Identity instead of the retired packer-local-test-sp secret (root
# CLAUDE.md, Hard-Won Lesson 11 epilogue).
resource "azurerm_role_assignment" "agent_avd_rg_contributor" {
  scope                = data.azurerm_resource_group.avd.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_linux_virtual_machine.build_agent.identity[0].principal_id
}
