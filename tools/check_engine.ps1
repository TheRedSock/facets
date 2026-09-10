param(
    [string]$Godot = 'C:/Godot/Godot_v4.6.1-stable_win64_console.exe',
    [switch]$Gpu
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$logRoot = Join-Path $projectRoot 'artifacts/checks'
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$checks = @('test_foundation', 'test_geometry', 'test_boundaries', 'test_factory', 'test_species_data', 'test_pleochroism', 'test_clips', 'test_board_consumer', 'test_cut_compiler')
$failed = @()
foreach ($check in $checks) {
    $output = & $Godot --headless --path $projectRoot --quit-after 600 --script "res://tests/lapidary/$check.gd" 2>&1
    $code = $LASTEXITCODE
    $output | Set-Content -Encoding utf8 -LiteralPath (Join-Path $logRoot "$check.log")
    # Godot can exit zero after a GDScript exception; exit status alone is unsafe.
    if ($code -ne 0 -or ($output | Select-String -Pattern '^\s*(SCRIPT ERROR:|ERROR:|FAIL(:|\b)|FAILED\b)')) {
        $failed += $check
        Write-Output "FAIL $check (see artifacts/checks/$check.log)"
        Write-Output $output
    } else {
        Write-Output "PASS $check"
    }
}
if ($Gpu) {
  foreach ($check in @('foundation_gpu_check', 'factory_gpu_check', 'library_gpu_check')) {
    $output = & $Godot --path $projectRoot --quit-after 600 --script "res://tools/$check.gd" 2>&1
    $code = $LASTEXITCODE
    $output | Set-Content -Encoding utf8 -LiteralPath (Join-Path $logRoot "$check.log")
    if ($code -ne 0 -or ($output | Select-String -Pattern '^\s*(SCRIPT ERROR:|ERROR:|FAIL(:|\b)|FAILED\b)')) {
        $failed += $check
        Write-Output $output
    } else {
        Write-Output "PASS $check"
    }
  }
}
if ($failed.Count -gt 0) {
    Write-Output "Failed checks: $($failed -join ', ')"
    exit 1
}
exit 0
