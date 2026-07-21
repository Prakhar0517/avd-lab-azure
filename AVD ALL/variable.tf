
variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
  default     = "test"
}

variable "workload" {
  description = "Workload name (avd, sql, web)"
  type        = string
  default     = "avd"
}
variable "project" {
  type    = string
  default = "tf-rg-demo"
}
variable "create_rg" {
  description = "Create resource group for AVD session hosts"
  type        = bool
  default     = true
}
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    project     = "tf-rg-demo"
    environment = "test"
    workload    = "avd"
    owner       = "Prakhar"
  }
}

variable "location_short" {
  description = "Short location name"
  type        = string
  default     = "eus"
  validation {
    condition     = can(regex("^eus$", var.location_short))
    error_message = "location_short must be one of: eus"
  }
}
variable "location" {
  default = "East US"
}

variable "admin_username" {
  type = string
}

variable "keyvault_admin_object_id" {
  description = "Entra ID object ID granted Key Vault Secrets Officer on the AVD secrets vault (Prakhar's user account)"
  type        = string
}

variable "pipeline_sp_object_id" {
  description = "Object ID of the 'azure connect' service connection's service principal — granted Key Vault Secrets Officer so pipeline runs can read/write the generated admin_password secret"
  type        = string
}

variable "persona_shortname" {
  type = string
}

variable "vm_count" {
  description = "Number of AVD session hosts"
  type        = number
  default     = 25
}

variable "golden_image_version" {
  description = "Version of the win11-avd-enterprise gallery image (sig_test_avd_eus_001) to deploy session hosts from. Produced by image-pipeline.yml as 1.0.<BuildId> — bump this to roll forward, revert it to roll back."
  type        = string
  default     = "1.0.168"
}

variable "vm_size" {
  description = "AVD Session Host Size"
  type        = string
  default     = "Standard_B2s"
}

variable "avd_users_group_object_id" {
  description = "Entra ID object ID for the AVD users group — granted Virtual Machine User Login (session-host.tf) and FSLogix share access (Fslogix.tf). Required for RDP to Entra ID joined hosts."
  type        = string
}