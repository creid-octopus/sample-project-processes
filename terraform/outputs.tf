output "space_id" {
  value = var.space_id
}

output "project_id" {
  value = local.project_id
}

output "tenant_count" {
  value = length(octopusdeploy_tenant.tenants)
}

# Expected tag usage, for comparing with the export. Each entry is how many tenants carry the tag.
output "expected_tenants_per_tag" {
  value = {
    for tag_key in keys(local.tags) : tag_key => length([for t, tags in local.tenants : t if contains(tags, tag_key)])
  }
}

# Expected target inventory, for comparing with the export.
output "expected_targets" {
  value = {
    total                        = length(local.servers) + length(local.workstations)
    servers                      = length(local.servers)
    workstations                 = length(local.workstations)
    disabled                     = length(local.disabled_workstations)
    targets_per_tenant           = { for tenant, n in local.workstations_per_tenant : tenant => n + 1 }
    environments_per_server      = length(local.all_environment_ids)
    environments_per_workstation = 2
  }
}
