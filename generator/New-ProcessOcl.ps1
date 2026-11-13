<#
.SYNOPSIS
    Generates deployment_process.ocl and expected.json from a definition file.

.DESCRIPTION
    The definition is the expected result. The export script is tested by comparing
    its output with expected.json.

    Every step is a dummy bash script. Each script body holds a marker string so the
    privacy tests can prove that no script text reaches the export.

.PARAMETER Definition
    Path to the definition JSON file.

.PARAMETER OutputFolder
    Where to write deployment_process.ocl. Default: the project folder under .octopus.

.PARAMETER ExpectedPath
    Where to write expected.json. Default: expected/<definition name>.expected.json
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

$def = Get-Content -LiteralPath $Definition -Raw | ConvertFrom-Json
$ocl = New-Object System.Text.StringBuilder
$expectedSteps = New-Object System.Collections.Generic.List[object]

$stepNumber = 0
$wave = 0
$firstStepEver = $true

foreach ($group in $def.groups) {
    $count = [int](Get-Prop $group "count" 1)
    $layout = Get-Prop $group "layout" "sequential"
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

    for ($i = 1; $i -le $count; $i++) {
        $stepNumber++
        $name = if ($count -gt 1) { "{0} {1:00}" -f $group.name, $i } else { $group.name }
        $slug = ($name.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')

        # Parallel groups: the first step waits for the previous step. The rest start with it.
        $parallelWithPrevious = ($layout -eq "parallel") -and ($i -gt 1)
        if (-not $parallelWithPrevious) { $wave++ }

        [void]$ocl.AppendLine("step $(ConvertTo-OclString $slug) {")
        [void]$ocl.AppendLine("    name = $(ConvertTo-OclString $name)")
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

        [void]$ocl.AppendLine("")
        [void]$ocl.AppendLine("    action {")
        [void]$ocl.AppendLine('        action_type = "Octopus.Script"')
        if ($isDisabled) { [void]$ocl.AppendLine("        is_disabled = true") }
        if ($isRequired) { [void]$ocl.AppendLine("        is_required = true") }
        if ($envs.Count -gt 0) { [void]$ocl.AppendLine("        environments = [" + (($envs | ForEach-Object { ConvertTo-OclString $_ }) -join ", ") + "]") }
        if ($excludedEnvs.Count -gt 0) { [void]$ocl.AppendLine("        excluded_environments = [" + (($excludedEnvs | ForEach-Object { ConvertTo-OclString $_ }) -join ", ") + "]") }
        if ($channels.Count -gt 0) { [void]$ocl.AppendLine("        channels = [" + (($channels | ForEach-Object { ConvertTo-OclString $_ }) -join ", ") + "]") }

        [void]$ocl.AppendLine("        properties = {")
        if ($runsOn -ne "targets") { [void]$ocl.AppendLine('            Octopus.Action.RunOnServer = "true"') }
        else { [void]$ocl.AppendLine('            Octopus.Action.RunOnServer = "false"') }

        $body = New-Object System.Collections.Generic.List[string]
        $body.Add("echo SCRIPT-MARKER-$slug")
        if ($setsOutput) { $body.Add("set_octopusvariable `"$setsOutput`" `"value-$slug`"") }
        if ($readsOutput -and $readsOutputFrom) {
            $producerName = ($readsOutputFrom -split '-' | ForEach-Object { if ($_ -match '^\d+$') { $_ } else { (Get-Culture).TextInfo.ToTitleCase($_) } }) -join ' '
            $body.Add("echo `"#{Octopus.Action[$producerName].Output.$readsOutput}`"")
        }
        [void]$ocl.AppendLine("            Octopus.Action.Script.ScriptBody = <<-EOT")
        foreach ($line in $body) { [void]$ocl.AppendLine("                $line") }
        [void]$ocl.AppendLine("            EOT")
        [void]$ocl.AppendLine('            Octopus.Action.Script.ScriptSource = "Inline"')
        [void]$ocl.AppendLine('            Octopus.Action.Script.Syntax = "Bash"')
        [void]$ocl.AppendLine("        }")

        if ($tags.Count -gt 0) { [void]$ocl.AppendLine("        tenant_tags = [" + (($tags | ForEach-Object { ConvertTo-OclString $_ }) -join ", ") + "]") }
        if ($runsOn -ne "targets") { [void]$ocl.AppendLine('        worker_pool = "hosted-ubuntu"') }

        if ($package) {
            [void]$ocl.AppendLine("")
            [void]$ocl.AppendLine("        packages {")
            [void]$ocl.AppendLine("            acquisition_location = $(ConvertTo-OclString (Get-Prop $package 'acquisition' 'Server'))")
            [void]$ocl.AppendLine("            feed = $(ConvertTo-OclString $package.feed)")
            [void]$ocl.AppendLine("            package_id = $(ConvertTo-OclString $package.packageId)")
            [void]$ocl.AppendLine("            properties = {")
            [void]$ocl.AppendLine('                SelectionMode = "immediate"')
            [void]$ocl.AppendLine("            }")
            [void]$ocl.AppendLine("        }")
        }
        [void]$ocl.AppendLine("    }")
        [void]$ocl.AppendLine("}")
        [void]$ocl.AppendLine("")

        $expectedSteps.Add([pscustomobject][ordered]@{
            number               = $stepNumber
            name                 = $name
            wave                 = $wave
            parallelWithPrevious = $parallelWithPrevious
            runCondition         = $condition
            hasConditionExpression = [bool]$conditionExpression
            maxParallelism       = $maxParallelism
            runsOn               = if ($runsOn -eq "targets") { "Targets" } else { "Worker" }
            targetRole           = if ($runsOn -eq "targets") { $targetRole } else { $null }
            tenantTags           = $tags
            environments         = $envs
            excludedEnvironments = $excludedEnvs
            channels             = $channels
            isDisabled           = $isDisabled
            isRequired           = $isRequired
            setsOutput           = $setsOutput
            readsOutputFrom      = if ($readsOutput) { $readsOutputFrom } else { $null }
            packageCount         = if ($package) { 1 } else { 0 }
            packageAcquisition   = if ($package) { Get-Prop $package "acquisition" "Server" } else { $null }
            marker               = "SCRIPT-MARKER-$slug"
        })
    }
}

New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
$oclPath = Join-Path $OutputFolder "deployment_process.ocl"
# Write without a byte order mark and with Unix line endings.
[System.IO.File]::WriteAllText($oclPath, ($ocl.ToString().TrimEnd() + "`n").Replace("`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))

$waveGroups = $expectedSteps | Group-Object -Property wave
$largest = ($waveGroups | Measure-Object -Property Count -Maximum).Maximum

$tagUse = @{}
foreach ($s in $expectedSteps) { foreach ($t in $s.tenantTags) { if (-not $tagUse.ContainsKey($t)) { $tagUse[$t] = 0 }; $tagUse[$t]++ } }

$expected = [ordered]@{
    definition   = (Split-Path -Leaf $Definition)
    counts       = [ordered]@{
        steps       = $expectedSteps.Count
        waves       = $waveGroups.Count
        largestWave = $largest
        tagged      = @($expectedSteps | Where-Object { $_.tenantTags.Count -gt 0 }).Count
        disabled    = @($expectedSteps | Where-Object { $_.isDisabled }).Count
        required    = @($expectedSteps | Where-Object { $_.isRequired }).Count
        withCondition = @($expectedSteps | Where-Object { $_.runCondition -ne "Success" }).Count
        withPackage = @($expectedSteps | Where-Object { $_.packageCount -gt 0 }).Count
    }
    stepsUsingTag = $tagUse
    steps         = $expectedSteps
}

if (-not $ExpectedPath) {
    $dir = Join-Path $PSScriptRoot "../expected"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $ExpectedPath = Join-Path $dir ((Split-Path -Leaf $Definition) -replace '\.json$', '.expected.json')
}
$expected | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ExpectedPath -Encoding UTF8

Write-Host "Wrote $oclPath"
Write-Host "Wrote $ExpectedPath"
Write-Host ("Steps: {0}  Waves: {1}  Largest wave: {2}" -f $expectedSteps.Count, $waveGroups.Count, $largest)
