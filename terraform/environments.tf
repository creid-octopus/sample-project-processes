# "Development" already exists in the space. Terraform only reads it.
data "octopusdeploy_environments" "development" {
  partial_name = "Development"
}

resource "octopusdeploy_environment" "lab" {
  name = "Lab"
}

resource "octopusdeploy_environment" "staging" {
  name = "Staging"
}

resource "octopusdeploy_environment" "production" {
  name = "Production"
}

locals {
  development_environment_id = one([for e in data.octopusdeploy_environments.development.environments : e.id if e.name == "Development"])

  all_environment_ids = [
    local.development_environment_id,
    octopusdeploy_environment.lab.id,
    octopusdeploy_environment.staging.id,
    octopusdeploy_environment.production.id,
  ]
}

# Lifecycles drive the channels. The project keeps its default lifecycle.
resource "octopusdeploy_lifecycle" "standard" {
  name        = "Standard (Lab, Staging, Production)"
  description = "Mock lifecycle for the standard release channel."

  phase {
    name                        = "Lab"
    optional_deployment_targets = [octopusdeploy_environment.lab.id]
  }

  phase {
    name                        = "Staging"
    optional_deployment_targets = [octopusdeploy_environment.staging.id]
  }

  phase {
    name                        = "Production"
    optional_deployment_targets = [octopusdeploy_environment.production.id]
  }
}

resource "octopusdeploy_lifecycle" "lab_only" {
  name        = "Lab only"
  description = "Mock lifecycle for pre-release channels. Never reaches production."

  phase {
    name                        = "Lab"
    optional_deployment_targets = [octopusdeploy_environment.lab.id]
  }
}
