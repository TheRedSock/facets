param(
    [string]$Godot = 'C:/Godot/Godot_v4.6.1-stable_win64_console.exe',
    [string]$Stone = '',
    [string]$Specimen = '',
    [string]$Batch = '',
    [string]$Recipe = '',
    [string]$Quality = '',
    [int]$SpecimenSeed = 1,
    [string]$Style = '',
    [switch]$RetainPrints,
    [string]$Clip = '',
    [ValidateSet('interact', 'preview', 'clip_bake', 'hero', 'reference')]
    [string]$Rung = 'clip_bake',
    [ValidateSet('webp_lossless', 'bc7', 'astc4x4')]
    [string]$Codec = 'webp_lossless',
    [int]$Resolution = 0,
    [int]$Samples = 0,
    [int]$Page = 512,
    [ValidateSet(0, 1, 2, 4, 8)]
    [int]$GeometryCoverage = 0,
    [ValidateRange(0, 1048576)]
    [int]$CacheBudgetMiB = 2048,
    [switch]$SkipCollection,
    [switch]$PlanOnly
)
# Generated source bundle/ZIP, resumable store and shipping PCK stay ignored.
# Copy generated/gem-assets.pck next to an exported game executable.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$logRoot = Join-Path $projectRoot 'artifacts/build-assets'
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$generatedRoot = Join-Path $projectRoot 'generated'
New-Item -ItemType Directory -Force -Path $generatedRoot | Out-Null
New-Item -ItemType File -Force -Path (Join-Path $generatedRoot '.gdignore') | Out-Null
function Invoke-GemStage([string]$Name, [string[]]$Arguments) {
    $log = Join-Path $logRoot "$Name.log"
    & $Godot --audio-driver Dummy @Arguments 2>&1 | Tee-Object -FilePath $log
    if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $log -Pattern '^\s*(SCRIPT ERROR:|ERROR:|FAIL(:|\b)|FAILED\b)')) {
        throw "Asset stage $Name failed; see $log"
    }
}
$prepare = @('--headless', '--path', $projectRoot, '--quit-after', '600', '--script', 'res://tools/prepare_gem_jobs.gd', '--')
if ($Batch) {
    foreach ($selector in @('Stone', 'Specimen', 'Recipe', 'Quality', 'SpecimenSeed', 'Style', 'RetainPrints', 'Clip', 'Rung', 'Resolution', 'Samples')) {
        if ($PSBoundParameters.ContainsKey($selector)) { throw "Batch resources carry their own requests; cannot override $selector" }
    }
    $prepare += "--batch=$Batch"
} else { $prepare += "--rung=$Rung" }
if (-not $Batch -or $PSBoundParameters.ContainsKey('GeometryCoverage')) { $prepare += "--geometry-coverage=$GeometryCoverage" }
if ($Stone) { $prepare += "--stone=$Stone" }
if ($Specimen) { $prepare += "--specimen=$Specimen" }
if ($Recipe) { $prepare += "--recipe=$Recipe"; $prepare += "--seed=$SpecimenSeed" }
if ($Quality) { $prepare += "--quality=$Quality" }
if ($Style) { $prepare += "--style=$Style" }
if ($RetainPrints) { $prepare += '--retain-prints=true' }
if ($Clip) { $prepare += "--clip=$Clip" }
if ($Resolution -gt 0) { $prepare += "--resolution=$Resolution" }
if ($Samples -gt 0) { $prepare += "--samples=$Samples" }
Invoke-GemStage 'prepare' $prepare
if ($PlanOnly) { exit 0 }
Invoke-GemStage 'render' @('--path', $projectRoot, '--quit-after', '600', '--script', 'res://tools/gem_frame_worker.gd', '--', '--manifest=res://generated/gem-job-bundle/manifest.json', '--output=res://generated/gemfactory')
Invoke-GemStage 'pack' @('--headless', '--path', $projectRoot, '--quit-after', '600', '--script', 'res://tools/pack_gem_library.gd', '--', "--codec=$Codec", "--page=$Page")
if (-not $SkipCollection) {
    Invoke-GemStage 'collect' @('--headless', '--path', $projectRoot, '--quit-after', '600', '--script', 'res://tools/maintain_gem_store.gd', '--', "--budget-mib=$CacheBudgetMiB", '--apply=true')
}
