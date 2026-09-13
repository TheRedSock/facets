param([string]$Godot = 'C:/Godot/Godot_v4.6.1-stable_win64_console.exe')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'tools/check_process.ps1')
$outputRoot = Join-Path $projectRoot 'artifacts/check-process-tests'
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
$fixture = Join-Path $outputRoot 'incomplete.gd'
@'
extends SceneTree
func _initialize() -> void:
    print("RUNNING_PID: " + str(OS.get_process_id()))
'@ | Set-Content -Encoding utf8 -LiteralPath $fixture
$result = Invoke-BoundedCheckProcess -Executable $Godot -Arguments @('--headless', '--path', $projectRoot, '--script', $fixture) -TimeoutSeconds 2
if (-not $result.timed_out -or $result.exit_code -ne 124 -or $result.output -notmatch 'RUNNING_PID: (\d+)') { throw "Expected a started but incomplete Godot process: $($result.output)" }
$nativePid = [int]$Matches[1]
if (Get-Process -Id $nativePid -ErrorAction SilentlyContinue) { throw 'Timed-out Godot child survived termination' }
$result = Invoke-BoundedCheckProcess -Executable $Godot -Arguments @('--version') -TimeoutSeconds 10
if ($result.timed_out -or $result.exit_code -ne 0 -or $result.output -notmatch '^4\.6') { throw 'Successful command result was lost' }
Write-Output 'CHECK_COMPLETE: test_check_process (timeout, child termination, successful completion)'
