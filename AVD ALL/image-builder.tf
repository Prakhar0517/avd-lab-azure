# ─────────────────────────────────────────────────────────────────────────────
# IMAGE BUILDER — REPLACED BY PACKER
# ─────────────────────────────────────────────────────────────────────────────
# The manually managed image builder VM below has been retired.
#
# It is replaced by a Packer pipeline (see /packer/windows-avd.pkr.hcl) which:
#   1. Spins up a temporary Azure VM automatically
#   2. Runs Ansible inside it to install FSLogix, AVD agent, and hardening
#   3. Syspreps and captures the image to the Shared Image Gallery
#   4. Deletes the temporary VM
#
# No persistent image builder VM is needed — Packer manages the entire
# build lifecycle. Session hosts in session-host.tf will reference the
# gallery image once the Packer pipeline has produced at least one version.
# ─────────────────────────────────────────────────────────────────────────────

/*
resource "azurerm_public_ip" "image_builder_pip" { ... }
resource "azurerm_network_interface" "image_builder_nic" { ... }
resource "azurerm_windows_virtual_machine" "image_builder" { ... }
resource "azurerm_virtual_machine_extension" "image_builder_domain_join" { ... }
*/
