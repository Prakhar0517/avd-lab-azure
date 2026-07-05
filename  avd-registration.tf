resource "azurerm_virtual_desktop_host_pool_registration_info" "reginfo" {
  hostpool_id     = azurerm_virtual_desktop_host_pool.hp.id
  expiration_date = timeadd(timestamp(), "24h")

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [expiration_date]
  }
}