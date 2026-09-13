param([string]$Archive = '')
# Pinned official 4.6.1 Windows templates; no global installation or ZIP expansion.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$destination = Join-Path $projectRoot 'artifacts/toolchain/godot-4.6.1'
New-Item -ItemType Directory -Force -Path $destination | Out-Null
$expectedArchive = 'e6d372afd4fdfaae9571eb5e3568afcd96ce6db9a569244034154faf0ac69875'
if (-not $Archive) {
    $Archive = Join-Path $destination 'export_templates.tpz'
    if (-not (Test-Path -LiteralPath $Archive)) {
        Invoke-WebRequest -Uri 'https://github.com/godotengine/godot-builds/releases/download/4.6.1-stable/Godot_v4.6.1-stable_export_templates.tpz' -OutFile ($Archive + '.download')
        if ((Get-FileHash -LiteralPath ($Archive + '.download') -Algorithm SHA256).Hash -ne $expectedArchive) { throw 'Downloaded template archive checksum mismatch' }
        Move-Item -LiteralPath ($Archive + '.download') -Destination $Archive
    }
}
if ((Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash -ne $expectedArchive) { throw 'Template archive checksum mismatch' }
$expected = @{
    'windows_debug_x86_64.exe' = '8515cd8041a906bdf82a3c9926125e20f642a1062cb2a45a962f3a43dffa41ed'
    'windows_release_x86_64.exe' = '6a0266cb7571aa4d437a32094acd353f020c77dcf7ff5a3305ae45d0609e5c20'
}
$archiveFile = [System.IO.Compression.ZipFile]::OpenRead($Archive)
try {
    foreach ($name in $expected.Keys) {
        $entry = $archiveFile.GetEntry("templates/$name")
        if (-not $entry) { throw "Missing template ZIP member: $name" }
        $path = Join-Path $destination $name
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $path, $true)
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $expected[$name]) { throw "Extracted template checksum mismatch: $name" }
    }
} finally { $archiveFile.Dispose() }
Write-Output "EXPORT_TEMPLATES_COMPLETE: $destination"
