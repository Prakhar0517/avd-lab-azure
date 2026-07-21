# build-agent/ — dedicated Azure DevOps Linux build agent

Self-contained Terraform stack that provisions `vm-build-agent-01`, a
dedicated Linux Azure DevOps build agent, replacing the WSL2-on-laptop agent
that `image-pipeline.yml` currently depends on (root `CLAUDE.md`, Hard-Won
Lesson 8, and its "KNOWN RISK" note under `image-pipeline.yml`).

This stack is intentionally independent of `AVD ALL/`: its own resource
group, VNet, and Terraform state (same backend storage account/container as
`AVD ALL/`, different state key — see `main.tf`). The only link between the
two is a data-source lookup of the existing `kv-avdlab-5mwdto` Key Vault
(`keyvault.tf`) — no remote-state or output reference.

## Manual prerequisites (must exist before `terraform apply`)

1. **Agent pool `linux-build`** must already exist in the Azure DevOps org
   `prakhar0517` (Organization Settings → Agent Pools → New). Terraform and
   cloud-init cannot create Azure DevOps agent pools — `config.sh` will fail
   on first boot if the pool isn't there yet.
2. **Key Vault secret `ado-agent-pat`** must exist in `kv-avdlab-5mwdto`
   (`rg-terraform-state`) before first boot, holding a Personal Access Token
   scoped to **Agent Pools (Read & manage)** only. cloud-init retries for up
   to ~12 minutes to cover Key Vault RBAC propagation lag — it cannot wait
   for a secret that was never created.

## Why this is applied manually, once

This VM is the build agent. An agent can't provision itself — something has
to run `terraform apply` before there's anywhere for `image-pipeline.yml` (or
any other pipeline) to actually execute. This stack is the one documented
exception to "no `terraform apply` from laptop" in the root `CLAUDE.md`:
applied manually, once, from the laptop, as the bootstrap step. It is not
wired into `azure-pipelines.yml` or `image-pipeline.yml`, and neither of
those files has been touched by this change.

Future changes to this stack should still go through a PR for review, but
until `linux-build` has at least one agent registered, there is no agent to
run a plan/apply pipeline on — so the very first apply has nowhere to run
except the laptop.

## What it creates

- `rg-build-agent-eus` (eastus)
- `vnet-build-agent` (`10.20.0.0/24`) / `snet-agent` (`10.20.0.0/27`) —
  non-overlapping with `AVD ALL/`'s `10.10.0.0/16`, no peering
- NSG: all inbound denied by default; an `Allow-SSH-Admin` rule is only
  created when `admin_source_ip` is set. Outbound is left open — the agent
  needs HTTPS out to `dev.azure.com`, Key Vault, apt, and HashiCorp, plus
  WinRM 5986 out to Packer's temporary Windows build VMs.
- A **Standard, static public IP attached directly to the NIC** — this gives
  the VM an explicit outbound path now that Azure's implicit default
  outbound access is retired for new VMs. Inbound is unaffected — the NSG
  above still denies it.
- `vm-build-agent-01`: Ubuntu 22.04 LTS Gen2, `Standard_B2s`, 64 GB
  StandardSSD_LRS OS disk, admin user `prakhar` with SSH-key-only auth
  (password auth disabled), SystemAssigned managed identity.
- A `Key Vault Secrets User` role assignment for the VM's identity, scoped to
  the existing `kv-avdlab-5mwdto` (that vault uses RBAC authorization, not
  access policies — see `AVD ALL/keyvault.tf` — so this mirrors that model
  rather than adding an access policy).
- A `Contributor` role assignment for the VM's identity, scoped to the
  existing `rg-test-tf-rg-demo-avd-eus` resource group (`packer-rbac.tf`,
  data-source lookup — not a remote-state reference to `AVD ALL/`). This is
  what lets Packer build and capture the golden image using the agent's
  Managed Identity instead of the retired `packer-local-test-sp` /
  `packer-client-secret` (root `CLAUDE.md`, Hard-Won Lesson 11 epilogue).
  Like every other stack-modifying change here, it's applied from the
  laptop per this stack's bootstrap exception (see above) — and like the
  Key Vault Secrets User assignment, allow up to ~10 minutes for the role
  to propagate before running a Packer build against a fresh apply.
