# Azure Virtual Desktop Lab — Infrastructure as Code

> A production-grade Azure Virtual Desktop environment built entirely with Terraform and deployed via a full CI/CD pipeline on Azure DevOps. No manual deployments.

---

## Overview

This project is a personal infrastructure lab and learning challenge: design, build, and automate a complete Azure Virtual Desktop environment using real-world DevOps practices — Infrastructure as Code, GitOps workflow, secrets management, and CI/CD gating.

**Current Phase:** Baseline infrastructure complete. Rebuilding with golden image pipeline (Packer + Ansible) — see [Roadmap](#roadmap).

---


```

┌─────────────────────────────────────────────────────────────────┐
│                     Azure DevOps Pipeline                        │
│                                                                  │
│   PR pushed → Plan stage → Manual review → Approve → Apply      │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## What's Built

### Core Infrastructure (Terraform)
| Component | Resource | Details |
|---|---|---|
| Networking | VNet, Subnet, NSG | RDP scoped to VirtualNetwork only, HTTPS outbound |
| AVD | Workspace, Host Pool | Pooled / BreadthFirst, max 10 sessions |
| AVD | Application Groups | Desktop + RemoteApp groups |
| Compute | Session Hosts | Windows 11 Multi-Session, `Standard_B2s` |
| Compute | Image Builder VM | Staging machine for golden image |
| Identity | Hybrid Azure AD Join | Azure AD Connect on DC, Entra ID sync |
| Profiles | FSLogix Storage | Private Endpoint + Private DNS Zone |
| Images | Shared Image Gallery | `sig_test_avd_eus_001` with image definition |
| Monitoring | Log Analytics Workspace | Session host diagnostics |
| State | Azure Blob Storage | Remote Terraform state (`storageterraform0517`) |

### Domain & Identity
- Domain Controller (`dc-01.avd.lab`) — the only manually provisioned resource; required as a prerequisite for domain join
- All session hosts domain-joined via the `JsonADDomainExtension` VM extension (`adjoinuser@avd.lab`)
- AVD DSC extension handles host pool registration token injection

### FSLogix (Post-Terraform)
- ADMX/ADML templates installed to Group Policy Central Store
- FSLogix profile settings deployed via Group Policy Management Console targeting the `OU=AVD` organisational unit
- Profile VHDs stored on Azure Files with Private Endpoint — VMs never traverse the public internet to reach storage

### CI/CD Pipeline
- **Trigger:** PR to `main` → Plan stage runs automatically
- **Review:** Plan output visible in pipeline logs before anything is applied
- **Gate:** Apply stage requires manual approval (`prod-approval` environment)
- **Artifact:** Plan file published at Plan stage, downloaded at Apply — ensures the reviewed plan is exactly what gets applied
- **Secrets:** All credentials injected via Azure DevOps Library variable group (`avd-secrets`) as `TF_VAR_*` environment variables — no plaintext secrets in code

---

## Repository Structure

```
avd-lab-azure/
├── main.tf                  # Provider, backend, workspace/host pool/app groups
├── network.tf               # VNet, subnet, NSG
├── session-host.tf          # AVD session host VMs + extensions
├── compute-gallery.tf       # Shared Image Gallery + image definition
├── image-builder.tf         # Image builder staging VM
├── Fslogix.tf               # FSLogix storage account + private endpoint
├── apps.tf                  # RemoteApp application group resources
├── avd-registration.tf      # Host pool registration info
├── identity.tf              # Identity-related resources
├── locals.tf                # Shared local values
├── variable.tf              # Input variable definitions
├── Output.tf                # Output values
├── terraform.tfvars         # Non-sensitive variable values (no secrets)
└── azure-pipelines.yml      # CI/CD pipeline definition
```

---

## Prerequisites

Before deploying this environment you will need:

- Azure subscription with Contributor access
- Azure DevOps organisation and project
- Service connection configured in Azure DevOps (Service Principal)
- Self-hosted agent pool (or update `pool:` in `azure-pipelines.yml` to use Microsoft-hosted)
- Azure Blob Storage container for Terraform remote state
- A Windows Server VM deployed as a Domain Controller (the only resource provisioned outside Terraform — see [Known Issues](#known-issues--lessons-learned))
- Azure DevOps Library variable group named `avd-secrets` with the following locked secret variables:
  ```
  admin_password
  domain_password
  user_password
  ```

---

## Deployment

```bash
# Clone the repo
git clone https://github.com/Prakhar0517/avd-lab-azure.git
cd avd-lab-azure

# Review non-sensitive variables
cat terraform.tfvars

# Local plan (optional — pipeline does this automatically)
terraform init
terraform plan -var="admin_password=<value>" \
               -var="domain_password=<value>" \
               -var="user_password=<value>"
```

For CI/CD deployment: push a branch, open a PR to `main`, let the pipeline run Plan, review the output, approve, merge. Apply runs automatically after merge with manual approval gate.

---

## Known Issues & Lessons Learned

These are real issues encountered during the build — documented here as learning artefacts.

| Issue | Root Cause | Resolution |
|---|---|---|
| Terraform state drift | Partial deployments mixed with manual Azure Portal changes | Destroy and rebuild cleanly from code only |
| `unexpected end of JSON input` on AVD App Group | Race condition / eventual consistency during Terraform reads | Re-run plan; resolved in clean rebuild |
| `Saved plan is stale` | Azure infrastructure changed between Plan and Apply pipeline stages | Reduced time between stages; golden image approach eliminates most in-flight changes |
| Missing Terraform variables in pipeline | `terraform.tfvars` removed from git during secrets cleanup | Restored non-sensitive vars to `tfvars`; secrets remain in variable group |
| `Inconsistent dependency lock file` | `.terraform.lock.hcl` missing from repo | Added lock file to git |
| VM Extension conflicts (`resource already exists`) | Extensions existed in Azure but not in Terraform state after manual changes | `terraform import` or destroy and redeploy |
| Domain join failed — LDAP Error 49 / `0x52e` | Password mismatch between Active Directory and Azure DevOps variable group | Reset `adjoinuser` password in AD; update variable group to match |
| AVD session host registration failure | Downstream of failed domain join — DSC extension could not complete | Resolved by fixing domain join credential issue |

**Key lesson:** Mixing manually created Azure resources with Terraform-managed ones causes compounding state drift that becomes increasingly difficult to recover from. The correct pattern — and the goal of this project going forward — is **everything from code, nothing from the portal**.

---

## Roadmap

### July 2026 — Packer + Ansible + Full CI/CD

**Phase 1 — Golden Image Pipeline**
- [ ] Packer HCL template targeting Azure, outputting to `sig_test_avd_eus_001`
- [ ] Ansible playbook as Packer provisioner: FSLogix agent, AVD agent + DSC bootloader, Windows hardening baseline, sysprep
- [ ] `image-pipeline.yml` in Azure DevOps: commit → Packer build → new gallery image version

**Phase 2 — Scale to 25 Session Hosts**
- [ ] Update `session-host.tf` to source latest image version from gallery (replacing marketplace image)
- [ ] Scale to 25 VMs (`avd-sh-01` through `avd-sh-25`) via `vm_count` variable
- [ ] Domain join and host pool registration fully automated via Terraform extensions
- [ ] All 25 hosts visible in host pool and accessible via Windows App

**Phase 3 — CI/CD Hardening**
- [ ] Separate image build pipeline from infra deploy pipeline
- [ ] Azure Key Vault integration for secrets (replacing ADO variable group)
- [ ] End-to-end demo: one commit → image built → 25 VMs deployed → users log in

---

## Tech Stack

![Terraform](https://img.shields.io/badge/Terraform-7B42BC?style=flat&logo=terraform&logoColor=white)
![Azure](https://img.shields.io/badge/Microsoft_Azure-0089D6?style=flat&logo=microsoft-azure&logoColor=white)
![Azure DevOps](https://img.shields.io/badge/Azure_DevOps-0078D7?style=flat&logo=azure-devops&logoColor=white)
![Windows](https://img.shields.io/badge/Windows_11-0078D4?style=flat&logo=windows11&logoColor=white)

---

## Author

Prakhar Sharma
[github.com/Prakhar0517](https://github.com/Prakhar0517)