param(
    [string]$Godot = 'C:/Godot/Godot_v4.6.1-stable_win64_console.exe',
    [string]$AssetPack = '',
    [string]$Output = '',
    [switch]$Probe,
    [double]$FrameBudgetMs = 0
)
# Export a fresh runtime-only project. Never copy the developer's .godot cache.
$ErrorActionPreference = 'Stop'
if ([double]::IsNaN($FrameBudgetMs) -or [double]::IsInfinity($FrameBudgetMs) -or $FrameBudgetMs -lt 0 -or ($FrameBudgetMs -gt 0 -and -not $Probe)) { throw 'A positive finite frame budget requires -Probe' }
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'check_process.ps1')
. (Join-Path $PSScriptRoot 'check_result.ps1')
$runId = Get-Date -Format 'yyyyMMdd-HHmmss-ffff'
$auditRoot = Join-Path $projectRoot "artifacts/package-build/$runId"
$stageRoot = Join-Path $auditRoot 'runtime-source'
if (-not $AssetPack) { $AssetPack = Join-Path $projectRoot 'generated/gem-assets.pck' }
$AssetPack = (Resolve-Path -LiteralPath $AssetPack).Path
if (-not $Output) { $Output = Join-Path $projectRoot "generated/desktop/$runId" }
$Output = [System.IO.Path]::GetFullPath($Output)
if (Test-Path -LiteralPath $Output) {
    if (@(Get-ChildItem -LiteralPath $Output -Force).Count -ne 0) { throw "Package destination must be empty: $Output" }
}
New-Item -ItemType Directory -Force -Path $Output, $stageRoot | Out-Null
$preset = Get-Content -LiteralPath (Join-Path $projectRoot 'export_presets.cfg') -Raw
$fileList = [regex]::Match($preset, '(?m)^export_files=PackedStringArray\((.+)\)\r?$')
if (-not $fileList.Success) { throw 'Export preset must explicitly enumerate runtime resources' }
$runtimeFiles = @([regex]::Matches($fileList.Groups[1].Value, '"res://([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
$runtimeFiles += @('project.godot', 'icon.svg')
$sourceHashes = [ordered]@{}
foreach ($relative in $runtimeFiles) {
    if ($relative -match '(^|/)\.\.(/|$)' -or [System.IO.Path]::IsPathRooted($relative)) { throw "Invalid runtime path: $relative" }
    foreach ($suffix in @('', '.uid', '.import')) {
        $source = Join-Path $projectRoot ($relative + $suffix)
        if ($suffix -and -not (Test-Path -LiteralPath $source)) { continue }
        $destination = Join-Path $stageRoot ($relative + $suffix)
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination
        $sourceHashes[$relative + $suffix] = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}
$templates = Join-Path $projectRoot 'artifacts/toolchain/godot-4.6.1'
$expectedTemplates = @{
    'windows_debug_x86_64.exe' = '8515cd8041a906bdf82a3c9926125e20f642a1062cb2a45a962f3a43dffa41ed'
    'windows_release_x86_64.exe' = '6a0266cb7571aa4d437a32094acd353f020c77dcf7ff5a3305ae45d0609e5c20'
}
foreach ($name in $expectedTemplates.Keys) {
    $template = Join-Path $templates $name
    if (-not (Test-Path -LiteralPath $template)) { throw 'Missing pinned templates; run tools/fetch_export_templates.ps1 first' }
    if ((Get-FileHash -LiteralPath $template -Algorithm SHA256).Hash -ne $expectedTemplates[$name]) { throw "Export template checksum mismatch: $name" }
    $preset = $preset.Replace("res://artifacts/toolchain/godot-4.6.1/$name", $template.Replace('\', '/'))
}
[System.IO.File]::WriteAllText((Join-Path $stageRoot 'export_presets.cfg'), $preset, [System.Text.UTF8Encoding]::new($false))
function Invoke-PackageStage([string]$Name, [string[]]$Arguments, [string]$Completion) {
    $execution = Invoke-BoundedCheckProcess -Executable $Godot -Arguments $Arguments -TimeoutSeconds 300 -WorkingDirectory $Output
    $execution.output | Set-Content -LiteralPath (Join-Path $auditRoot "$Name.log") -Encoding utf8
    $result = Get-GodotCheckResult -ExitCode $execution.exit_code -Output $execution.output -Completion $Completion
    if (-not $result.passed) { Write-Output $execution.output; throw "Package stage $Name failed; see $auditRoot" }
    Write-Output "PASS $Name"
}
Invoke-PackageStage 'import' @('--headless', '--path', $stageRoot, '--editor', '--import') 'first_scan_filesystem'
$exe = Join-Path $Output 'Facets.exe'
Invoke-PackageStage 'export' @('--headless', '--path', $stageRoot, '--export-release', 'Windows Desktop', $exe) '[ DONE ] savepack'
$gamePack = Join-Path $Output 'Facets.pck'
if (-not (Test-Path -LiteralPath $exe) -or -not (Test-Path -LiteralPath $gamePack)) { throw 'Export did not produce the executable and PCK' }
Copy-Item -LiteralPath $AssetPack -Destination (Join-Path $Output 'gem-assets.pck')
$shippedPack = Join-Path $Output 'gem-assets.pck'
$inventoryReport = Join-Path $auditRoot 'inventory.json'
Invoke-PackageStage 'inventory' @('--headless', '--main-pack', $gamePack, '--script', (Join-Path $PSScriptRoot 'audit_game_package.gd'), '--', "--pack=$shippedPack", "--report=$inventoryReport") 'CHECK_COMPLETE: audit_game_package'
if ($Probe) {
    $probeArguments = @('--audio-driver', 'Dummy', '--main-pack', $gamePack, '--script', (Join-Path $PSScriptRoot 'export_runtime_probe.gd'), '--', "--pack=$shippedPack", "--report=$(Join-Path $auditRoot 'runtime-probe.json')")
    if ($FrameBudgetMs -gt 0) { $probeArguments += '--frame-budget-ms=' + $FrameBudgetMs.ToString([Globalization.CultureInfo]::InvariantCulture) }
    Invoke-PackageStage 'runtime-probe' $probeArguments 'CHECK_COMPLETE: export_runtime_probe'
}
foreach ($relative in $sourceHashes.Keys) {
    if ((Get-FileHash -LiteralPath (Join-Path $projectRoot $relative) -Algorithm SHA256).Hash -ne $sourceHashes[$relative]) { throw "Runtime source changed during export: $relative" }
}
$packageFiles = [ordered]@{}
foreach ($file in Get-ChildItem -LiteralPath $Output -File) {
    if ($file.Name -notin @('Facets.exe', 'Facets.pck', 'gem-assets.pck')) { throw "Unexpected shipped file: $($file.Name)" }
    $packageFiles[$file.Name] = @{ sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant(); bytes = $file.Length }
}
@{ status = 'passed'; source_files = $sourceHashes; package_files = $packageFiles; inventory = $inventoryReport; probe = [bool]$Probe; release_ui = 'separate acceptance required'; output = $Output } |
    ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $auditRoot 'report.json') -Encoding utf8
Write-Output "GAME_PACKAGE_COMPLETE: $Output"
Write-Output "Evidence: $auditRoot"
