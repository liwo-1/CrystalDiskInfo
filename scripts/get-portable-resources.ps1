[CmdletBinding()]
param(
    [string]$Destination = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts/resources')
)

$ErrorActionPreference = 'Stop'
$version = '9.9.2'
$expectedHash = '01acb3176851a85824d9589c6514e3eb9771eb7f9d5ee58ed9b4e057bd21c7df'
$destinationPath = [IO.Path]::GetFullPath($Destination)
if (Test-Path -LiteralPath $destinationPath) {
    throw "Resource destination already exists: $destinationPath. Use an empty destination or pass the existing resources to build-portable.ps1."
}
$downloadDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts/downloads'
New-Item -ItemType Directory -Path $downloadDirectory -Force | Out-Null
$archive = Join-Path $downloadDirectory "CrystalDiskInfo${version}.zip"
$url = 'https://downloads.sourceforge.net/project/crystaldiskinfo/9.9.2/CrystalDiskInfo9_9_2.zip?download=1&use_mirror=pilotfiber'
& curl.exe --fail --location --retry 2 --connect-timeout 20 --max-time 180 --output $archive $url
if ($LASTEXITCODE -ne 0) { throw "Resource download failed (curl exit $LASTEXITCODE)." }
$actualHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne $expectedHash) {
    throw "Resource archive failed SHA-256 verification. Expected $expectedHash; got $actualHash."
}
Expand-Archive -LiteralPath $archive -DestinationPath $destinationPath
if (-not (Test-Path -LiteralPath (Join-Path $destinationPath 'CdiResource/dialog/Graph.html'))) {
    throw 'Verified archive does not contain the required runtime resources.'
}
Write-Host "Verified CrystalDiskInfo $version resources: $destinationPath"
