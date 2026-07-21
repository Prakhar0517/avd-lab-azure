# ── Virtual Network ──────────────────────────────────────────────────────────
# Deliberately non-overlapping with AVD ALL's 10.10.0.0/16 — this stack has no
# peering or other network relationship to the AVD stack.
resource "azurerm_virtual_network" "agent_vnet" {
  name                = "vnet-build-agent"
  location            = azurerm_resource_group.build_agent.location
  resource_group_name = azurerm_resource_group.build_agent.name
  address_space       = ["10.20.0.0/24"]

  tags = local.common_tags
}

resource "azurerm_subnet" "agent_subnet" {
  name                 = "snet-agent"
  resource_group_name  = azurerm_resource_group.build_agent.name
  virtual_network_name = azurerm_virtual_network.agent_vnet.name
  address_prefixes     = ["10.20.0.0/27"]
}

# ── Network Security Group: deny all inbound, optional SSH-allow ────────────
resource "azurerm_network_security_group" "agent_nsg" {
  name                = "nsg-build-agent-eus"
  location            = azurerm_resource_group.build_agent.location
  resource_group_name = azurerm_resource_group.build_agent.name

  # Only created when var.admin_source_ip is set. Priority 900 puts it ahead
  # of Deny-All-Inbound (4096) below, so it actually takes effect when present.
  dynamic "security_rule" {
    for_each = var.admin_source_ip != null ? [var.admin_source_ip] : []
    content {
      name                       = "Allow-SSH-Admin"
      priority                   = 900
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "22"
      source_address_prefix      = security_rule.value
      destination_address_prefix = "*"
    }
  }

  # Azure NSGs already default-deny anything not explicitly allowed, but this
  # makes the "no inbound" intent explicit and overrides the built-in
  # AllowVnetInBound / AllowAzureLoadBalancerInBound defaults.
  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Outbound intentionally left at platform defaults (allow) — the agent
  # needs HTTPS out to dev.azure.com / Key Vault / apt / HashiCorp, plus
  # WinRM 5986 out to Packer's temporary Windows build VMs.

  tags = local.common_tags
}

resource "azurerm_subnet_network_security_group_association" "agent_nsg_assoc" {
  subnet_id                 = azurerm_subnet.agent_subnet.id
  network_security_group_id = azurerm_network_security_group.agent_nsg.id
}

# ── Public IP: explicit outbound path ────────────────────────────────────────
# Default outbound access (the implicit outbound IP a VM gets with no other
# outbound method) is retired for new deployments. A Standard static public IP
# attached directly to the NIC gives the VM an explicit outbound path.
# Inbound is unaffected by this — the NSG above denies it regardless.
resource "azurerm_public_ip" "agent_pip" {
  name                = "pip-build-agent-01"
  location            = azurerm_resource_group.build_agent.location
  resource_group_name = azurerm_resource_group.build_agent.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = local.common_tags
}

resource "azurerm_network_interface" "agent_nic" {
  name                = "nic-build-agent-01"
  location            = azurerm_resource_group.build_agent.location
  resource_group_name = azurerm_resource_group.build_agent.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.agent_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.agent_pip.id
  }

  tags = local.common_tags
}
