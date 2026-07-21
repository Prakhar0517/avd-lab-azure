# Creates Shared Image Gallery
resource "azurerm_shared_image_gallery" "sig" {
  name                = "sig_${var.environment}_avd_${var.location_short}_001"
  resource_group_name = azurerm_resource_group.avd_rg[0].name
  location            = azurerm_resource_group.avd_rg[0].location
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
  resource_group_name = azurerm_resource_group.avd_rg[0].name
  location            = azurerm_resource_group.avd_rg[0].location

  os_type            = "Windows"
  hyper_v_generation = "V2"

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

# Pins the golden image version session hosts deploy from. Looking this up
# as a data source (rather than a bare version string on the VM resource)
# means a typo'd or not-yet-built version fails at `terraform plan`, not
# mid-apply after the first few VMs are already replaced.
data "azurerm_shared_image_version" "golden" {
  name                = var.golden_image_version
  image_name          = azurerm_shared_image.avd_image_def.name
  gallery_name        = azurerm_shared_image_gallery.sig.name
  resource_group_name = azurerm_resource_group.avd_rg[0].name
}


