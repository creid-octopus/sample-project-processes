<#
.SYNOPSIS
    Generates deployment_process.ocl, variables.ocl and an expected result from a definition file.

.DESCRIPTION
    The definition is the expected result. The export script is tested by comparing
    its output with the expected JSON file.

    Every step is a dummy bash script. Each script body holds a marker string so the
    privacy tests can prove that no script text reaches the export.

    The OCL follows the layout the Octopus UI writes when it saves a process: attributes in
    alphabetical order, and no RunOnServer property for steps that use a worker pool. That
    keeps a save from the UI from rewriting the whole file.

    Group options (all optional):
      count, layout (sequential|parallel), joinPrevious, actionsPerStep, intoPreviousStep,
      numberFrom, numbered, runsOn (worker|targets), targetRole, tenantTags, environments,
      excludedEnvironments, channels, condition, conditionExpression, maxParallelism,
      isDisabled, isRequired, setsOutput, readsOutput, readsOutputFrom, failsWhenVariable,
      autoRetry {maximumCount, minimumBackoff}, package {feed, packageId, acquisition,
      mode (script|reference), reference}, packageRequirement.

    intoPreviousStep: every step of the group becomes an extra action of the step before it.

.PARAMETER Definition
    Path to the definition JSON file.

.PARAMETER OutputFolder
    Where to write the OCL files. Default: the project folder under .octopus.

.PARAMETER ExpectedPath
    Where to write the expected JSON. Default: expected/<definition name>.expected.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Definition,

    [string]$OutputFolder = (Join-Path $PSScriptRoot "../.octopus/large-process-multi-tenant"),

    [string]$ExpectedPath
)

$ErrorActionPreference = "Stop"

function ConvertTo-OclString {
    param([string]$Text)
    # JSON string escaping is valid in OCL strings.
    return (ConvertTo-Json -InputObject $Text -Compress)
}

function Get-Prop {
    param($Object, [string]$Name, $Default = $null)
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    return $p.Value
}

