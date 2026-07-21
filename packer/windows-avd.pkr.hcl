# ─────────────────────────────────────────────────────────────────────────────
# PHASE 2a — PACKER GOLDEN IMAGE TEMPLATE
# ─────────────────────────────────────────────────────────────────────────────
# Builds a Windows 11 multi-session AVD golden image:
#   1. Spins up a temporary Azure VM from the marketplace base image
#   2. PowerShell provisioner bootstraps the VM (waits for the guest agent)
#   3. Ansible provisioner (over WinRM) installs FSLogix, AVD agent, and the
#      hardening baseline — see packer/ansible/playbook.yml (Phase 2b, not
#      written yet — this template will fail at the ansible step until that
#      file exists)
#   4. Sysprep generalizes the VM
#   5. Packer captures straight into the Shared Image Gallery and deletes the
#      temporary VM (and only the temporary VM/NIC/disk/PIP it created — see
#      note on build_resource_group_name below)
#
# Auth: authenticates via the build agent's Managed Identity — NOT the same
# credential as Terraform. Terraform's "azure connect" service connection is
# Workload Identity Federation (OIDC, no client secret); Packer has no WIF
# fallback, but vm-build-agent-01 carries a system-assigned Managed Identity
# with Contributor on the AVD resource group (build-agent/packer-rbac.tf),
# and the packer azure-arm plugin defaults to the machine's Managed Identity
# when no client_secret/client_jwt/client_cert_path/use_azure_cli_auth is
# set — so image-pipeline.yml exports only ARM_TENANT_ID/ARM_SUBSCRIPTION_ID
# (see CLAUDE.md Hard-Won Lesson 11 epilogue). The old packer-local-test-sp
# service principal and its Key Vault secret are retired.
#
# ── Base image: verified 2026-07-09 against the live subscription ──────────
# `az vm image list-skus -l eastus -f windows-11 -p MicrosoftWindowsDesktop`
# shows win11-22h2-avd (what this template AND session-host.tf's
# source_image_reference both point at) no longer exists as a SKU at all —
# not deprecated, just gone. win11-24h2-avd is published and available in
# eastus, so this template now builds from that. session-host.tf still
# references win11-22h2-avd; that's a separate, pre-existing problem this
# task didn't touch (session-host.tf wasn't in scope here) — but it means any
# Terraform change that forces session host VM replacement will fail until
# that file is updated too. Flag this to the user before it bites.
#
# ── Trusted Launch: verified, no change needed ──────────────────────────────
# `az vm image show` on win11-24h2-avd reports hyperVGeneration=V2 and
# features: [{"name":"SecurityType","value":"TrustedLaunchAndConfidentialVmSupported"}].
# The "...Supported" suffix (vs. bare "TrustedLaunch") means Trusted Launch
# and Confidential VM are optional capabilities of this image, not a
# requirement — it deploys fine as a plain Gen2 "Standard" security-type VM.
# compute-gallery.tf's azurerm_shared_image sets hyper_v_generation = "V2"
# only (no trusted_launch_supported / confidential_vm_supported), so it
# defines a Standard-security-type Gen2 image. This source block below also
# doesn't set `security_type`, so Packer's build VM defaults to Standard too
# — both sides agree, so there's no security-type mismatch to cause a
# capture failure. (win11-23h2-avd reports the identical feature value, so
# this has been true for a while, not something new in 24h2.) If you later
# want Trusted Launch as a deliberate hardening step (reasonable, since this
# project already has a hardening playbook), that requires changes on both
# sides together — `security_type = "TrustedLaunch"` + secure_boot/vtpm here,
# AND `trusted_launch_supported = true` on the gallery image definition, AND
# matching `security_type` on the session-host.tf VMs that consume the
# resulting image version. That's a separate decision, not done here.
#
# ── Ansible provisioner: requires WSL2 on this Windows self-hosted agent ───
# Ansible has no supported native-Windows control node — `ansible-playbook`
# itself (the process Packer's "ansible" provisioner shells out to on THIS
# machine, not inside the target Azure VM) needs a real POSIX environment.
# Verified on this machine: `wsl.exe -l -q` returns "The Windows Subsystem
# for Linux is not installed." — i.e. the gap is real, not theoretical.
# See packer/preflight-check.ps1 and the note on the ansible provisioner
# below for the recommended fix and how Phase 2c should use it.
# ─────────────────────────────────────────────────────────────────────────────

packer {
  required_version = ">= 1.9.0"

  required_plugins {
    azure = {
      source  = "github.com/hashicorp/azure"
      version = ">= 2.0.0"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = ">= 1.1.0"
    }
  }
}

# ── Auth (Managed Identity — see header note above) ─────────────────────────
# These vars stay empty in image-pipeline.yml now (no ARM_CLIENT_ID/
# ARM_CLIENT_SECRET exported); kept only so a local/manual `packer build`
# can still override with an explicit SP if ever needed.

variable "client_id" {
  type      = string
  default   = env("ARM_CLIENT_ID")
  sensitive = true
}

variable "client_secret" {
  type      = string
  default   = env("ARM_CLIENT_SECRET")
  sensitive = true
}

