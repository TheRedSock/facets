param(
    [string]$Godot = 'C:/Godot/Godot_v4.6.1-stable_win64_console.exe',
    [switch]$Gpu
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$logRoot = Join-Path $projectRoot 'artifacts/checks'
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$stages = @(
    @{ Name = 'import'; Args = @('--headless', '--editor', '--quit') },
    @{ Name = 'source_check'; Args = @('--headless', '--quit-after', '600', 'res://tools/source_check.tscn') }
)
foreach ($name in @('test_foundation', 'test_geometry', 'test_boundaries', 'test_factory', 'test_store_maintenance', 'test_spectra', 'test_material_inputs', 'test_optical_depth', 'test_species_data', 'test_pleochroism', 'test_clips', 'test_board_consumer', 'test_cut_compiler')) {
    $stages += @{ Name = $name; Args = @('--headless', '--quit-after', '600', '--script', "res://tests/lapidary/$name.gd") }
}
if ($Gpu) {
    foreach ($name in @('foundation_gpu_check', 'factory_gpu_check', 'library_gpu_check', 'surface_check', 'spectra_gpu_check')) {
        $stages += @{ Name = $name; Args = @('--quit-after', '600', '--script', "res://tools/$name.gd") }
    }
}
$failed = @()
foreach ($stage in $stages) {
    $arguments = @('--path', $projectRoot) + $stage.Args
    $output = & $Godot @arguments 2>&1
    $code = $LASTEXITCODE
    $log = Join-Path $logRoot ($stage.Name + '.log')
    $output | Set-Content -Encoding utf8 -LiteralPath $log
    # Godot can exit zero after a GDScript exception; exit status alone is unsafe.
    if ($code -ne 0 -or ($output | Select-String -Pattern '^\s*(SCRIPT ERROR:|ERROR:|FAIL(:|\b)|FAILED\b)')) {
        $failed += $stage.Name
        Write-Output "FAIL $($stage.Name) (see $log)"
        Write-Output $output
    } else {
        Write-Output "PASS $($stage.Name)"
    }
}
if ($failed.Count -gt 0) {
    Write-Output "Failed checks: $($failed -join ', ')"
    exit 1
}
exit 0
