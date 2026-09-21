function Invoke-BoundedCheckProcess {
    param([string]$Executable, [string[]]$Arguments, [int]$TimeoutSeconds = 900, [string]$WorkingDirectory = '')
    if ($TimeoutSeconds -lt 1) { throw 'Check timeout must be positive' }
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Executable
    if ($WorkingDirectory) { $startInfo.WorkingDirectory = $WorkingDirectory }
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $startInfo.ArgumentList.Add($argument) }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw 'Cannot start validation process' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $deadline = [Diagnostics.Stopwatch]::StartNew()
        $peakWorking = [long]0
        $peakPrivate = [long]0
        $finished = $false
        while ($deadline.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
            if ($process.WaitForExit(1000)) { $finished = $true; break }
            try {
                $process.Refresh()
                $peakWorking = [Math]::Max($peakWorking, $process.PeakWorkingSet64)
                $peakPrivate = [Math]::Max($peakPrivate, $process.PrivateMemorySize64)
            } catch {
                if (-not $process.HasExited) { throw }
                $finished = $true; break
            }
        }
        $timedOut = -not $finished
        if ($timedOut) {
            $process.Kill($true)
            $process.WaitForExit()
        }
        $output = $stdout.GetAwaiter().GetResult() + "`n" + $stderr.GetAwaiter().GetResult()
        if ($timedOut) { $output += "`nERROR: Validation process exceeded ${TimeoutSeconds}s and was terminated." }
        return [pscustomobject]@{ output = $output; exit_code = $(if ($timedOut) { 124 } else { $process.ExitCode }); timed_out = $timedOut; peak_working_set_bytes = $peakWorking; sampled_peak_private_bytes = $peakPrivate }
    } finally { $process.Dispose() }
}
