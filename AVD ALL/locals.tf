locals {
  rg_name = format(
    "rg-%s-%s-%s-%s",
    var.environment,
    var.project,
    var.workload,
    var.location_short
  )

  env      = var.environment
  location = var.location_short
}

locals {
  common_tags = merge(
    var.tags,
    {
      project     = var.project
      environment = var.environment
      workload    = var.workload
    }
  )
}

resource "azurerm_resource_group" "avd_rg" {
  count    = var.create_rg ? 1 : 0
  name     = local.rg_name
  location = var.location

  tags = local.common_tags
}