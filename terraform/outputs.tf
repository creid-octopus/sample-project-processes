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
