terraform {
  required_version = ">= 1.5"

  required_providers {
    octopusdeploy = {
      source  = "OctopusDeploy/octopusdeploy"
      version = "~> 1.0"
    }
  }
}
