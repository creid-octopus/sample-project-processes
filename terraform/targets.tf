# One Cloud Region target stands in for every machine at first. It needs no real
# server, and it counts as one machine against the license. Steps that run on
# targets execute their scripts on the worker pool, so deployments really run.
#
# It is registered for every environment and every tenant, and carries every role
# the process uses. Later we add more targets to test splits (servers and
# workstations, per environment) and unavailable machines.
data "octopusdeploy_worker_pools" "hosted_ubuntu" {
  partial_name = "Hosted Ubuntu"
}

locals {
  hosted_ubuntu_pool_id = one([for p in data.octopusdeploy_worker_pools.hosted_ubuntu.worker_pools : p.id if p.name == "Hosted Ubuntu"])
}

resource "octopusdeploy_cloud_region_deployment_target" "all" {
  name                              = "mock-target-all"
  environments                      = local.all_environment_ids
  roles                             = ["app-server", "db-server", "workstation"]
  default_worker_pool_id            = local.hosted_ubuntu_pool_id
  tenanted_deployment_participation = "Tenanted"
  tenants                           = [for t in octopusdeploy_tenant.tenants : t.id]

  # Tenant connections must exist before the target can name the tenants.
  depends_on = [octopusdeploy_tenant_project.connections]
}
