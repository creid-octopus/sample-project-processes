variable "octopus_url" {
  type        = string
  description = "Address of the Octopus instance."
  default     = "https://creid.octopus.app"
}

variable "octopus_api_key" {
  type        = string
  sensitive   = true
  description = "API key for the agent identity. Set it with the TF_VAR_octopus_api_key environment variable. Never put it in a file."
}

variable "space_id" {
  type        = string
  description = "The only space this workspace may touch."
  default     = "Spaces-2"

  validation {
    condition     = var.space_id == "Spaces-2"
    error_message = "This workspace is locked to the multi-tenant-testing space (Spaces-2)."
  }
}

variable "project_name" {
  type        = string
  description = "Name of the existing Config as Code project. Created in the UI. Terraform only reads it."
  default     = "Large Process - Multi Tenant"
}
