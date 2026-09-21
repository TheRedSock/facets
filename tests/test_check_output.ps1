$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$destination = Join-Path $repo ('artifacts/check-runner-tests/' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $destination | Out-Null
$sentinel = Join-Path $destination 'historical.txt'
'immutable evidence' | Set-Content -LiteralPath $sentinel
$before = (Get-FileHash -LiteralPath $sentinel).Hash
$output = & pwsh -NoProfile -File (Join-Path $repo 'tools/check_engine.ps1') -Only import -OutputRoot $destination -Godot 'must-not-launch.exe' 2>&1
if ($LASTEXITCODE -eq 0 -or "$output" -notmatch 'must be new or empty') { throw "Expected occupied-output rejection: $output" }
if ((Get-FileHash -LiteralPath $sentinel).Hash -cne $before -or @(Get-ChildItem -LiteralPath $destination).Count -ne 1) { throw 'Historical evidence was modified' }
Write-Output 'CHECK_COMPLETE: test_check_output (occupied directory rejected before engine launch; evidence unchanged)'
