param(
    [Parameter(Mandatory)][int]$ProcessId,
    [ValidateRange(10,600)][int]$Seconds = 30,
    [double]$FrameBudgetMs = 16.7,
    [string]$Output = ''
)
# External ETW measurement of the exact release process; no game instrumentation.
$ErrorActionPreference = 'Stop'
if ([double]::IsNaN($FrameBudgetMs) -or [double]::IsInfinity($FrameBudgetMs) -or $FrameBudgetMs -le 0) { throw 'Frame budget must be finite and positive' }
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'check_process.ps1')
$target = Get-Process -Id $ProcessId -ErrorAction Stop
if ([IO.Path]::GetFileName($target.Path) -cne 'Facets.exe') { throw 'Select the actual Facets.exe release process' }
$packageRoot = Split-Path -Parent $target.Path
$packageHashes = [ordered]@{}
foreach ($name in @('Facets.exe','Facets.pck','gem-assets.pck')) {
    $packageHashes[$name] = (Get-FileHash -LiteralPath (Join-Path $packageRoot $name) -Algorithm SHA256).Hash.ToLowerInvariant()
}
$toolRoot = Join-Path $projectRoot 'artifacts/toolchain/presentmon'
$tool = Join-Path $toolRoot 'PresentMon-2.5.1-x64.exe'
$expectedHash = '9bec3083069f58f911e6a512f4806db51a27bd096103087bc1d05ef54c80a191'
New-Item -ItemType Directory -Force -Path $toolRoot | Out-Null
if (-not (Test-Path -LiteralPath $tool)) {
    Invoke-WebRequest -Uri 'https://github.com/GameTechDev/PresentMon/releases/download/v2.5.1/PresentMon-2.5.1-x64.exe' -OutFile $tool
}
if ((Get-FileHash -LiteralPath $tool -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedHash) { throw 'PresentMon checksum mismatch' }
$runId = Get-Date -Format 'yyyyMMdd-HHmmss-ffff'
if (-not $Output) { $Output = Join-Path $projectRoot "artifacts/release-frames/$runId" }
$Output = [IO.Path]::GetFullPath($Output)
if (Test-Path -LiteralPath $Output) { throw 'Frame capture output must be a new directory' }
New-Item -ItemType Directory -Path $Output | Out-Null
$csv = Join-Path $Output 'frames.csv'
$arguments = @('--process_id', "$ProcessId", '--timed', "$Seconds", '--terminate_after_timed',
    '--session_name', "Facets-$runId", '--no_console_stats', '--no_track_input', '--output_file', $csv)
$capture = Invoke-BoundedCheckProcess -Executable $tool -Arguments $arguments -TimeoutSeconds ($Seconds+30)
$capture.output | Set-Content -LiteralPath (Join-Path $Output 'capture.log')
$report = [ordered]@{ status='failed'; executable=$target.Path; process_id=$ProcessId; package_files=$packageHashes;
    tool_sha256=$expectedHash; tool_version='2.5.1'; requested_seconds=$Seconds; budget_ms=$FrameBudgetMs;
    exit_code=$capture.exit_code; timed_out=$capture.timed_out }
if ($capture.exit_code -ne 0 -or -not (Test-Path -LiteralPath $csv)) {
    $report.status = 'environment_error'
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Output 'report.json')
    throw "Frame capture failed. Inspect $Output/capture.log. ETW requires an administrator or Performance Log Users token; no group membership is changed by this tool."
}
$rows = @(Import-Csv -LiteralPath $csv)
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Output 'report.json')
if ($rows.Count -lt 300) { throw 'Incomplete frame capture: fewer than 300 presented frames' }
if (@($rows | Where-Object { [int]$_.ProcessID -ne $ProcessId }).Count) { throw 'Capture contains another process' }
$chains = @($rows.SwapChainAddress | Sort-Object -Unique)
if ($chains.Count -ne 1) { throw 'Capture has multiple swap chains; inspect them before selecting a measurement' }
$times = @($rows | ForEach-Object {
    $value = [double]::Parse($_.MsBetweenPresents,[Globalization.CultureInfo]::InvariantCulture)
    if ([double]::IsNaN($value) -or [double]::IsInfinity($value) -or $value -lt 0) { throw 'Invalid frame interval in capture' }
    $value
})
# The first present has no previous frame in this capture. Retain every later
# interval, including pauses and frames dropped by the display compositor.
$times = @($times | Select-Object -Skip 1 | Sort-Object)
if (($times | Measure-Object -Sum).Sum -lt $Seconds*900) { throw 'Frame capture does not cover the requested interval' }
foreach ($name in $packageHashes.Keys) {
    if ((Get-FileHash -LiteralPath (Join-Path $packageRoot $name) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $packageHashes[$name]) { throw 'Package changed during frame capture' }
}
$p95 = $times[[int][math]::Ceiling($times.Count*.95)-1]
$report.status = if ($p95 -le $FrameBudgetMs) { 'passed' } else { 'failed' }
$report.frames = $times.Count
$report.present_interval_ms = @{p50=$times[[int][math]::Ceiling($times.Count*.5)-1];p95=$p95;p99=$times[[int][math]::Ceiling($times.Count*.99)-1];max=$times[-1]}
$report.csv_sha256 = (Get-FileHash -LiteralPath $csv -Algorithm SHA256).Hash.ToLowerInvariant()
$report.note = 'ETW intervals between application presents. Display scheduling/drop information remains in the raw CSV. Capture the foreground game with the GPU otherwise idle; scene and interaction evidence must accompany this report.'
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Output 'report.json')
Write-Output "Release frame report: $Output/report.json"
Write-Output 'CHECK_COMPLETE: measure_release_frames'
if ($report.status -ne 'passed') { exit 1 }
