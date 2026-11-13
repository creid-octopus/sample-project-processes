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
