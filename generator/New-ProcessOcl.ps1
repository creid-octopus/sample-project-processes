<#
.SYNOPSIS
    Generates deployment_process.ocl, variables.ocl and an expected result from a definition file.

.DESCRIPTION
    The definition is the expected result. The export script is tested by comparing
    its output with the expected JSON file.

    Every step is a dummy bash script. Each script body holds a marker string so the
    privacy tests can prove that no script text reaches the export.

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
$ocl = New-Object System.Text.StringBuilder
$expectedRows = New-Object System.Collections.Generic.List[object]

$workerPoolSlug = Get-Prop $def "workerPool" "hosted-ubuntu"
$stepNumber = 0
$wave = 0

foreach ($group in $def.groups) {
    $count = [int](Get-Prop $group "count" 1)
    $actionsPerStep = [int](Get-Prop $group "actionsPerStep" 1)
    $layout = Get-Prop $group "layout" "sequential"
    $joinPrevious = [bool](Get-Prop $group "joinPrevious" $false)
    $runsOn = Get-Prop $group "runsOn" "worker"
    $tags = @(Get-Prop $group "tenantTags" @())
    $envs = @(Get-Prop $group "environments" @())
    $excludedEnvs = @(Get-Prop $group "excludedEnvironments" @())
    $channels = @(Get-Prop $group "channels" @())
    $condition = Get-Prop $group "condition" "Success"
    $conditionExpression = Get-Prop $group "conditionExpression" $null
    $maxParallelism = Get-Prop $group "maxParallelism" $null
    $isDisabled = [bool](Get-Prop $group "isDisabled" $false)
    $isRequired = [bool](Get-Prop $group "isRequired" $false)
    $setsOutput = Get-Prop $group "setsOutput" $null
    $readsOutput = Get-Prop $group "readsOutput" $null
    $readsOutputFrom = Get-Prop $group "readsOutputFrom" $null
    $package = Get-Prop $group "package" $null
    $packageRequirement = Get-Prop $group "packageRequirement" $null
    $targetRole = Get-Prop $group "targetRole" $null
    $failsWhenVariable = Get-Prop $group "failsWhenVariable" $null

    for ($i = 1; $i -le $count; $i++) {
        $stepNumber++
        $stepName = if ($count -gt 1) { "{0} {1:00}" -f $group.name, $i } else { $group.name }
        $stepSlug = Get-Slug $stepName

        # Parallel groups: the first step waits for the previous step unless joinPrevious is set.
        # The rest start with the step before them.
        $parallelWithPrevious = (($layout -eq "parallel") -and ($i -gt 1)) -or ($joinPrevious -and ($i -eq 1) -and ($stepNumber -gt 1))
        if (-not $parallelWithPrevious) { $wave++ }

        [void]$ocl.AppendLine("step $(ConvertTo-OclString $stepSlug) {")
        [void]$ocl.AppendLine("    name = $(ConvertTo-OclString $stepName)")
        if ($condition -ne "Success") { [void]$ocl.AppendLine("    condition = $(ConvertTo-OclString $condition)") }
        if ($packageRequirement) { [void]$ocl.AppendLine("    package_requirement = $(ConvertTo-OclString $packageRequirement)") }

        $stepProps = New-Object System.Collections.Generic.List[string]
        if ($conditionExpression) { $stepProps.Add("        Octopus.Step.ConditionVariableExpression = $(ConvertTo-OclString $conditionExpression)") }
        if ($maxParallelism) { $stepProps.Add("        Octopus.Action.MaxParallelism = $(ConvertTo-OclString $maxParallelism)") }
        if ($runsOn -eq "targets" -and $targetRole) { $stepProps.Add("        Octopus.Action.TargetRoles = $(ConvertTo-OclString $targetRole)") }
        if ($stepProps.Count -gt 0) {
            [void]$ocl.AppendLine("    properties = {")
            foreach ($line in $stepProps) { [void]$ocl.AppendLine($line) }
            [void]$ocl.AppendLine("    }")
        }
        if ($parallelWithPrevious) { [void]$ocl.AppendLine('    start_trigger = "StartWithPrevious"') }

        for ($a = 1; $a -le $actionsPerStep; $a++) {
            $multi = ($actionsPerStep -gt 1)
            $actionName = if ($multi) { "$stepName - Action $a" } else { $stepName }
            $actionSlug = Get-Slug $actionName
            $label = if ($multi) { "$stepNumber.$a" } else { "$stepNumber" }

            [void]$ocl.AppendLine("")
            if ($multi) { [void]$ocl.AppendLine("    action $(ConvertTo-OclString $actionSlug) {") }
            else { [void]$ocl.AppendLine("    action {") }
            [void]$ocl.AppendLine('        action_type = "Octopus.Script"')
            if ($multi) { [void]$ocl.AppendLine("        name = $(ConvertTo-OclString $actionName)") }
            if ($isDisabled) { [void]$ocl.AppendLine("        is_disabled = true") }
            if ($isRequired) { [void]$ocl.AppendLine("        is_required = true") }
            if ($envs.Count -gt 0) { [void]$ocl.AppendLine("        environments = $(Format-OclList $envs)") }
            if ($excludedEnvs.Count -gt 0) { [void]$ocl.AppendLine("        excluded_environments = $(Format-OclList $excludedEnvs)") }
            if ($channels.Count -gt 0) { [void]$ocl.AppendLine("        channels = $(Format-OclList $channels)") }

            [void]$ocl.AppendLine("        properties = {")
            if ($runsOn -ne "targets") { [void]$ocl.AppendLine('            Octopus.Action.RunOnServer = "true"') }
            else { [void]$ocl.AppendLine('            Octopus.Action.RunOnServer = "false"') }

            # A package is linked in one of two ways, because an inline script cannot carry an unnamed package:
            #   mode "script"    the script runs from the package (ScriptSource Package, linked by properties)
            #   mode "reference" an inline script with a named, referenced package
            $packageMode = if ($package) { Get-Prop $package "mode" "script" } else { $null }
            $marker = "SCRIPT-MARKER-$actionSlug"
            if ($packageMode -eq "script") {
                $downloadOnTentacle = if ((Get-Prop $package "acquisition" "Server") -eq "ExecutionTarget") { "True" } else { "False" }
                [void]$ocl.AppendLine("            Octopus.Action.Package.DownloadOnTentacle = $(ConvertTo-OclString $downloadOnTentacle)")
                [void]$ocl.AppendLine("            Octopus.Action.Package.FeedId = $(ConvertTo-OclString $package.feed)")
                [void]$ocl.AppendLine("            Octopus.Action.Package.PackageId = $(ConvertTo-OclString $package.packageId)")
                [void]$ocl.AppendLine('            Octopus.Action.Script.ScriptFileName = "run.sh"')
                [void]$ocl.AppendLine('            Octopus.Action.Script.ScriptSource = "Package"')
            }
            else {
                $body = New-Object System.Collections.Generic.List[string]
                $body.Add("echo $marker")
                if ($setsOutput) { $body.Add("set_octopusvariable `"$setsOutput`" `"value-$actionSlug`"") }
                if ($failsWhenVariable) {
                    # Test hook: the step fails on purpose when the variable is "true".
                    $body.Add("if [ `"#{$failsWhenVariable}`" = `"true`" ]; then echo `"simulated failure`"; exit 1; fi")
                }
                if ($readsOutput -and $readsOutputFrom) {
                    $body.Add("echo `"#{Octopus.Action[$(Get-TitleFromSlug $readsOutputFrom)].Output.$readsOutput}`"")
                }
                [void]$ocl.AppendLine("            Octopus.Action.Script.ScriptBody = <<-EOT")
                foreach ($line in $body) { [void]$ocl.AppendLine("                $line") }
                [void]$ocl.AppendLine("            EOT")
                [void]$ocl.AppendLine('            Octopus.Action.Script.ScriptSource = "Inline"')
                [void]$ocl.AppendLine('            Octopus.Action.Script.Syntax = "Bash"')
            }
            [void]$ocl.AppendLine("        }")

            if ($tags.Count -gt 0) { [void]$ocl.AppendLine("        tenant_tags = $(Format-OclList $tags)") }
            if ($runsOn -ne "targets") { [void]$ocl.AppendLine("        worker_pool = $(ConvertTo-OclString $workerPoolSlug)") }

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
                number                 = $stepNumber
                label                  = $label
                stepName               = $stepName
                name                   = $actionName
                wave                   = $wave
                parallelWithPrevious   = $parallelWithPrevious
                runCondition           = $condition
                hasConditionExpression = [bool]$conditionExpression
                maxParallelism         = $maxParallelism
                runsOn                 = if ($runsOn -eq "targets") { "Targets" } else { "Worker" }
                targetRole             = if ($runsOn -eq "targets") { $targetRole } else { $null }
                tenantTags             = $tags
                environments           = $envs
                excludedEnvironments   = $excludedEnvs
                channels               = $channels
                isDisabled             = $isDisabled
                isRequired             = $isRequired
                setsOutput             = $setsOutput
                readsOutputFrom        = if ($readsOutput) { $readsOutputFrom } else { $null }
                packageRequirement     = if ($packageRequirement) { $packageRequirement } else { "LetOctopusDecide" }
                packageCount           = if ($package) { 1 } else { 0 }
                packageReference       = if ($package) { if ($packageMode -eq "reference") { Get-Prop $package "reference" "reference-package" } else { "(primary)" } } else { $null }
                packageAcquisition     = if ($package) { Get-Prop $package "acquisition" "Server" } else { $null }
                marker                 = $marker
            })
        }
        [void]$ocl.AppendLine("}")
        [void]$ocl.AppendLine("")
    }
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
    param([string]$Path, [string]$Text)
    $clean = $Text.TrimEnd().Replace("`r`n", "`n")
    if ($clean.Length -gt 0) { $clean += "`n" }
    [System.IO.File]::WriteAllText($Path, $clean, (New-Object System.Text.UTF8Encoding($false)))
}

New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
$oclPath = Join-Path $OutputFolder "deployment_process.ocl"
Write-Unix $oclPath $ocl.ToString()
$varPath = Join-Path $OutputFolder "variables.ocl"
Write-Unix $varPath $vocl.ToString()

$rows = $expectedRows.ToArray()
$waveGroups = @($rows | Group-Object -Property wave)
$stepsDistinct = @($rows | Select-Object -ExpandProperty number -Unique).Count
# The largest wave counts steps, not actions.
$largestSteps = ($waveGroups | ForEach-Object { @($_.Group | Select-Object -ExpandProperty number -Unique).Count } | Measure-Object -Maximum).Maximum

$tagUse = @{}
foreach ($r in $rows) { foreach ($t in $r.tenantTags) { if (-not $tagUse.ContainsKey($t)) { $tagUse[$t] = 0 }; $tagUse[$t]++ } }

function ConvertTo-SortedMap {
    param($Map)
    $sorted = [ordered]@{}
    foreach ($key in ($Map.Keys | Sort-Object)) { $sorted[$key] = $Map[$key] }
    return $sorted
}
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
