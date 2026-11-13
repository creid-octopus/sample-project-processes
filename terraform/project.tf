# The project is created in the UI with Config as Code. Terraform reads it and
# manages the pieces around it. The deployment process lives in
# .octopus/large-process-multi-tenant and is written by generator/New-ProcessOcl.ps1.
data "octopusdeploy_projects" "main" {
  partial_name = var.project_name
}

locals {
  project_id = one([for p in data.octopusdeploy_projects.main.projects : p.id if p.name == var.project_name])
}

# Channels carry the lifecycles. Version rules are added after the process exists,
# because a rule refers to steps by name.
resource "octopusdeploy_channel" "lab" {
  name         = "Lab"
  description  = "Lab builds only."
  project_id   = local.project_id
  lifecycle_id = octopusdeploy_lifecycle.lab_only.id
}

resource "octopusdeploy_channel" "beta" {
  name         = "Beta"
  description  = "Pre-release channel for beta program tenants."
  project_id   = local.project_id
  lifecycle_id = octopusdeploy_lifecycle.lab_only.id
}

resource "octopusdeploy_channel" "release" {
  name         = "Release"
  description  = "Standard release channel."
  project_id   = local.project_id
  lifecycle_id = octopusdeploy_lifecycle.promotion.id
}
