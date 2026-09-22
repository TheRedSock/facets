param(
    [Parameter(Mandatory)][string]$Package,
    [Parameter(Mandatory)][string]$Output,
    [ValidateSet('cpu','native','characterization')][string]$Mode = 'cpu',
    [int]$Width = 1280, [int]$Height = 720,
    [int]$Multiplier = 1, [int]$Seeds = 100, [int]$Repetitions = 3,
    [string]$Policies = 'all-pass,first,survivor,remote,mixed',
    [switch]$Reduced,
    [int]$GpuIndex = -1
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'check_process.ps1')
. (Join-Path $PSScriptRoot 'check_result.ps1')
$packagePath = (Resolve-Path -LiteralPath $Package).Path
$outputPath = [IO.Path]::GetFullPath($Output)
if (Test-Path -LiteralPath $outputPath) { throw 'Release report directory must be fresh' }
New-Item -ItemType Directory -Path $outputPath | Out-Null
function PackageIdentity {
    $result = [ordered]@{}
    foreach ($name in @('Facets.exe','Facets.pck','gem-assets.pck')) {
        $result[$name] = (Get-FileHash -LiteralPath (Join-Path $packagePath $name) -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    return $result
}
$identity = PackageIdentity
$metadata = [ordered]@{ schema=1; mode=$Mode; package=$packagePath; hashes=$identity; started=(Get-Date).ToString('o'); power=(powercfg /getactivescheme | Out-String).Trim(); width=$Width; height=$Height; gpu_index=$GpuIndex; multiplier=$Multiplier; seeds=$Seeds; repetitions=$Repetitions; policies=$Policies }
try {
    $metadata.cpu = @(Get-CimInstance Win32_Processor | Select-Object Name,LoadPercentage)
    $metadata.gpu = @(Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion)
} catch { $metadata.hardware_query_error = $_.Exception.Message }
$metadata | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 (Join-Path $outputPath 'environment.json')
$report = Join-Path $outputPath 'probe.json'
$arguments = @('--audio-driver','Dummy','--resolution',"${Width}x${Height}")
if ($Mode -ne 'native') { $arguments += '--headless' }
if ($GpuIndex -ge 0) { $arguments += @('--gpu-index',"$GpuIndex") }
$arguments += @('--',"--merge-probe=$($report.Replace('\','/'))","--merge-multiplier=$Multiplier","--merge-seeds=$Seeds","--merge-repetitions=$Repetitions","--merge-policies=$Policies")
if ($Mode -eq 'native') { $arguments += @('--merge-native','--review') }
if ($Mode -eq 'characterization') { $arguments += '--merge-characterization' }
if ($Reduced) { $arguments += '--merge-reduced' }
$execution = Invoke-BoundedCheckProcess -Executable (Join-Path $packagePath 'Facets.exe') -Arguments $arguments -TimeoutSeconds 7200 -WorkingDirectory $packagePath
$execution.output | Set-Content -Encoding utf8 (Join-Path $outputPath 'probe.log')
$checked = Get-GodotCheckResult -ExitCode $execution.exit_code -Output $execution.output -Completion 'CHECK_COMPLETE: merge_probe'
$sameBytes = (ConvertTo-Json $identity -Compress) -eq (ConvertTo-Json (PackageIdentity) -Compress)
$errors = @()
if (-not $sameBytes) { $errors += 'Package bytes changed during measurement' }
if (-not (Test-Path -LiteralPath $report)) { $errors += 'Missing structured report' }
else {
    $data = Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
    if ($data.editor) { $errors += 'Expected release executable' }
    if ($data.status -ne 'passed') { $errors += @($data.failures) }
    if ($Mode -eq 'cpu') {
        $expected = $Seeds*$Repetitions*($Policies.Split(',').Count)
        if ($data.rooms.Count -ne $expected) { $errors += "Corpus count $($data.rooms.Count) expected $expected" }
        foreach ($group in ($data.rooms | Group-Object seed,policy)) {
            if (@($group.Group.digest | Select-Object -Unique).Count -ne 1) { $errors += "Nondeterministic repetitions: $($group.Name)" }
        }
    }
}
$result = [ordered]@{ schema=1; completed=$checked.completed; check=$checked; same_package_bytes=$sameBytes; errors=$errors; passed=($checked.passed -and $sameBytes -and $errors.Count -eq 0); finished=(Get-Date).ToString('o'); peak_working_set_bytes=$execution.peak_working_set_bytes; sampled_peak_private_bytes=$execution.sampled_peak_private_bytes; memory_scope='Whole process including worker/snapshots and renderer; not an isolated worker allocation count.' }
$result | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 (Join-Path $outputPath 'run.json')
if (-not $result.passed) {
    $reasons = @($errors) + @($checked.errors) + @($checked.environment_errors)
    Write-Output ('FAIL merge_release: '+(($reasons | Select-Object -First 3) -join ', ')+"; full report: $outputPath/run.json")
    exit 1
}
Write-Output "MERGE_RELEASE_COMPLETE: $Mode $outputPath"
