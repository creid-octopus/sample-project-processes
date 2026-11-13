# "Development" already exists in the space. Terraform only reads it.
data "octopusdeploy_environments" "development" {
  partial_name = "Development"
}

resource "octopusdeploy_environment" "test" {
  name = "Test"
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
    octopusdeploy_environment.test.id,
    octopusdeploy_environment.lab.id,
    octopusdeploy_environment.staging.id,
    octopusdeploy_environment.production.id,
  ]
}

# Lifecycles drive the channels. The project keeps its default lifecycle.
resource "octopusdeploy_lifecycle" "promotion" {
  name        = "Dev/Test, Lab, Production"
  description = "Mock promotion flow. One of Development or Test must pass, then Lab, then Production."

  # Phase 1: non-production. A release needs a successful deployment to at least one of these.
  phase {
    name                                  = "Non-production"
    optional_deployment_targets           = [local.development_environment_id, octopusdeploy_environment.test.id]
    minimum_environments_before_promotion = 1
  }

  # Phase 2: Lab must pass before Production.
  phase {
    name                        = "Lab"
    optional_deployment_targets = [octopusdeploy_environment.lab.id]
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
