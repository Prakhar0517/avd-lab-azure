
variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
  default     = "test"
}

variable "location_short" {
  description = "Short location name"
  type        = string
  default     = "eus"
}

variable "admin_username" {
  type = string
}

variable "admin_password" {
  type      = string
  sensitive = true
}

variable "domain_name" {
  type = string
  description = "Active Directory domain FQDN (e.g., avd.lab)"
}

variable "ou_path" {
  type    = string
  default = ""
  description = "Target OU path for computer objects"
}

variable "domain_user_upn" {
  type = string
  description = "Domain account authorized to join machines to the domain"
}

variable "domain_password" {
  type      = string
  sensitive = true
  description = "Password for the domain join account"
}

variable "persona_shortname" {
  type = string
}

variable "dns_servers" {
  description = "DNS servers for the VNet (Domain Controllers or AADDS IPs)"
  type        = list(string)
  default     = ["10.10.0.4"] # Configured for Active-Active DCs
}

variable "user_password" {
  type      = string
  sensitive = true
}

variable "vm_count" {
  description = "Number of AVD session hosts"
  type        = number
  default     = 2
}

variable "vm_size" {
  description = "AVD Session Host Size"
  type        = string
  default     = "Standard_B2s"
}