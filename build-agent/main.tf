provider "azurerm" {
  features {}
}

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.80"
    }
  }

  # Independent state from "AVD ALL/" — same backend storage account/container,
  # different key, so this stack can be applied/destroyed without touching the
  # AVD stack's state.
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "storageterraform0517"
    container_name       = "tfstate"
    key                  = "build-agent.tfstate"
  }
}

resource "azurerm_resource_group" "build_agent" {
  name     = "rg-build-agent-eus"
  location = var.location

  tags = local.common_tags
}
