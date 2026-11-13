# One Cloud Region target stands in for every machine at first. It needs no real
# server, and it counts as one machine against the license. Steps that run on
# targets execute their scripts on the worker pool, so deployments really run.
#
# It is registered for every environment and every tenant, and carries every role
# the process uses. Later we add more targets to test splits (servers and
# workstations, per environment) and unavailable machines.
#
# Workers: "Local Container" is a static pool for a polling Tentacle worker that runs
# in a container on the owner's machine. Terraform creates the pool. The worker
# registers itself into it. Until a worker is healthy in the pool, keep
# var.target_worker_pool_name on "Hosted Ubuntu".
resource "octopusdeploy_static_worker_pool" "local_container" {
  name        = "Local Container"
  description = "Polling worker running in a local container."
  is_default  = false
}

data "octopusdeploy_worker_pools" "target_pool" {
  partial_name = var.target_worker_pool_name

  depends_on = [octopusdeploy_static_worker_pool.local_container]
}

locals {
  target_worker_pool_id = one([for p in data.octopusdeploy_worker_pools.target_pool.worker_pools : p.id if p.name == var.target_worker_pool_name])
}

resource "octopusdeploy_cloud_region_deployment_target" "all" {
  name                              = "mock-target-all"
  environments                      = sort(local.all_environment_ids)
  roles                             = ["app-server", "db-server", "workstation"]
  default_worker_pool_id            = local.target_worker_pool_id
  tenanted_deployment_participation = "Tenanted"
  tenants                           = sort([for t in octopusdeploy_tenant.tenants : t.id])

  # Tenant connections must exist before the target can name the tenants.
  depends_on = [octopusdeploy_tenant_project.connections]
}
