param(
    [string]$Godot = 'C:/Godot/Godot_v4.6.1-stable_win64_console.exe',
    [switch]$Gpu,
    [switch]$CrystalPrecision,
    [string]$ReferencePython = ''
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$logRoot = Join-Path $projectRoot 'artifacts/checks'
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$stages = @(
    @{ Name = 'import'; Args = @('--headless', '--editor', '--quit') },
    @{ Name = 'source_check'; Args = @('--headless', '--quit-after', '600', 'res://tools/source_check.tscn') }
)
foreach ($name in @('test_foundation', 'test_cleavage', 'test_mesh_admission', 'test_geometry', 'test_boundaries', 'test_factory', 'test_job_validation', 'test_store_maintenance', 'test_store_transfer', 'test_spectra', 'test_material_inputs', 'test_principal_indices', 'test_crystal_admission', 'test_optical_depth', 'test_volume_fields', 'test_polarization', 'test_crystal_modes', 'test_crystal_interface', 'test_crystal_packet', 'test_crystal_loss', 'test_species_data', 'test_pleochroism', 'test_clips', 'test_board_consumer', 'test_cut_compiler', 'test_cut_design')) {
    $stages += @{ Name = $name; Args = @('--headless', '--quit-after', '600', '--script', "res://tests/lapidary/$name.gd") }
}
$stages += @{ Name = 'test_fracture'; Args = @('--headless', '--quit-after', '600', '--script', 'res://tests/lapidary/test_fracture.gd') }
$stages += @{ Name = 'test_volume_authoring'; Args = @('--headless', '--quit-after', '600', '--script', 'res://tests/lapidary/test_volume_authoring.gd') }
$stages += @{ Name = 'test_geometry_factory'; Args = @('--headless', '--quit-after', '600', '--script', 'res://tests/lapidary/test_geometry_factory.gd') }
$stages += @{ Name = 'test_render_dependencies'; Args = @('--headless', '--quit-after', '600', '--script', 'res://tests/lapidary/test_render_dependencies.gd') }
$stages += @{ Name = 'test_finish_fields'; Args = @('--headless', '--quit-after', '600', '--script', 'res://tests/lapidary/test_finish_fields.gd') }
if ($ReferencePython) {
    $stages += @{ Name = 'export_polarization_checks'; Args = @('--headless', '--quit-after', '600', '--script', 'res://tools/export_polarization_checks.gd') }
}
if ($Gpu) {
	$stages += @{ Name = 'cleavage_gpu_check'; Args = @('--quit-after', '600', '--script', 'res://tools/cleavage_gpu_check.gd') }
	$stages += @{ Name = 'cleavage_portable_check'; Args = @('--headless', '--quit-after', '600', '--script', 'res://tools/cleavage_portable_check.gd') }
	$stages += @{ Name = 'finish_fields_gpu_check'; Args = @('--quit-after', '600', '--script', 'res://tools/finish_fields_gpu_check.gd') }
	$stages += @{ Name = 'finish_fields_render_check'; Args = @('--quit-after', '600', '--script', 'res://tools/finish_fields_render_check.gd') }
	$stages += @{ Name = 'microsurface_gpu_check'; Args = @('--quit-after', '600', '--script', 'res://tools/microsurface_gpu_check.gd') }
	$stages += @{ Name = 'pipeline_cache_check'; Args = @('--quit-after', '600', '--script', 'res://tools/pipeline_cache_check.gd') }
    $stages += @{ Name = 'geometry_factory_check'; Args = @('--quit-after', '600', '--script', 'res://tools/geometry_factory_check.gd') }
    foreach ($name in @('foundation_gpu_check', 'factory_gpu_check', 'farm_gpu_check', 'library_gpu_check', 'surface_check', 'spectra_gpu_check', 'principal_indices_gpu_check', 'volume_gpu_check', 'polarization_gpu_check', 'crystal_gpu_check', 'crystal_transport_check', 'geometry_aov_check')) {
        $stages += @{ Name = $name; Args = @('--quit-after', '600', '--script', "res://tools/$name.gd") }
    }
}
if ($CrystalPrecision) {
    $stages += @{ Name = 'crystal_gpu_precision'; Args = @('--quit-after', '600', '--script', 'res://tools/crystal_gpu_check.gd', '--', '--stress', '--fp64') }
}
$failed = @()
foreach ($stage in $stages) {
    $arguments = @('--audio-driver', 'Dummy', '--path', $projectRoot) + $stage.Args
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
if ($ReferencePython -and $failed.Count -eq 0) {
    $referenceChecks = @('check_mesh_predicates', 'check_polarization_reference', 'check_crystal_modes_reference', 'check_crystal_interface_reference', 'check_crystal_packet_reference', 'check_crystal_loss_reference')
    if ($Gpu) { $referenceChecks += @('check_gpu_polarization_reference', 'check_microsurface_reference', 'check_finish_fields_reference') }
    foreach ($name in $referenceChecks) {
        $output = & $ReferencePython (Join-Path $projectRoot "tools/$name.py") 2>&1
        $code = $LASTEXITCODE
        $output | Set-Content -Encoding utf8 -LiteralPath (Join-Path $logRoot "$name.log")
        if ($code -ne 0) { $failed += $name }
        else { Write-Output "PASS $name" }
        Write-Output $output
    }
}
if ($failed.Count -gt 0) {
    Write-Output "Failed checks: $($failed -join ', ')"
    exit 1
}
exit 0
