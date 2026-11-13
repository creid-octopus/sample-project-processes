# Cloud Region targets stand in for real machines. They need no server and are not
# counted against the machine license. Steps that run on targets execute their
# scripts on the worker pool, so deployments really run.
#
# Each tenant has one server and a few workstations, like a county office. The
# "Machine Type" tag set (scope Target) says which is which. One workstation is
# disabled, to model a machine that is out of service.
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

locals {
  # Workstations per tenant. Charlie is the large office.
  workstations_per_tenant = {
    "Tenant Alpha"   = 2
    "Tenant Bravo"   = 3
    "Tenant Charlie" = 4
    "Tenant Delta"   = 2
    "Tenant Echo"    = 3
  }

  # One workstation that is out of service.
  disabled_workstations = ["tenant-charlie-ws-04"]

  servers = {
    for tenant, _ in local.workstations_per_tenant :
    "${lower(replace(tenant, " ", "-"))}-server" => tenant
  }

  workstations = merge([
    for tenant, count in local.workstations_per_tenant : {
      for n in range(1, count + 1) :
      format("%s-ws-%02d", lower(replace(tenant, " ", "-")), n) => tenant
    }
  ]...)
}

resource "octopusdeploy_cloud_region_deployment_target" "server" {
  for_each                          = local.servers
  name                              = each.key
  environments                      = sort(local.all_environment_ids)
  roles                             = ["app-server", "db-server", "Machine Type/Server Machine"]
  default_worker_pool_id            = local.target_worker_pool_id
  tenanted_deployment_participation = "Tenanted"
  tenants                           = [octopusdeploy_tenant.tenants[each.value].id]

  depends_on = [octopusdeploy_tenant_project.connections, octopusdeploy_tag.machine_server]
}

resource "octopusdeploy_cloud_region_deployment_target" "workstation" {
  for_each                          = local.workstations
  name                              = each.key
  environments                      = sort([octopusdeploy_environment.lab.id, octopusdeploy_environment.production.id])
  roles                             = ["Machine Type/Workstation Machine", "workstation"]
  default_worker_pool_id            = local.target_worker_pool_id
  tenanted_deployment_participation = "Tenanted"
  tenants                           = [octopusdeploy_tenant.tenants[each.value].id]
  is_disabled                       = contains(local.disabled_workstations, each.key)

  depends_on = [octopusdeploy_tenant_project.connections, octopusdeploy_tag.machine_workstation]
}
