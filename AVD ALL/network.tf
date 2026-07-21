# ── Virtual Network ───────────────────────────────────────────────────────────
# No custom DNS servers needed — Entra ID joined VMs use Azure default DNS.
# Previously pointed at dc-01 (10.10.0.4) for domain resolution.
resource "azurerm_virtual_network" "avd_vnet" {
  name                = "vnet-avd-demo"
  location            = azurerm_resource_group.avd_rg[0].location
  resource_group_name = azurerm_resource_group.avd_rg[0].name
  address_space       = ["10.10.0.0/16"]

  tags = local.common_tags
}

# ── Subnet ────────────────────────────────────────────────────────────────────
resource "azurerm_subnet" "avd_session_subnet" {
  name                 = "subnet-avd-session-hosts"
  resource_group_name  = azurerm_resource_group.avd_rg[0].name
  virtual_network_name = azurerm_virtual_network.avd_vnet.name
  address_prefixes     = ["10.10.1.0/24"]
}

# ── Network Interfaces ────────────────────────────────────────────────────────
resource "azurerm_network_interface" "avd_nic" {
  count               = var.vm_count
  name                = format("nic-avd-sh-%02d", count.index + 1)
  location            = azurerm_resource_group.avd_rg[0].location
  resource_group_name = azurerm_resource_group.avd_rg[0].name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.avd_session_subnet.id
    private_ip_address_allocation = "Dynamic"
  }

  tags = local.common_tags
}

# ── Network Security Group ────────────────────────────────────────────────────
resource "azurerm_network_security_group" "avd_nsg" {
  name                = "nsg-${var.environment}-${var.location_short}-avd"
  location            = azurerm_resource_group.avd_rg[0].location
  resource_group_name = azurerm_resource_group.avd_rg[0].name

  # RDP inbound scoped to VirtualNetwork only — no public RDP exposure
  security_rule {
    name                       = "Allow-RDP"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-ICMP"
    priority                   = 1010
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-HTTPS-Out"
    priority                   = 1020
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }
}

resource "azurerm_subnet_network_security_group_association" "avd_nsg_assoc" {
  subnet_id                 = azurerm_subnet.avd_session_subnet.id
  network_security_group_id = azurerm_network_security_group.avd_nsg.id
}
