param(
    [string]$Godot = 'C:/Godot/Godot_v4.6.1-stable_win64_console.exe',
    [switch]$Gpu,
    [switch]$CrystalPrecision,
    [string]$ReferencePython = '',
    [string[]]$Only = @(),
    [switch]$List
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$logRoot = Join-Path $projectRoot 'artifacts/checks'
. (Join-Path $PSScriptRoot 'check_result.ps1')
. (Join-Path $PSScriptRoot 'check_process.ps1')
$registry = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'engine_checks.json') -Raw | ConvertFrom-Json
if ($registry.schema -ne 1) { throw 'Unknown check registry schema' }
$stages = @($registry.stages | Where-Object {
    ($_.mode -eq 'cpu' -or ($_.mode -eq 'gpu' -and $Gpu) -or ($_.mode -eq 'precision' -and $CrystalPrecision) -or ($_.mode -eq 'reference' -and $ReferencePython)) -and
    ($Only.Count -eq 0 -or $_.name -in $Only)
})
if ($Only.Count) {
    foreach ($name in $Only) {
        if ($name -notin $stages.name) { throw "Unknown or disabled check: $name (select its GPU/reference mode)" }
    }
}
if ($List) { $stages | Select-Object name,mode,completion; exit 0 }
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$failed = @()
$results = @()
function Get-CheckedSourceDigest {
    $records = [System.Collections.Generic.List[string]]::new()
    foreach ($directory in @('core', 'resources', 'scenes', 'autoloads', 'tools', 'tests', 'data')) {
        Get-ChildItem -LiteralPath (Join-Path $projectRoot $directory) -File -Recurse |
            Where-Object { $_.Extension -in @('.gd', '.glsl', '.ps1', '.py', '.json', '.tres', '.tscn', '.csv') -and $_.FullName -notmatch '[\\/]__pycache__[\\/]' } |
            Sort-Object FullName | ForEach-Object { $records.Add($_.FullName + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash) }
    }
    return $records -join "`n"
}
$sourceBefore = Get-CheckedSourceDigest
foreach ($stage in $stages) {
    $arguments = @('--audio-driver', 'Dummy', '--path', $projectRoot, '--log-file', (Join-Path $logRoot ($stage.name + '.godot.log'))) + $stage.args
    $started = Get-Date
    $timeout = if ($stage.timeout_seconds) { [int]$stage.timeout_seconds } elseif ($stage.mode -eq 'cpu') { 300 } else { 1800 }
    $execution = Invoke-BoundedCheckProcess -Executable $Godot -Arguments $arguments -TimeoutSeconds $timeout
    $code = $execution.exit_code
    $text = $execution.output
    $output = $text -split "`r?`n"
    $output | Set-Content -Encoding utf8 -LiteralPath (Join-Path $logRoot ($stage.name + '.log'))
    $result = Get-GodotCheckResult -ExitCode $code -Output $text -Completion $stage.completion
    $results += [ordered]@{ name = $stage.name; result = $result; elapsed_seconds = ((Get-Date) - $started).TotalSeconds }
    if (-not $result.passed) {
        $failed += $stage.name
        Write-Output "FAIL $($stage.name): completed=$($result.completed), exit=$code, environment_errors=$($result.environment_errors.Count)"
        Write-Output $output
    } else { Write-Output "PASS $($stage.name)" }
    $results | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 -LiteralPath (Join-Path $logRoot 'results.json')
}
if ($ReferencePython -and $failed.Count -eq 0 -and $Only.Count -eq 0) {
    $referenceChecks = @('check_polygon_reference', 'check_mesh_predicates', 'check_polarization_reference', 'check_crystal_modes_reference', 'check_crystal_interface_reference', 'check_crystal_packet_reference', 'check_crystal_loss_reference')
    if ($Gpu) { $referenceChecks += @('check_gpu_polarization_reference', 'check_microsurface_reference', 'check_finish_fields_reference', 'check_absorption_mixtures') }
    foreach ($name in $referenceChecks) {
        $execution = Invoke-BoundedCheckProcess -Executable $ReferencePython -Arguments @((Join-Path $projectRoot "tools/$name.py")) -TimeoutSeconds 1800
        $output = $execution.output
        $code = $execution.exit_code
        $output | Set-Content -Encoding utf8 -LiteralPath (Join-Path $logRoot "$name.log")
        if ($code -ne 0) { $failed += $name; Write-Output "FAIL $name" }
        else { Write-Output "PASS $name" }
    }
}
if ($sourceBefore -cne (Get-CheckedSourceDigest)) {
    $failed += 'source_changed_during_validation'
    Write-Output 'FAIL source_changed_during_validation: rerun against a stable source tree'
}
if ($failed.Count -gt 0) { Write-Output "Failed checks: $($failed -join ', ')"; exit 1 }
Write-Output "ENGINE_CHECKS_COMPLETE: $($stages.Count) Godot stages"
exit 0
