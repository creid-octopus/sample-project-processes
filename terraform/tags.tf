# Six generic tag sets that mirror the shape we need to test: several sets,
# several tags each, steps gated by one tag or by tags from more than one set.
# The names are deliberately generic.
locals {
  tag_sets = {
    "Module Pack"     = ["Module A", "Module B", "Module C", "Module D", "Module E", "Module F"]
    "Integration"     = ["Integration 1", "Integration 2", "Integration 3"]
    "Host Type"       = ["Server Only", "Server And Workstation"]
    "Pre-release"     = ["Beta Program"]
    "Rollout Control" = ["Hold", "Fast Track"]
    "Hardening"       = ["Enhanced"]
  }

  tags = merge([
    for set_name, tag_names in local.tag_sets : {
      for tag_name in tag_names : "${set_name}/${tag_name}" => {
        set = set_name
        tag = tag_name
      }
    }
  ]...)
}

resource "octopusdeploy_tag_set" "sets" {
  for_each = local.tag_sets
  name     = each.key
}

resource "octopusdeploy_tag" "tags" {
  for_each   = local.tags
  name       = each.value.tag
  color      = "#2F7DB5"
  tag_set_id = octopusdeploy_tag_set.sets[each.value.set].id
}

# Target tags. Servers and workstations are told apart by this tag set.
resource "octopusdeploy_tag_set" "machine_type" {
  name        = "Machine Type"
  description = "Whether a deployment target is a server or a workstation."
  type        = "MultiSelect"
  scopes      = ["Target"]
}

# Target tag names must be unique across all target tag sets, ignoring case. A tag
# named "Workstation" clashes with the "workstation" role in Default Target Tags, and the
# provider then crashes (nil pointer) instead of reporting the error. So the tag names
# carry a "Machine" suffix.
resource "octopusdeploy_tag" "machine_server" {
  name       = "Server Machine"
  color      = "#5B8DEF"
  tag_set_id = octopusdeploy_tag_set.machine_type.id
}

resource "octopusdeploy_tag" "machine_workstation" {
  name       = "Workstation Machine"
  color      = "#E58F3A"
  tag_set_id = octopusdeploy_tag_set.machine_type.id
}