- A daily auto-shutdown schedule at 23:00 India Standard Time, no
  notification.

## cloud-init (`cloud-init.yaml`)

Rendered via `templatefile()` in `vm.tf` (so the vault name, PAT secret name,
ADO org URL, pool, and agent name are visible in Terraform rather than buried
in YAML) and passed in as `custom_data`. On first boot it:

1. Installs `git curl unzip jq python3-pip`.
2. Installs the Azure CLI (Microsoft's official install script) and Packer
   (HashiCorp's apt repo).
3. `pip3 install ansible pywinrm`.
4. Creates a non-sudo `adoagent` service account.
5. Downloads the latest `vsts-agent-linux-x64` release tarball into
   `/opt/ado-agent`, owned by `adoagent`. The tarball isn't attached as a
   GitHub release asset, so the version is read from the release's
   `tag_name` and used to build the real `download.agent.dev.azure.com` URL,
   which is HEAD-checked before use; if resolution or the check fails, it
   falls back to a pinned, pre-verified version (the agent self-updates
   after registration, so a slightly-stale pin is safe).
6. Runs `az login --identity`, then `az keyvault secret show` for
   `ado-agent-pat`, retrying every 30s for up to ~12 minutes to cover RBAC
   propagation lag — but only if `/opt/ado-agent/.agent` doesn't already
   exist (i.e. only on first run; see below).
7. As `adoagent`, runs `config.sh --unattended` against
   `https://dev.azure.com/prakhar0517`, pool `linux-build`, agent name
   `vm-build-agent-01`. The PAT is handed to `config.sh` only via the
   `VSTS_AGENT_INPUT_TOKEN` environment variable inside that subshell — it is
   never echoed and never written to disk; `config.sh` persists its own
   derived OAuth credential, not the raw PAT.
8. Installs and starts the agent as a systemd service via `svc.sh`, running
   as `adoagent`.

**The whole script is safe to run twice in a row** (cloud-init itself only
runs it once per VM, but it's also invoked manually for
troubleshooting/testing): the HashiCorp gpg key step uses
`--batch --yes` so it overwrites non-interactively instead of blocking on a
`/dev/tty` prompt that doesn't exist under cloud-init; agent registration
(step 6-7) is skipped entirely once `/opt/ado-agent/.agent` exists, since
`config.sh --unattended` has no tty to prompt on and errors if re-run
against an already-configured agent without `--replace`; and the `svc.sh
install` step is skipped once `/opt/ado-agent/.service` exists, since
`svc.sh install` hard-fails if the systemd unit file is already there (it
has no overwrite mode) — `svc.sh start` is naturally idempotent and always
runs. The Microsoft Azure CLI install script was checked too: it pipes `gpg
--dearmor` straight to a shell redirect rather than `gpg -o`, so it was
already safe to rerun and needed no change.

Provisioning output is logged to `/var/log/ado-agent-provision.log` on the
VM for troubleshooting.

## Applying

```bash
cd build-agent
terraform init
terraform plan
terraform apply
```

`terraform.tfvars` in this directory carries `admin_ssh_public_key` and is
listed in `build-agent/.gitignore` — **it is local-only and will not exist
on a fresh clone.** Recreate it (or pass `-var "admin_ssh_public_key=..."`
directly) before planning/applying:

```
admin_ssh_public_key = "ssh-ed25519 AAAA... your-key-here"
```

`admin_source_ip` is optional and has no entry in `terraform.tfvars` by
default — pass `-var "admin_source_ip=<your public IP>/32"` to create the
SSH-allow rule; omit it and the NSG creates no SSH-allow rule at all
(inbound stays fully denied; use Azure Bastion or Serial Console for
out-of-band access instead).

**Editing `cloud-init.yaml` forces a VM replacement.** `custom_data` is only
applied at initial provisioning (Azure/cloud-init don't re-run it on an
existing VM), so it's a `ForceNew` field on
`azurerm_linux_virtual_machine.build_agent` — any change to `cloud-init.yaml`
means `terraform plan` will show `vm-build-agent-01` as destroyed and
recreated, not updated in place. That's expected, and it's exactly the
scenario the ~12-minute Key Vault retry loop in `cloud-init.yaml` is built to
absorb: the replacement VM's managed-identity role assignment has to
propagate all over again before it can read `ado-agent-pat`.
