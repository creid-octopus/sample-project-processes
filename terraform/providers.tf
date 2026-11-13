# The space ID is pinned on purpose. A mistake in a variable cannot point this
# workspace at another space. The validation in variables.tf enforces the same rule.
provider "octopusdeploy" {
  address  = var.octopus_url
  api_key  = var.octopus_api_key
  space_id = var.space_id
}