function Get-Slug {
    param([string]$Text)
    return ($Text.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
}

function Format-OclList {
    param($Items)
    return "[" + ((@($Items) | ForEach-Object { ConvertTo-OclString $_ }) -join ", ") + "]"
}

function Get-TitleFromSlug {
    param([string]$Slug)
    return (($Slug -split '-') | ForEach-Object { if ($_ -match '^\d+$') { $_ } else { (Get-Culture).TextInfo.ToTitleCase($_) } }) -join ' '
}

$def = Get-Content -LiteralPath $Definition -Raw | ConvertFrom-Json
$workerPoolSlug = Get-Prop $def "workerPool" "hosted-ubuntu"

# ---------------------------------------------------------------------------
# Pass 1: build steps in memory. A step holds one or more actions.
# ---------------------------------------------------------------------------

$steps = New-Object System.Collections.Generic.List[object]
$wave = 0

foreach ($group in $def.groups) {
    $count = [int](Get-Prop $group "count" 1)
    $actionsPerStep = [int](Get-Prop $group "actionsPerStep" 1)
    $layout = Get-Prop $group "layout" "sequential"
    $joinPrevious = [bool](Get-Prop $group "joinPrevious" $false)
    $intoPrevious = [bool](Get-Prop $group "intoPreviousStep" $false)
    $numberFrom = [int](Get-Prop $group "numberFrom" 1)
    $forceNumber = [bool](Get-Prop $group "numbered" $false)
    $runsOn = Get-Prop $group "runsOn" "worker"
    $condition = Get-Prop $group "condition" "Success"
    $conditionExpression = Get-Prop $group "conditionExpression" $null
    $maxParallelism = Get-Prop $group "maxParallelism" $null
    $packageRequirement = Get-Prop $group "packageRequirement" $null
    $targetRole = Get-Prop $group "targetRole" $null
    $package = Get-Prop $group "package" $null

    for ($i = 1; $i -le $count; $i++) {
        $number = $numberFrom + $i - 1
        $stepName = if ($count -gt 1 -or $forceNumber) { "{0} {1:00}" -f $group.name, $number } else { $group.name }
        $stepSlug = Get-Slug $stepName

        $hostStep = $null
        if ($intoPrevious -and $steps.Count -gt 0) {
            $hostStep = $steps[$steps.Count - 1]
        }
        else {
            # Parallel groups: the first step waits for the previous step unless joinPrevious is set.
            $parallelWithPrevious = (($layout -eq "parallel") -and ($i -gt 1)) -or ($joinPrevious -and ($i -eq 1) -and ($steps.Count -gt 0))
            if (-not $parallelWithPrevious) { $wave++ }
            $hostStep = [pscustomobject]@{
                Number               = $steps.Count + 1
                Name                 = $stepName
                Slug                 = $stepSlug
                Wave                 = $wave
                ParallelWithPrevious = $parallelWithPrevious
                Condition            = $condition
                ConditionExpression  = $conditionExpression
                MaxParallelism       = $maxParallelism
                PackageRequirement   = $packageRequirement
                TargetRole           = if ($runsOn -eq "targets") { $targetRole } else { $null }
                Actions              = (New-Object System.Collections.Generic.List[object])
            }
            $steps.Add($hostStep)
        }

        for ($a = 1; $a -le $actionsPerStep; $a++) {
            $actionName = if ($actionsPerStep -gt 1) { "$stepName - Action $a" } else { $stepName }
            $hostStep.Actions.Add([pscustomobject]@{
                Name                 = $actionName
                Slug                 = Get-Slug $actionName
                RunsOn               = $runsOn
                Tags                 = @(Get-Prop $group "tenantTags" @())
                Environments         = @(Get-Prop $group "environments" @())
                ExcludedEnvironments = @(Get-Prop $group "excludedEnvironments" @())
                Channels             = @(Get-Prop $group "channels" @())
                IsDisabled           = [bool](Get-Prop $group "isDisabled" $false)
                IsRequired           = [bool](Get-Prop $group "isRequired" $false)
                SetsOutput           = Get-Prop $group "setsOutput" $null
                ReadsOutput          = Get-Prop $group "readsOutput" $null
                ReadsOutputFrom      = Get-Prop $group "readsOutputFrom" $null
                FailsWhenVariable    = Get-Prop $group "failsWhenVariable" $null
                AutoRetry            = Get-Prop $group "autoRetry" $null
                Package              = $package
            })
        }
    }
}

# ---------------------------------------------------------------------------
# Pass 2: render OCL and the expected rows
# ---------------------------------------------------------------------------

$ocl = New-Object System.Text.StringBuilder
$expectedRows = New-Object System.Collections.Generic.List[object]

foreach ($step in $steps) {
    $multi = ($step.Actions.Count -gt 1)

    [void]$ocl.AppendLine("step $(ConvertTo-OclString $step.Slug) {")
    if ($step.Condition -ne "Success") { [void]$ocl.AppendLine("    condition = $(ConvertTo-OclString $step.Condition)") }
    [void]$ocl.AppendLine("    name = $(ConvertTo-OclString $step.Name)")
    if ($step.PackageRequirement) { [void]$ocl.AppendLine("    package_requirement = $(ConvertTo-OclString $step.PackageRequirement)") }

    $stepProps = New-Object System.Collections.Generic.List[string]
    if ($step.MaxParallelism) { $stepProps.Add("        Octopus.Action.MaxParallelism = $(ConvertTo-OclString $step.MaxParallelism)") }
    if ($step.TargetRole) { $stepProps.Add("        Octopus.Action.TargetRoles = $(ConvertTo-OclString $step.TargetRole)") }
    if ($step.ConditionExpression) { $stepProps.Add("        Octopus.Step.ConditionVariableExpression = $(ConvertTo-OclString $step.ConditionExpression)") }
    if ($stepProps.Count -gt 0) {
        [void]$ocl.AppendLine("    properties = {")
        foreach ($line in $stepProps) { [void]$ocl.AppendLine($line) }
        [void]$ocl.AppendLine("    }")
    }
    if ($step.ParallelWithPrevious) { [void]$ocl.AppendLine('    start_trigger = "StartWithPrevious"') }

    $actionIndex = 0
    foreach ($act in $step.Actions) {
        $actionIndex++
        $label = if ($multi) { "$($step.Number).$actionIndex" } else { "$($step.Number)" }
        $package = $act.Package
        $packageMode = if ($package) { Get-Prop $package "mode" "script" } else { $null }
        $marker = "SCRIPT-MARKER-$($act.Slug)"

        [void]$ocl.AppendLine("")
        if ($multi) { [void]$ocl.AppendLine("    action $(ConvertTo-OclString $act.Slug) {") } else { [void]$ocl.AppendLine("    action {") }
        [void]$ocl.AppendLine('        action_type = "Octopus.Script"')
        if ($act.Channels.Count -gt 0) { [void]$ocl.AppendLine("        channels = $(Format-OclList $act.Channels)") }
        if ($act.Environments.Count -gt 0) { [void]$ocl.AppendLine("        environments = $(Format-OclList $act.Environments)") }
        if ($act.ExcludedEnvironments.Count -gt 0) { [void]$ocl.AppendLine("        excluded_environments = $(Format-OclList $act.ExcludedEnvironments)") }
        if ($act.IsDisabled) { [void]$ocl.AppendLine("        is_disabled = true") }
        if ($act.IsRequired) { [void]$ocl.AppendLine("        is_required = true") }
        if ($multi) { [void]$ocl.AppendLine("        name = $(ConvertTo-OclString $act.Name)") }

        [void]$ocl.AppendLine("        properties = {")
        if ($act.AutoRetry) {
            [void]$ocl.AppendLine("            Octopus.Action.AutoRetry.MaximumCount = $(ConvertTo-OclString ([string]$act.AutoRetry.maximumCount))")
            [void]$ocl.AppendLine("            Octopus.Action.AutoRetry.MinimumBackoff = $(ConvertTo-OclString ([string]$act.AutoRetry.minimumBackoff))")
        }
        if ($packageMode -eq "script") {
            $downloadOnTentacle = if ((Get-Prop $package "acquisition" "Server") -eq "ExecutionTarget") { "True" } else { "False" }
            [void]$ocl.AppendLine("            Octopus.Action.Package.DownloadOnTentacle = $(ConvertTo-OclString $downloadOnTentacle)")
            [void]$ocl.AppendLine("            Octopus.Action.Package.FeedId = $(ConvertTo-OclString $package.feed)")
            [void]$ocl.AppendLine("            Octopus.Action.Package.PackageId = $(ConvertTo-OclString $package.packageId)")
        }
        # The UI leaves RunOnServer out for steps that use a worker pool.
        if ($act.RunsOn -eq "targets") { [void]$ocl.AppendLine('            Octopus.Action.RunOnServer = "false"') }

        if ($packageMode -eq "script") {
            [void]$ocl.AppendLine('            Octopus.Action.Script.ScriptFileName = "run.sh"')
            [void]$ocl.AppendLine('            Octopus.Action.Script.ScriptSource = "Package"')
        }
        else {
            # A package is linked in one of two ways, because an inline script cannot carry an unnamed package:
            #   mode "script"    the script runs from the package (ScriptSource Package, linked by properties)
            #   mode "reference" an inline script with a named, referenced package
            $body = New-Object System.Collections.Generic.List[string]
            $body.Add("echo $marker")
            if ($act.SetsOutput) { $body.Add("set_octopusvariable `"$($act.SetsOutput)`" `"value-$($act.Slug)`"") }
            if ($act.FailsWhenVariable) {
                # Test hook: the step fails on purpose when the variable is "true".
                $body.Add("if [ `"#{$($act.FailsWhenVariable)}`" = `"true`" ]; then echo `"simulated failure`"; exit 1; fi")
            }
            if ($act.ReadsOutput -and $act.ReadsOutputFrom) {
                $body.Add("echo `"#{Octopus.Action[$(Get-TitleFromSlug $act.ReadsOutputFrom)].Output.$($act.ReadsOutput)}`"")
            }
            if ($body.Count -eq 1) {
                # The UI writes a one-line script as a plain string with four leading spaces.
                [void]$ocl.AppendLine("            Octopus.Action.Script.ScriptBody = $(ConvertTo-OclString ('    ' + $body[0]))")
            }
            else {
                [void]$ocl.AppendLine("            Octopus.Action.Script.ScriptBody = <<-EOT")
                foreach ($line in $body) { [void]$ocl.AppendLine("                    $line") }
                [void]$ocl.AppendLine("                EOT")
            }
            [void]$ocl.AppendLine('            Octopus.Action.Script.ScriptSource = "Inline"')
            [void]$ocl.AppendLine('            Octopus.Action.Script.Syntax = "Bash"')
        }
        [void]$ocl.AppendLine("        }")

        if ($act.Tags.Count -gt 0) { [void]$ocl.AppendLine("        tenant_tags = $(Format-OclList $act.Tags)") }
        if ($act.RunsOn -ne "targets") { [void]$ocl.AppendLine("        worker_pool = $(ConvertTo-OclString $workerPoolSlug)") }

        if ($package) {
            [void]$ocl.AppendLine("")
            $referenceName = Get-Prop $package "reference" "reference-package"
            if ($packageMode -eq "reference") { [void]$ocl.AppendLine("        packages $(ConvertTo-OclString $referenceName) {") }
            else { [void]$ocl.AppendLine("        packages {") }
            [void]$ocl.AppendLine("            acquisition_location = $(ConvertTo-OclString (Get-Prop $package 'acquisition' 'Server'))")
            [void]$ocl.AppendLine("            feed = $(ConvertTo-OclString $package.feed)")
            [void]$ocl.AppendLine("            package_id = $(ConvertTo-OclString $package.packageId)")
            [void]$ocl.AppendLine("            properties = {")
            if ($packageMode -eq "reference") {
                [void]$ocl.AppendLine('                Extract = "False"')
                [void]$ocl.AppendLine('                Purpose = ""')
            }
            [void]$ocl.AppendLine('                SelectionMode = "immediate"')
            [void]$ocl.AppendLine("            }")
            [void]$ocl.AppendLine("        }")
        }
        [void]$ocl.AppendLine("    }")

        $expectedRows.Add([pscustomobject][ordered]@{
            number                 = $step.Number
            label                  = $label
            stepName               = $step.Name
            name                   = $act.Name
            wave                   = $step.Wave
            parallelWithPrevious   = $step.ParallelWithPrevious
            runCondition           = $step.Condition
            hasConditionExpression = [bool]$step.ConditionExpression
            maxParallelism         = $step.MaxParallelism
            runsOn                 = if ($act.RunsOn -eq "targets") { "Targets" } else { "Worker" }
            targetRole             = $step.TargetRole
            tenantTags             = $act.Tags
            environments           = $act.Environments
            excludedEnvironments   = $act.ExcludedEnvironments
            channels               = $act.Channels
            isDisabled             = $act.IsDisabled
            isRequired             = $act.IsRequired
            setsOutput             = $act.SetsOutput
            readsOutputFrom        = if ($act.ReadsOutput) { $act.ReadsOutputFrom } else { $null }
            autoRetry              = if ($act.AutoRetry) { [pscustomobject][ordered]@{ maximumCount = [int]$act.AutoRetry.maximumCount; minimumBackoff = [int]$act.AutoRetry.minimumBackoff } } else { $null }
            packageRequirement     = if ($step.PackageRequirement) { $step.PackageRequirement } else { "LetOctopusDecide" }
            packageCount           = if ($package) { 1 } else { 0 }
            packageReference       = if ($package) { if ($packageMode -eq "reference") { Get-Prop $package "reference" "reference-package" } else { "(primary)" } } else { $null }
            packageAcquisition     = if ($package) { Get-Prop $package "acquisition" "Server" } else { $null }
            marker                 = $marker
        })
    }
    [void]$ocl.AppendLine("}")
    [void]$ocl.AppendLine("")
}

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

$vocl = New-Object System.Text.StringBuilder
$varCount = 0; $varScoped = 0; $varPrompted = 0; $varStepOutput = 0
$scopeTypeCounts = @{}

foreach ($vg in @(Get-Prop $def "variables" @())) {
    $vcount = [int](Get-Prop $vg "count" 1)
    $values = @(Get-Prop $vg "values" @([pscustomobject]@{}))
    $prompt = [bool](Get-Prop $vg "prompted" $false)
    $vReadsFrom = Get-Prop $vg "readsOutputFrom" $null
    $vReads = Get-Prop $vg "readsOutput" $null
    $fixedValue = Get-Prop $vg "value" "dummy"
    $exactValue = [bool](Get-Prop $vg "exactValue" $false)

    for ($n = 1; $n -le $vcount; $n++) {
        $vname = if ($vcount -gt 1) { "{0}.{1:00}" -f $vg.prefix, $n } else { $vg.prefix }
        [void]$vocl.AppendLine("variable $(ConvertTo-OclString $vname) {")
        $first = $true
        foreach ($val in $values) {
            if (-not $first) { [void]$vocl.AppendLine("") }
            $first = $false
            $text = if ($vReadsFrom -and $vReads) { "#{Octopus.Action[$(Get-TitleFromSlug $vReadsFrom)].Output.$vReads}" } else { $(if ($exactValue) { $fixedValue } else { "$fixedValue-$n" }) }
            $scopeLines = New-Object System.Collections.Generic.List[string]
            $scopeNames = @()
            foreach ($scopeKey in @("environment", "channel")) {
                $sv = @(Get-Prop $val $scopeKey @())
                if ($sv.Count -gt 0) {
                    $scopeLines.Add("        $scopeKey = $(Format-OclList $sv)")
                    $scopeNames += ($scopeKey.Substring(0, 1).ToUpper() + $scopeKey.Substring(1))
                }
            }
            $hasBody = ($scopeLines.Count -gt 0) -or $prompt
            if ($hasBody) { [void]$vocl.AppendLine("    value $(ConvertTo-OclString $text) {") } else { [void]$vocl.AppendLine("    value $(ConvertTo-OclString $text) {}") }
            foreach ($line in $scopeLines) { [void]$vocl.AppendLine($line) }
            if ($prompt) {
                if ($scopeLines.Count -gt 0) { [void]$vocl.AppendLine("") }
                [void]$vocl.AppendLine("        prompt {")
                [void]$vocl.AppendLine("            description = `"`"")
                [void]$vocl.AppendLine("            label = $(ConvertTo-OclString $vname)")
                [void]$vocl.AppendLine("        }")
            }
            if ($hasBody) { [void]$vocl.AppendLine("    }") }

            $varCount++
            if ($scopeNames.Count -gt 0) { $varScoped++ }
            foreach ($sn in $scopeNames) { if (-not $scopeTypeCounts.ContainsKey($sn)) { $scopeTypeCounts[$sn] = 0 }; $scopeTypeCounts[$sn]++ }
            if ($prompt) { $varPrompted++ }
            if ($vReadsFrom -and $vReads) { $varStepOutput++ }
        }
        [void]$vocl.AppendLine("}")
        [void]$vocl.AppendLine("")
    }
}

# ---------------------------------------------------------------------------
# Write files
# ---------------------------------------------------------------------------

function Write-Unix {
    param([string]$Path, [string]$Text, [switch]$NoTrailingNewline)
    $clean = $Text.TrimEnd().Replace("`r`n", "`n")
    if ($clean.Length -gt 0 -and -not $NoTrailingNewline) { $clean += "`n" }
    [System.IO.File]::WriteAllText($Path, $clean, (New-Object System.Text.UTF8Encoding($false)))
}

New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
$oclPath = Join-Path $OutputFolder "deployment_process.ocl"
# The UI does not end the process file with a newline, so neither do we.
Write-Unix $oclPath $ocl.ToString() -NoTrailingNewline
$varPath = Join-Path $OutputFolder "variables.ocl"
Write-Unix $varPath $vocl.ToString()

$rows = $expectedRows.ToArray()
$waveGroups = @($rows | Group-Object -Property wave)
$stepsDistinct = $steps.Count
# The largest wave counts steps, not actions.
$largestSteps = ($waveGroups | ForEach-Object { @($_.Group | Select-Object -ExpandProperty number -Unique).Count } | Measure-Object -Maximum).Maximum

function ConvertTo-SortedMap {
    param($Map)
    $sorted = [ordered]@{}
    foreach ($key in ($Map.Keys | Sort-Object)) { $sorted[$key] = $Map[$key] }
    return $sorted
}

$tagUse = @{}
foreach ($r in $rows) { foreach ($t in $r.tenantTags) { if (-not $tagUse.ContainsKey($t)) { $tagUse[$t] = 0 }; $tagUse[$t]++ } }
$tagUse = ConvertTo-SortedMap $tagUse
$scopeTypeCounts = ConvertTo-SortedMap $scopeTypeCounts

$expected = [ordered]@{
    definition      = (Split-Path -Leaf $Definition)
    counts          = [ordered]@{
        steps         = $stepsDistinct
        actions       = $rows.Count
        waves         = $waveGroups.Count
        largestWave   = [int]$largestSteps
        taggedActions = @($rows | Where-Object { $_.tenantTags.Count -gt 0 }).Count
        disabled      = @($rows | Where-Object { $_.isDisabled }).Count
        required      = @($rows | Where-Object { $_.isRequired }).Count
        withCondition = @($rows | Where-Object { $_.runCondition -ne "Success" }).Count
        withPackage   = @($rows | Where-Object { $_.packageCount -gt 0 }).Count
        withAutoRetry = @($rows | Where-Object { $_.autoRetry }).Count
        multiActionSteps = @($rows | Group-Object -Property number | Where-Object { $_.Count -gt 1 }).Count
    }
    variables       = [ordered]@{
        projectVariableCount  = $varCount
        scopedCount           = $varScoped
        promptedCount         = $varPrompted
        referencingStepOutput = $varStepOutput
        countByScopeType      = $scopeTypeCounts
    }
    actionsUsingTag = $tagUse
    steps           = $rows
}

if (-not $ExpectedPath) {
    $dir = Join-Path $PSScriptRoot "../expected"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $ExpectedPath = Join-Path $dir ((Split-Path -Leaf $Definition) -replace '\.json$', '.expected.json')
}
$expected | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ExpectedPath -Encoding UTF8

Write-Host "Wrote $oclPath"
Write-Host "Wrote $varPath"
Write-Host "Wrote $ExpectedPath"
Write-Host ("Steps: {0}  Actions: {1}  Waves: {2}  Largest wave: {3}  Variables: {4}" -f $stepsDistinct, $rows.Count, $waveGroups.Count, $largestSteps, $varCount)
