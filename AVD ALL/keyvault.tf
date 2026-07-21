# ── Secrets Management: Azure Key Vault ─────────────────────────────────────
# Lives in rg-terraform-state (the same RG as the backend storage account),
# NOT in the AVD resource group. That RG isn't managed by this Terraform
# config (it's the pre-existing backend bootstrap RG — same reasoning as the
# "avd" RG note in CLAUDE.md), so it's referenced via a data source rather
# than created here. Keeping the vault out of azurerm_resource_group.avd_rg
# means it survives `terraform destroy` / recreation cycles of the AVD stack.

data "azurerm_resource_group" "tfstate" {
  name = "rg-terraform-state"
}

data "azurerm_client_config" "current" {}

resource "random_string" "kv_suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_key_vault" "avd_secrets" {
  name                = "kv-avdlab-${random_string.kv_suffix.result}"
  resource_group_name = data.azurerm_resource_group.tfstate.name
  location            = data.azurerm_resource_group.tfstate.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  rbac_authorization_enabled = true

  # Lab environment: no purge protection, so the vault/secrets can be purged
  # immediately instead of sitting in soft-delete for the retention window.
  # Soft delete itself can't be disabled (Azure requirement), so it's set to
  # the minimum allowed retention.
  purge_protection_enabled   = false
  soft_delete_retention_days = 7

  tags = local.common_tags
}

# ── RBAC: who can read/write secrets in this vault ──────────────────────────
# Both grants are needed for the "no human ever types a password" goal:
#  - the pipeline's SP writes the generated secret and reads it back into the
#    VM resource on every apply
#  - my own account can read it out-of-band (e.g. `az keyvault secret show`)
#    without ever having generated or typed it myself

resource "azurerm_role_assignment" "kv_secrets_officer_user" {
  scope                = azurerm_key_vault.avd_secrets.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.keyvault_admin_object_id
}

resource "azurerm_role_assignment" "kv_secrets_officer_pipeline" {
  scope                = azurerm_key_vault.avd_secrets.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.pipeline_sp_object_id
}

# Azure RBAC role assignments are eventually consistent — the pipeline SP's
# own "Key Vault Secrets Officer" grant above can take up to ~30s to actually
# take effect. Without this, the very first apply that creates the vault,
# grants the role, AND writes the secret in one run can 403 on the secret
# write because the grant hasn't propagated yet. Every apply after the first
# is unaffected (role assignment already exists, nothing to wait on), but
# this keeps the "vault + secret + VMs in the same apply" path reliable.
resource "time_sleep" "kv_rbac_propagation" {
  create_duration = "30s"

  depends_on = [
    azurerm_role_assignment.kv_secrets_officer_user,
    azurerm_role_assignment.kv_secrets_officer_pipeline,
  ]
}

# ── Secret: Terraform generates it, nobody ever knows or types it ──────────

resource "random_password" "admin_password" {
  length      = 24
  special     = true
  min_upper   = 2
  min_lower   = 2
  min_numeric = 2
  min_special = 2

  # Azure VM local admin passwords reject a handful of characters; keep the
  # special-character set to ones Azure actually accepts.
  override_special = "!@#$%^&*()-_=+"
}

resource "azurerm_key_vault_secret" "admin_password" {
  name         = "admin-password"
  value        = random_password.admin_password.result
  key_vault_id = azurerm_key_vault.avd_secrets.id

  depends_on = [time_sleep.kv_rbac_propagation]
}
