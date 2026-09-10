param(
    [string]$Godot = 'C:/Godot/Godot_v4.6.1-stable_win64_console.exe',
    [string]$Stone = '',
    [string]$Clip = '',
    [ValidateSet('interact', 'preview', 'board_live', 'clip_bake', 'hero', 'reference')]
    [string]$Rung = 'clip_bake',
    [ValidateSet('webp_lossless', 'bc7', 'astc4x4')]
    [string]$Codec = 'webp_lossless',
    [int]$Resolution = 0,
    [int]$Samples = 0,
    [int]$Page = 512,
    [switch]$PlanOnly
)
# Generated source bundle/ZIP, resumable store and shipping PCK stay ignored.
# Copy generated/gem-assets.pck next to an exported game executable.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$logRoot = Join-Path $projectRoot 'artifacts/build-assets'
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
function Invoke-GemStage([string]$Name, [string[]]$Arguments) {
    $log = Join-Path $logRoot "$Name.log"
    & $Godot @Arguments 2>&1 | Tee-Object -FilePath $log
    if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $log -Pattern '^\s*(SCRIPT ERROR:|ERROR:|FAIL(:|\b)|FAILED\b)')) {
        throw "Asset stage $Name failed; see $log"
    }
}
$prepare = @('--headless', '--path', $projectRoot, '--quit-after', '600', '--script', 'res://tools/prepare_gem_jobs.gd', '--', "--rung=$Rung")
if ($Stone) { $prepare += "--stone=$Stone" }
if ($Clip) { $prepare += "--clip=$Clip" }
if ($Resolution -gt 0) { $prepare += "--resolution=$Resolution" }
if ($Samples -gt 0) { $prepare += "--samples=$Samples" }
Invoke-GemStage 'prepare' $prepare
if ($PlanOnly) { exit 0 }
Invoke-GemStage 'render' @('--path', $projectRoot, '--quit-after', '600', '--script', 'res://tools/gem_frame_worker.gd', '--', '--manifest=res://generated/gem-job-bundle/manifest.json', '--output=res://generated/gemfactory')
Invoke-GemStage 'pack' @('--headless', '--path', $projectRoot, '--quit-after', '600', '--script', 'res://tools/pack_gem_library.gd', '--', "--codec=$Codec", "--page=$Page")
