param(
    [Parameter(Mandatory)][string]$Package,
    [Parameter(Mandatory)][string]$OutputRoot,
    [int]$GpuIndex = -1
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$packageRoot = (Resolve-Path -LiteralPath $Package).Path
$evidenceRoot = [IO.Path]::GetFullPath($OutputRoot, $repo)
if ((Test-Path -LiteralPath $evidenceRoot) -and @(Get-ChildItem -LiteralPath $evidenceRoot -Force).Count) { throw 'Release evidence directory must be new or empty' }
New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
. (Join-Path $repo 'tools/check_process.ps1')
. (Join-Path $repo 'tools/check_result.ps1')
$packageHashes = @{}
foreach ($file in 'Facets.exe','Facets.pck','gem-assets.pck') { $packageHashes[$file] = (Get-FileHash -LiteralPath (Join-Path $packageRoot $file)).Hash.ToLower() }
$results = [System.Collections.Generic.List[object]]::new()
function Invoke-ReleaseWitness {
    param([string]$Name,[string[]]$UserArgs,[string]$Marker,[string[]]$EngineArgs=@(),[string]$Directory=$packageRoot,[string]$ExpectedError='')
    $reportPath = Join-Path $evidenceRoot ($Name+'.json')
    $logPath = Join-Path $evidenceRoot ($Name+'.godot.log')
    $graphicsArgs = if ($GpuIndex -ge 0) { @('--gpu-index',"$GpuIndex") } else { @() }
    $args = @('--audio-driver','Dummy','--log-file',$logPath) + $graphicsArgs + $EngineArgs + @('--')
    foreach ($arg in $UserArgs) { $args += $arg.Replace('{report}',$reportPath.Replace('\','/')) }
    $started = Get-Date
    $execution = Invoke-BoundedCheckProcess -Executable (Join-Path $Directory 'Facets.exe') -Arguments $args -TimeoutSeconds 1200 -WorkingDirectory $Directory
    $execution.output | Set-Content -LiteralPath (Join-Path $evidenceRoot ($Name+'.process.log')) -Encoding utf8
    $log = if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Raw } else { $execution.output }
    $classification = Get-GodotCheckResult -ExitCode $execution.exit_code -Output $log -Completion $Marker
    if (-not (Test-Path -LiteralPath $reportPath)) { throw "Missing $Name report" }
    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    $passed = $classification.passed -and $report.status -in @('pass','passed') -and $report.editor -eq $false
    if ($ExpectedError) {
        # Keep expected loading errors separate from ordinary passing engine logs.
        # Never forgive script failures, leaks, timeouts or unrelated ERROR lines.
        $unexpected = @($classification.errors | Where-Object { $_ -notmatch '^ERROR: (Can.t open pack|Invalid pack file|Condition "magic != PACK_HEADER_MAGIC")' })
        $passed = $execution.exit_code -eq 0 -and $classification.completed -and $unexpected.Count -eq 0 -and $report.status -eq 'passed' -and $report.expected_load_error -like ($ExpectedError+'*')
    }
    $results.Add([ordered]@{name=$Name;passed=$passed;elapsed_seconds=((Get-Date)-$started).TotalSeconds;classification=$classification;expected_load_error=$ExpectedError;report=$reportPath})
    $results | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $evidenceRoot 'stages.json') -Encoding utf8
    if (-not $passed) { throw "Release witness failed: $Name; inspect preserved logs and report" }
    Write-Host "PASS release/$Name"
    return $report
}
$lifecycle = Invoke-ReleaseWitness 'lifecycle' @('--closeout-probe={report}') 'CHECK_COMPLETE: closeout_probe' @('--resolution','1600x900')
$native = @()
foreach ($size in '1600x900','1280x720') { $native += Invoke-ReleaseWitness ('room-'+$size) @('--room-probe={report}','--room-screenshots') 'CHECK_COMPLETE: room_probe' @('--resolution',$size) }
$p1 = Invoke-ReleaseWitness 'p1-corpus' @('--action-probe={report}','--probe-corpus') 'CHECK_COMPLETE: action_probe' @('--headless')
$p2 = Invoke-ReleaseWitness 'p2-corpus' @('--action-probe={report}','--probe-room-corpus') 'CHECK_COMPLETE: action_probe' @('--headless')
$baseline1 = Get-Content -LiteralPath (Join-Path $repo 'tests/game/p1-checkpoints.json') -Raw | ConvertFrom-Json
foreach ($action in $p1.actions) {
    $expected = $baseline1.seeds[[int]$action.seed].checkpoints[[int]$action.index]
    if ($action.state_digest -cne $expected.state_digest -or $action.event_digest -cne $expected.event_digest) { throw 'Release P1 checkpoint mismatch' }
}
$baseline2 = Get-Content -LiteralPath (Join-Path $repo 'tests/game/p2-reference.json') -Raw | ConvertFrom-Json
foreach ($action in $p2.actions) {
    $expected = $baseline2.records[[int]$action.seed-1].checkpoints[[int]$action.index+1]
    if ($action.state_digest -cne $expected.state_digest -or $action.event_digest -cne $expected.event_digest) { throw 'Release P2 checkpoint mismatch' }
}
if ($p1.actions.Count -ne 2000 -or $p2.actions.Count -ne 1194) { throw 'Incomplete release checkpoint corpus' }
$trials = @()
foreach ($fps in 30,60,120) {
    $args = @('--closeout-probe={report}','--closeout-case=trial')
    if ($fps -eq 60) { $args += '--room-screenshots' }
    if ($fps -eq 120) { $args += '--reduced-motion' }
    $trials += Invoke-ReleaseWitness ('trial-'+$fps) $args 'CHECK_COMPLETE: closeout_probe' @('--resolution','1280x720','--max-fps',"$fps")
}
foreach ($trial in $trials) {
    for ($i=0; $i -lt 3; $i++) {
        if ($trial.profiles[$i].snapshot_digest -cne $trials[0].profiles[$i].snapshot_digest) { throw 'Release trial FPS/reduced-motion replay mismatch' }
    }
}
foreach ($case in 'missing','corrupt') {
    $directory = Join-Path $evidenceRoot ($case+'-pack')
    New-Item -ItemType Directory -Path $directory | Out-Null
    foreach ($file in 'Facets.exe','Facets.pck') { Copy-Item -LiteralPath (Join-Path $packageRoot $file) -Destination (Join-Path $directory $file) }
    if ($case -eq 'corrupt') { [IO.File]::WriteAllBytes((Join-Path $directory 'gem-assets.pck'),[Text.Encoding]::ASCII.GetBytes('deliberately invalid diagnostic pack')) }
    $prefix = if ($case -eq 'missing') { 'Required gem asset pack is missing:' } else { 'Cannot mount required gem asset pack:' }
    $ignored = Invoke-ReleaseWitness ($case+'-pack') @('--closeout-probe={report}','--closeout-case=delivery_error') 'CHECK_COMPLETE: closeout_probe' @('--resolution','1280x720') $directory $prefix
}
foreach ($file in $packageHashes.Keys) {
    if ((Get-FileHash -LiteralPath (Join-Path $packageRoot $file)).Hash.ToLower() -cne $packageHashes[$file]) { throw 'Package changed during release verification' }
}
[ordered]@{schema=1;status='passed';package=$packageRoot;gpu_index=$GpuIndex;package_hashes=$packageHashes;completed_stages=$results.Count;p1_pairs=2000;p2_pairs=1194;trial_fps_equivalence=$true;cpu_target_ms=5;p1_cpu=$p1.simulation;p2_cpu=$p2.simulation;cpu_target_met=($p1.target_5ms_met -and $p2.target_5ms_met);frames=@($native | ForEach-Object {$_.frames});frame_target_met=(@($native | Where-Object {-not $_.target_16_7ms_met}).Count -eq 0);human_evaluation='deferred by user'} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $evidenceRoot 'release.json') -Encoding utf8
Write-Output 'CHECK_COMPLETE: verify_closeout_release'