variable "tenant_id" {
  type      = string
  default   = env("ARM_TENANT_ID")
  sensitive = true
}

variable "subscription_id" {
  type    = string
  default = env("ARM_SUBSCRIPTION_ID")
}

# ── Target: where the gallery actually lives ────────────────────────────────
# NOTE: CLAUDE.md's architecture table lists the resource group as "avd", but
# that RG only holds legacy/manual leftovers (e.g. the retired dc-01). Verified
# live against the subscription: the gallery sig_test_avd_eus_001 actually
# lives in rg-test-tf-rg-demo-avd-eus — the RG Terraform creates itself
# (locals.rg_name, azurerm_resource_group.avd_rg). Build here, not in "avd".

variable "resource_group_name" {
  type    = string
  default = "rg-test-tf-rg-demo-avd-eus"
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "gallery_name" {
  type    = string
  default = "sig_test_avd_eus_001"
}

variable "image_definition_name" {
  type    = string
  default = "win11-avd-enterprise"
}

variable "image_version" {
  description = "Version published into the gallery image definition. Azure Compute Gallery requires each build to use a new, strictly-increasing version — Phase 2c's pipeline should override this per run (e.g. -var image_version=1.0.<Build.BuildNumber>) rather than relying on this default."
  type        = string
  default     = "1.0.0"
}

variable "build_vm_size" {
  description = "VM size for the temporary build VM. Needs >= 2 vCPUs for sysprep."
  type        = string
  default     = "Standard_D2s_v3"
}

# ── Source: temporary Azure VM Packer builds, configures, and syspreps ─────

source "azure-arm" "avd_golden" {
  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
  subscription_id = var.subscription_id

  # Existing RG (holds the gallery) — NOT a throwaway RG Packer creates itself.
  # Because build_resource_group_name points at an EXISTING resource group,
  # Packer only deletes the specific VM/NIC/disk/PIP/ephemeral-NSG it created
  # here at the end of the build. It does NOT delete the resource group, so
  # the gallery, VNet, and session hosts already in this RG are untouched.
  build_resource_group_name = var.resource_group_name

  # Base marketplace image. session-host.tf currently still deploys from
  # win11-22h2-avd, but that SKU has been fully retired from the marketplace
  # (verified via `az vm image list-skus` — see header note above), so this
  # template moves to win11-24h2-avd instead of tracking a dead SKU.
  # session-host.tf needs the same update before it can provision a new
  # session host from scratch, but that's out of scope for this file.
  # (Marketplace terms are already accepted on this subscription — proven by
  # the session hosts already running from the sibling win11-22h2-avd image.)
  image_publisher = "MicrosoftWindowsDesktop"
  image_offer     = "windows-11"
  image_sku       = "win11-24h2-avd"
  image_version   = "latest"

  vm_size = var.build_vm_size
  os_type = "Windows"

  # No virtual_network_name set — Packer creates its own ephemeral VNet/
  # subnet/NSG/NIC/PIP scoped to the build and tears them down afterward.
  # Deliberately NOT joining vnet-avd-demo: nsg-test-eus-avd only allows RDP
  # from VirtualNetwork, not inbound WinRM (5986) from the internet, and
  # there's no reason this ephemeral build VM needs to share that network.

  communicator   = "winrm"
  winrm_use_ssl  = true
  winrm_insecure = true # self-signed cert on a short-lived build VM — traffic is still TLS-encrypted, just not CA-verified
  winrm_timeout  = "45m"
  winrm_username = "packer"

  # Publish straight to the Shared Image Gallery — no intermediate managed image.
  shared_image_gallery_destination {
    subscription = var.subscription_id
    resource_group = var.resource_group_name
    gallery_name = var.gallery_name
    image_name = var.image_definition_name
    image_version = var.image_version
    replication_regions = ["eastus"]
    storage_account_type = "Standard_LRS"
  }

  azure_tags = {
    project     = "tf-rg-demo"
    environment = "test"
    workload    = "avd"
    purpose     = "packer-golden-image-build"
  }
}

# ── Build ────────────────────────────────────────────────────────────────────

build {
  sources = ["source.azure-arm.avd_golden"]

  # 1. Bootstrap: confirm the VM has actually settled before handing off to
  #    Ansible. Packer's own WinRM communicator already works out of the box
  #    on Azure Windows images — this is just a readiness gate.
  provisioner "powershell" {
    inline = [
      "while ((Get-Service RdAgent).Status -ne 'Running') { Start-Sleep -s 5 }",
      "while ((Get-Service WindowsAzureGuestAgent).Status -ne 'Running') { Start-Sleep -s 5 }",
      "Write-Output 'Guest agent ready, handing off to Ansible.'"
    ]
  }

  # 2. Diagnostic only, non-fatal: print the WinRM service auth config so
  #    future readers can see it in the build log without re-deriving it.
  #    Confirmed root cause (both the earlier pywinrm "basic: credentials
  #    rejected" errors AND the ansible_svc Basic self-connect that was here
  #    before): win11-24h2-avd's WinRM service has Basic auth disabled
  #    server-side — "Possible authentication mechanisms reported by server:
  #    Negotiate" — so Basic is refused regardless of credentials or account.
  #    Packer's own communicator has always succeeded via Negotiate/NTLM,
  #    never Basic, which is why it looked like a credential handoff problem
  #    at first. No custom account is created here anymore: Packer
  #    force-injects its own ansible_password into the ansible provisioner
  #    regardless (see the note below), so a separate account could never
  #    actually be used by the ansible run in the first place.
  provisioner "powershell" {
    inline = [
      "Get-ChildItem WSMan:\\localhost\\Service\\Auth | Format-Table Name,Value"
    ]
  }

  # 3. Ansible playbook does the real configuration work: FSLogix install +
  #    registry keys, AVD agent, hardening baseline.
  #    See packer/ansible/playbook.yml (Phase 2b — not written yet).
  #
  #    Prerequisite this path introduces: `ansible-playbook` runs on the
  #    build agent itself (Default pool) and connects OUT to this VM over
  #    WinRM — it does not run inside the VM. That agent is Windows, and
  #    Ansible has no supported native-Windows control node, so plain
  #    `pip install ansible pywinrm` on the Windows agent is not sufficient —
  #    there is no POSIX shell for ansible-playbook to run in. The agent
  #    needs WSL2 with a Linux distro, and `packer build` for this template
  #    needs to run FROM INSIDE that WSL distro (a Linux packer binary +
  #    `pip3 install ansible pywinrm` there), not from native Windows, so
  #    that Packer's own subprocess call to `ansible-playbook` resolves.
  #    Packer's azure-arm plugin still just talks WinRM out to Azure over the
  #    network, which works the same from WSL2 as from Windows.
  #
  #    image-pipeline.yml (Phase 2c) should invoke roughly:
  #      $env:WSLENV = "ARM_CLIENT_ID:ARM_CLIENT_SECRET:ARM_TENANT_ID:ARM_SUBSCRIPTION_ID"
  #      wsl.exe -e bash -lc "cd /mnt/c/work/Main/packer && packer init . && packer build ."
  #    as its first step, run packer/preflight-check.ps1 to fail fast with a
  #    clear message instead of failing 20+ minutes into a build at this
  #    provisioner. If WSL2 setup proves too fragile in practice, the
  #    fallback is to fold playbook.yml's tasks into a plain "powershell"
  #    provisioner instead — but the assignment specifically calls for
  #    Ansible, so that fallback is documented, not taken, here.
  # Root cause, confirmed (see the WSMan:\localhost\Service\Auth diagnostic
  # above, plus Build 3's -vvvv output): win11-24h2-avd's WinRM service has
  # Basic auth disabled server-side and advertises only Negotiate — the
  # original pywinrm "basic: credentials rejected" error and the ansible_svc
  # Basic self-connect that used to be tested here both trace to that. Fix
  # was ansible_winrm_transport=ntlm above, and NTLM transport itself is
  # confirmed working (Negotiate=true, connection reached credential
  # validation). But Build 3 then failed at the credential-validation step
  # itself: "ESTABLISH WINRM CONNECTION FOR USER: prakharsharma" — Ansible's
  # `user` option defaults to the user running Packer (prakharsharma, inside
  # WSL), NOT the communicator's winrm_username. So the inventory carried
  # ansible_user=prakharsharma while Packer force-injected the "packer"
  # account's password (Packer appends its own -e ansible_password=
  # <communicator password> AFTER extra_arguments, and Ansible's -e is
  # last-value-wins) — NTLM correctly rejected that mismatched user/password
  # pair. Fix: set `user = "packer"` below so it matches winrm_username and
  # the auto-injected password. Build proven with this fix; -vvvv removed
  # below now that the build is stable — it echoed the injected
  # ansible_password into build logs, which must not carry into the CI
  # pipeline (image-pipeline.yml, Phase 2c).
  provisioner "ansible" {
    playbook_file = "./ansible/playbook.yml"
    user          = "packer" # must match winrm_username — Packer injects that account's password regardless of what ansible_user the inventory would otherwise default to
    use_proxy     = false    # proxy adapter is SSH-specific; connect directly over WinRM instead

    extra_arguments = [
      "--extra-vars", "ansible_shell_type=powershell ansible_shell_executable=none ansible_winrm_server_cert_validation=ignore ansible_winrm_transport=ntlm"
    ]
  }

  # 4. Clean restart before sysprep — clears any pending-reboot state left by
  #    installs/hardening in the playbook so sysprep doesn't generalize a VM
  #    mid-update.
  provisioner "windows-restart" {
    restart_timeout = "15m"
  }

  # 5. Generalize. Must be the last thing that runs before Packer captures
  #    the disk into the gallery.
  provisioner "powershell" {
    inline = [
      "& $env:SystemRoot\\System32\\Sysprep\\Sysprep.exe /oobe /generalize /quit /mode:vm",
      "while ($true) { $state = (Get-ItemProperty 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Setup\\State').ImageState; if ($state -eq 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') { break }; Write-Output $state; Start-Sleep -s 10 }"
    ]
  }
}
