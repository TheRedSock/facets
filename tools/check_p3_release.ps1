param(
    [Parameter(Mandatory)][string]$Package,
    [Parameter(Mandatory)][string]$Output,
    [ValidateSet('native','tuning')][string]$Mode = 'native',
    [int]$Width = 1280, [int]$Height = 720,
    [int]$GpuIndex = 0, [switch]$AlwaysOnTop
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'check_process.ps1')
. (Join-Path $PSScriptRoot 'check_result.ps1')
$packagePath = (Resolve-Path -LiteralPath $Package).Path
$outputPath = [IO.Path]::GetFullPath($Output)
if (Test-Path -LiteralPath $outputPath) { throw 'Evidence directory must be fresh' }
New-Item -ItemType Directory -Path $outputPath | Out-Null
$identity = [ordered]@{}
foreach ($name in 'Facets.exe','Facets.pck','gem-assets.pck') { $identity[$name] = (Get-FileHash -LiteralPath (Join-Path $packagePath $name)).Hash }
$witnesses = Join-Path $outputPath 'witnesses'
New-Item -ItemType Directory -Path $witnesses | Out-Null
$inputs = [ordered]@{}
foreach ($name in 'deep_seam.fac','commission-opening.fac') {
    $source = Join-Path $PSScriptRoot "../tests/fixtures/p3_expedition_v1/$name"
    Copy-Item -LiteralPath $source -Destination $witnesses
    $inputs[$name] = (Get-FileHash -LiteralPath $source).Hash
}
$report = Join-Path $outputPath 'probe.json'
$log = Join-Path $outputPath 'probe.godot.log'
$arguments = @('--audio-driver','Dummy','--resolution',"${Width}x${Height}",'--gpu-index',"$GpuIndex",'--log-file',$log)
if ($Mode -eq 'tuning') { $arguments += '--headless' }
if ($AlwaysOnTop) { $arguments += '--always-on-top' }
$arguments += @('--',"--p3-probe=$($report.Replace('\','/'))","--p3-witnesses=$($witnesses.Replace('\','/'))")
if ($Mode -eq 'tuning') { $arguments += '--p3-tuning' }
$execution = Invoke-BoundedCheckProcess -Executable (Join-Path $packagePath 'Facets.exe') -Arguments $arguments -TimeoutSeconds 1800 -WorkingDirectory $packagePath
$execution.output | Set-Content -Encoding utf8 (Join-Path $outputPath 'probe.process.log')
$checked = Get-GodotCheckResult -ExitCode $execution.exit_code -Output $execution.output -Completion 'CHECK_COMPLETE: p3_probe'
$errors = @()
foreach ($name in $identity.Keys) { if ((Get-FileHash -LiteralPath (Join-Path $packagePath $name)).Hash -ne $identity[$name]) { $errors += 'Package changed: '+$name } }
if (-not (Test-Path -LiteralPath $report)) { $errors += 'Missing structured report' }
else {
    $data = Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
    if ($data.editor) { $errors += 'Expected actual release executable' }
    if ($data.status -ne 'passed') { $errors += @($data.failures) }
    if ($Mode -eq 'tuning' -and $data.rooms.Count -ne 200) { $errors += 'Expected all 200 declared seed/policy runs' }
    if (@($data.observations | Where-Object { -not $_.passed }).Count) { $errors += 'Failed behavioral assertions' }
}
$result = [ordered]@{ schema=1; package=$packagePath; hashes=$identity; input_hashes=$inputs; mode=$Mode; width=$Width; height=$Height; check=$checked; errors=$errors; passed=($checked.passed -and $errors.Count -eq 0); peak_working_set_bytes=$execution.peak_working_set_bytes; sampled_peak_private_bytes=$execution.sampled_peak_private_bytes }
$result | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 (Join-Path $outputPath 'run.json')
if (-not $result.passed) { Write-Output "FAIL P3 release: $outputPath/run.json"; exit 1 }
Write-Output "P3_RELEASE_COMPLETE: $Mode $outputPath"
