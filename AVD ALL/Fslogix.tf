# ── FSLogix Storage Account ───────────────────────────────────────────────────
# Azure Files with Azure AD Kerberos (AADKERB) authentication.
# This replaces traditional AD DS Kerberos — no domain controller needed.
resource "random_string" "fs" {
  length  = 4
  upper   = false
  special = false
}

resource "azurerm_storage_account" "fslogix" {
  name                     = "stfslogix${random_string.fs.result}"
  resource_group_name      = azurerm_resource_group.avd_rg[0].name
  location                 = azurerm_resource_group.avd_rg[0].location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # AADKERB = Azure AD Kerberos — users authenticate to the file share
  # using their Entra ID credentials. No AD DS or DC required.
  azure_files_authentication {
    directory_type = "AADKERB"
  }

  tags = local.common_tags
}

# ── FSLogix File Share ────────────────────────────────────────────────────────
resource "azurerm_storage_share" "fslogix_share" {
  name               = "fslogix"
  storage_account_id = azurerm_storage_account.fslogix.id
  quota              = 75
}

# ── FSLogix RBAC ──────────────────────────────────────────────────────────────
# AVD users need SMB Share Contributor to read/write their FSLogix profile VHDs.
# Previously this was managed via AD group membership + traditional Kerberos.
/*resource "azurerm_role_assignment" "fslogix_share_access" {
  scope                = azurerm_storage_account.fslogix.id
  role_definition_name = "Storage File Data SMB Share Contributor"
  principal_id         = var.avd_users_group_object_id
}*/