function Get-GodotCheckResult {
    param([int]$ExitCode, [string]$Output, [string]$Completion)
    $environmentErrors = @($Output -split "`r?`n" | Where-Object { $_ -match '^ERROR: (Failed to read the root certificate store\.|Could not create editor (data|config|cache) directory:)' })
    $errors = @($Output -split "`r?`n" | Where-Object { $_ -match '^\s*(SCRIPT ERROR:|ERROR:|FAIL(:|\b)|FAILED\b)' })
    $complete = @($Output -split "`r?`n" | Where-Object { $_.Trim() -eq $Completion }).Count -gt 0
    if ($Completion -eq 'first_scan_filesystem') {
        $complete = $Output -match '\[ DONE \].*first_scan_filesystem'
    }
    [pscustomobject]@{
        passed = ($ExitCode -eq 0 -and $complete -and $errors.Count -eq 0)
        completed = $complete
        exit_code = $ExitCode
        errors = $errors
        environment_errors = $environmentErrors
    }
}
