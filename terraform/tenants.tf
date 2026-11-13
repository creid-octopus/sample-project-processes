# The instance license caps tenants at 10 across all spaces, and the default space
# uses 5, so this space gets 5 tenants. Each tenant's tags are listed by hand so the
# five together cover every tag. Tags a tenant lacks are what the export must report
# as unused or low use.
locals {
  tenants = {
    "Tenant Alpha" = [
      "Module Pack/Module A",
      "Host Type/Server Only",
    ]

    "Tenant Bravo" = [
      "Module Pack/Module A",
      "Module Pack/Module B",
      "Module Pack/Module C",
      "Integration/Integration 1",
      "Host Type/Server And Workstation",
      "Hardening/Enhanced",
    ]

    "Tenant Charlie" = [
      "Module Pack/Module A",
      "Module Pack/Module B",
      "Module Pack/Module C",
      "Module Pack/Module D",
      "Module Pack/Module E",
      "Module Pack/Module F",
      "Integration/Integration 1",
      "Integration/Integration 2",
      "Integration/Integration 3",
      "Host Type/Server And Workstation",
      "Rollout Control/Hold",
    ]

    "Tenant Delta" = [
      "Module Pack/Module A",
      "Module Pack/Module D",
      "Integration/Integration 2",
      "Host Type/Server Only",
      "Pre-release/Beta Program",
      "Rollout Control/Fast Track",
    ]

    "Tenant Echo" = [
      "Module Pack/Module A",
      "Module Pack/Module B",
      "Host Type/Server And Workstation",
      "Pre-release/Beta Program",
      "Hardening/Enhanced",
      "Rollout Control/Hold",
    ]
  }
}

resource "octopusdeploy_tenant" "tenants" {
  for_each    = local.tenants
  name        = each.key
  description = "Mock tenant."
  tenant_tags = [for t in each.value : octopusdeploy_tag.tags[t].canonical_tag_name]
}

# The project must allow tenanted deployments before tenants can connect to it.
resource "octopusdeploy_tenant_project" "connections" {
  for_each        = octopusdeploy_tenant.tenants
  tenant_id       = each.value.id
  project_id      = local.project_id
  environment_ids = local.all_environment_ids
}
