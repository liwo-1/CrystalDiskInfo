[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ArchivePath
)

$ErrorActionPreference = 'Stop'
$archive = (Resolve-Path -LiteralPath $ArchivePath).Path
$testRoot = Join-Path (Split-Path $PSScriptRoot -Parent) ('artifacts/smoke/' + [Guid]::NewGuid().ToString('N'))
Expand-Archive -LiteralPath $archive -DestinationPath $testRoot
$executables = @(Get-ChildItem -LiteralPath $testRoot -Filter DiskInfo64.exe -Recurse -File)
if ($executables.Count -ne 1) { throw 'Expected exactly one DiskInfo64.exe in the portable archive.' }
$executable = $executables[0]
$packageRoot = $executable.DirectoryName
foreach ($relative in @('CdiResource/dialog/Graph.html', 'CdiResource/language/English.lang', 'CdiResource/themes/Default', 'LICENSE.txt')) {
    if (-not (Test-Path -LiteralPath (Join-Path $packageRoot $relative))) {
        throw "Portable archive is missing $relative."
    }
}

# The upstream application requires elevation to read drive health information.
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Runtime smoke test requires an elevated Windows session; package validation passed, but runtime has not been tested.'
}

$process = Start-Process -FilePath $executable.FullName -ArgumentList '/CopyExit' -WorkingDirectory $packageRoot -WindowStyle Hidden -PassThru
if (-not $process.WaitForExit(45000)) {
    $process.Kill()
    $process.WaitForExit()
    throw 'Portable runtime smoke test timed out after 45 seconds.'
}
if ($process.ExitCode -ne 0) { throw "Portable executable exited with code $($process.ExitCode)." }
$report = Join-Path $packageRoot 'DiskInfo.txt'
if (-not (Test-Path -LiteralPath $report)) { throw 'Application exited without producing its drive report.' }
if ((Get-Content -LiteralPath $report -Raw) -notmatch 'CrystalDiskInfo') {
    throw 'Drive report is missing the CrystalDiskInfo header.'
}
Write-Host 'Portable archive passed startup and report generation after extraction to a new folder.'
Write-Host 'Hardware-specific SMART support still depends on the target computer and drive.'
