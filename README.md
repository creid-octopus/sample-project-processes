# Sample project processes

A mock multi-tenant Octopus Deploy project used to test a process export script. The mock reproduces the structure around the steps: tenant tags, parallel groups, run conditions, channels, scoping, and package acquisition. Every step is a dummy script.

Nothing here comes from a real customer. Names are generic.

## Layout

| Path | Purpose |
|---|---|
| `.octopus/large-process-multi-tenant/` | Config as Code files for the project. `deployment_process.ocl` is generated. |
| `generator/` | Turns a small definition file into `deployment_process.ocl` and an expected result. |
| `expected/` | What the export script must report for each definition. Generated. |
| `terraform/` | Everything around the process: environments, lifecycles, tag sets, tenants, channels. |

## How the pieces fit

1. The project `Large Process - Multi Tenant` exists in the `multi-tenant-testing` space. It was created in the UI with Config as Code and points at this repository.
2. `terraform/` reads that project and manages the rest of the space.
3. `generator/New-ProcessOcl.ps1` writes the deployment process. Edit the definition, not the OCL.
4. Push to `main`. Octopus reads the new process from Git.
5. Run the export script against the space. Compare its output with `expected/`.

Terraform does not manage the deployment process. The provider docs advise against it.

## Setup

Needs Terraform 1.5 or later and PowerShell 7.

```bash
# Set the key in your shell. Never write it to a file.
export TF_VAR_octopus_api_key="API-XXXX"

cd terraform
terraform init
terraform plan
terraform apply
```

The key belongs to an identity with permissions in the `multi-tenant-testing` space only. The workspace is locked to that space ID in `variables.tf`.

One manual step: open the project in the UI and set **Tenanted deployments** to `Require a tenant for every deployment` (or `Allow`). Tenants cannot connect to the project until this is set. Terraform does not change the project itself because Config as Code projects keep part of their settings in Git.

## Generate a process

```bash
pwsh generator/New-ProcessOcl.ps1 -Definition generator/definition.large.json   # 200 steps, 203 actions
pwsh generator/New-ProcessOcl.ps1 -Definition generator/definition.small.json   # 26 steps
```

Each group in the definition becomes one or more steps.

| Field | Meaning |
|---|---|
| `count`, `layout` | Number of steps. `sequential` or `parallel`. In a parallel group every step after the first starts with the previous step. |
| `runsOn` | `worker` or `targets` (with `targetRole`). |
| `tenantTags` | Tags that limit where the step runs, as `Tag Set/Tag`. |
| `condition`, `conditionExpression` | `Success`, `Failure`, `Always`, or `Variable` with an expression. |
| `environments`, `excludedEnvironments`, `channels` | Scoping, by slug. |
| `maxParallelism` | Number or variable expression. |
| `isDisabled`, `isRequired` | Flags. |
| `package` | A package reference with feed, ID, and acquisition location. |
| `setsOutput`, `readsOutput`, `readsOutputFrom` | Output variable dependencies. |
| `actionsPerStep` | Number of actions in each step. More than one makes a multi action step. |
| `joinPrevious` | The group's first step starts with the previous step, so a wave can span two groups. |
| `variables` (top level) | Project variables: `count`, `prefix`, `values` (each with `environment` or `channel` scope), `prompted`, and step output references. Written to `variables.ocl`. |

Each script body holds a marker string such as `SCRIPT-MARKER-core-prep-01`. The privacy tests search the export for these markers.

## Mock tenants

The instance license allows 10 tenants across all spaces, so this space has 5. Their tags are listed by hand in `terraform/tenants.tf` and together cover every tag.

| Tenant | Tags |
|---|---|
| Tenant Alpha | Module A, Server Only |
| Tenant Bravo | Modules A to C, Integration 1, Server And Workstation, Enhanced |
| Tenant Charlie | All six modules, all three integrations, Server And Workstation, Hold |
| Tenant Delta | Modules A and D, Integration 2, Server Only, Beta Program, Fast Track |
| Tenant Echo | Modules A and B, Server And Workstation, Beta Program, Enhanced, Hold |

`terraform output expected_tenants_per_tag` prints the expected count for each tag.

## Not built yet

* Version rules on channels. They refer to steps by name, so they come after the process settles.
* Deployment targets, for the target and offline cases.
* Telemetry data: releases and scheduled deployments, including failures and redeploys.
* Comparison scripts and the privacy checks.

## Safety

* Never commit state, variable files, API keys, export folders, or alias maps. `.gitignore` covers them.
* Run `terraform plan` before every `apply`.
