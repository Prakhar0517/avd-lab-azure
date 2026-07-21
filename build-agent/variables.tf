variable "location" {
  description = "Azure region for the build agent stack"
  type        = string
  default     = "eastus"
}

variable "admin_ssh_public_key" {
  description = "SSH public key for the 'prakhar' admin account on vm-build-agent-01. Password authentication is disabled — this is the only way in."
  type        = string
}

variable "admin_source_ip" {
  description = "Single source IP/CIDR allowed to SSH to the agent (e.g. \"203.0.113.4/32\"). Leave as null (default) to create no SSH-allow rule at all — inbound stays fully denied by the NSG."
  type        = string
  default     = null
}
