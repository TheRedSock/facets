$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../tools/check_result.ps1')
$cases = @(
    @{ Code = 0; Text = 'PASS an intermediate assertion'; Marker = 'CHECK_COMPLETE: fixture'; Expected = $false },
    @{ Code = 0; Text = 'CHECK_COMPLETE: fixture'; Marker = 'CHECK_COMPLETE: fixture'; Expected = $true },
    @{ Code = 1; Text = 'CHECK_COMPLETE: fixture'; Marker = 'CHECK_COMPLETE: fixture'; Expected = $false },
    @{ Code = 0; Text = "SCRIPT ERROR: failure`nCHECK_COMPLETE: fixture"; Marker = 'CHECK_COMPLETE: fixture'; Expected = $false },
    @{ Code = 0; Text = "ERROR: Failed to read the root certificate store.`nCHECK_COMPLETE: fixture"; Marker = 'CHECK_COMPLETE: fixture'; Expected = $false },
    @{ Code = 0; Text = 'CHECK_COMPLETE: another_test'; Marker = 'CHECK_COMPLETE: fixture'; Expected = $false },
    @{ Code = 0; Text = 'CHECK_COMPLETE: fixture_suffix'; Marker = 'CHECK_COMPLETE: fixture'; Expected = $false },
    @{ Code = 0; Text = 'Started first_scan_filesystem'; Marker = 'first_scan_filesystem'; Expected = $false }
)
foreach ($case in $cases) {
    $result = Get-GodotCheckResult -ExitCode $case.Code -Output $case.Text -Completion $case.Marker
    if ($result.passed -ne $case.Expected) { throw "Incorrect stage classification: $($case.Text)" }
}
Write-Output 'Check result: 8 cases passed (including incomplete, wrong-stage, exit-zero exception and environment error)'
