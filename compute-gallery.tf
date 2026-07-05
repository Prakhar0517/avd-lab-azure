# Creates Shared Image Gallery
resource "azurerm_shared_image_gallery" "sig" {
  name                = "sig_${var.environment}_avd_${var.location_short}_001"
  resource_group_name = data.azurerm_resource_group.avd_rg.name
  location            = data.azurerm_resource_group.avd_rg.location
  description         = "Shared images"

  tags = {
    environment = local.env
    workload    = "avd"
  }
}

#Creates image definition

resource "azurerm_shared_image" "avd_image_def" {
  name                = "win11-avd-enterprise"
  gallery_name        = azurerm_shared_image_gallery.sig.name
  resource_group_name = data.azurerm_resource_group.avd_rg.name
  location            = data.azurerm_resource_group.avd_rg.location

  os_type             = "Windows"
  hyper_v_generation  = "V2"

  identifier {
    publisher = "lab"
    offer     = "avd"
    sku       = "win11-multisession"
  }

  description = "Windows 11 Enterprise multi-session AVD base image"

  tags = {
    environment = local.env
    workload    = "avd"
  }
}


