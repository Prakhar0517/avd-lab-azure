# Validates that this self-hosted Azure DevOps agent can actually run the
# "ansible" provisioner in windows-avd.pkr.hcl before image-pipeline.yml
# (Phase 2c) invests 20+ minutes building a VM only to fail at that step.
#
# Why this exists: Ansible has no supported native-Windows control node.
# Packer's "ansible" provisioner shells out to `ansible-playbook` on the
# machine running `packer build` (this agent) — it does not run inside the
# target Azure VM, it only connects to it over WinRM. Since this agent's OS
# is Windows, `packer build` for this template must run from inside WSL2,
# with a Linux packer binary and `ansible`/`pywinrm` installed there.
#
# Run this as the first step of image-pipeline.yml (Phase 2c), or manually
# on the agent to check readiness. Exits 1 with a specific remediation
# message per missing prerequisite; exits 0 if the agent is ready.

$ErrorActionPreference = "Stop"
$failures = @()

$wslInstalled = $true
try {
    $distros = wsl.exe -l -q 2>$null
    if ($LASTEXITCODE -ne 0 -or -not ($distros | Where-Object { $_.Trim() -ne "" })) {
        $wslInstalled = $false
    }
} catch {
    $wslInstalled = $false
}

if (-not $wslInstalled) {
    $failures += "WSL2 is not installed or has no registered Linux distro. Run: wsl --install -d Ubuntu (requires a reboot)."
} else {
    $packerCheck = wsl.exe -e bash -lc "command -v packer" 2>$null
    if (-not $packerCheck) {
        $failures += "packer (Linux binary) not found inside WSL. Install it inside the distro: https://developer.hashicorp.com/packer/install"
    }

    $ansibleCheck = wsl.exe -e bash -lc "command -v ansible-playbook" 2>$null
    if (-not $ansibleCheck) {
        $failures += "ansible-playbook not found inside WSL. Install inside the distro: pip3 install ansible pywinrm"
    }

    $pywinrmCheck = wsl.exe -e bash -lc "python3 -c 'import winrm' 2>/dev/null && echo OK" 2>$null
    if ($pywinrmCheck -notmatch "OK") {
        $failures += "pywinrm python package not found inside WSL. Install: pip3 install pywinrm"
    }
}

if ($failures.Count -gt 0) {
    Write-Host "Ansible/WSL prerequisite check FAILED on this agent:" -ForegroundColor Red
    foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Red }
    exit 1
}

Write-Host "Ansible/WSL prerequisites OK - packer build can proceed inside WSL." -ForegroundColor Green
exit 0
