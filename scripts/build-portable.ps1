#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourcePath,
    [string]$MSBuildPath,
    [string]$WindowsSdkVersion
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path -Parent $PSScriptRoot

function Require-File([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file is missing: $Path"
    }
}

$resourceRoot = (Resolve-Path -LiteralPath $ResourcePath).Path
if (Test-Path -LiteralPath (Join-Path $resourceRoot 'CdiResource') -PathType Container) {
    $resourceRoot = Join-Path $resourceRoot 'CdiResource'
}
$distributionRoot = Split-Path -Parent $resourceRoot
Require-File (Join-Path $resourceRoot 'dialog/Graph.html')
$defaultTheme = Join-Path $resourceRoot 'themes/Default'
if (-not (Test-Path -LiteralPath $defaultTheme -PathType Container)) {
    throw 'Missing CdiResource/themes/Default. Use the extracted official Standard Edition resources.'
}
if (@(Get-ChildItem -LiteralPath $defaultTheme -Filter '*.png' -File).Count -eq 0) {
    throw 'The Default theme contains no PNG assets.'
}
Require-File (Join-Path $repo 'Language/English.lang')
Require-File (Join-Path $repo 'LICENSE.txt')

if (-not $MSBuildPath) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    Require-File $vswhere
    $installation = & $vswhere -latest -products '*' -version '[17.0,18.0)' `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($LASTEXITCODE -ne 0 -or -not $installation) {
        throw 'Visual Studio 2022 C++ tools were not found. The build needs v143 C++ tools, MFC for x86/x64, and a Windows SDK.'
    }
    $MSBuildPath = Join-Path $installation 'MSBuild/Current/Bin/MSBuild.exe'
}
Require-File $MSBuildPath
$kitsRoot = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots').KitsRoot10
if (-not $WindowsSdkVersion) {
    $sdk = Get-ChildItem -LiteralPath (Join-Path $kitsRoot 'Include') -Directory |
        Where-Object {
            $_.Name -match '^10\.0\.\d+\.\d+$' -and
            (Test-Path -LiteralPath (Join-Path $_.FullName 'um/Windows.h')) -and
            (Test-Path -LiteralPath (Join-Path $kitsRoot "Lib/$($_.Name)/um/x64/kernel32.lib")) -and
            (Test-Path -LiteralPath (Join-Path $kitsRoot "Lib/$($_.Name)/ucrt/x64/libucrt.lib"))
        } | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
    if (-not $sdk) { throw 'No complete Windows 10/11 SDK for x64 was found.' }
    $WindowsSdkVersion = $sdk.Name
}
Require-File (Join-Path $kitsRoot "Include/$WindowsSdkVersion/um/Windows.h")

# Fresh output paths prevent stale binaries from entering a package. No existing
# build output or user settings are removed.
$runId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$buildRoot = Join-Path $repo "artifacts/build/$runId"
$bin = Join-Path $buildRoot 'bin'
$obj = Join-Path $buildRoot 'obj'
$package = Join-Path $repo "artifacts/portable/CrystalDiskInfo-x64-$runId"
New-Item -ItemType Directory -Path $bin, $obj -Force | Out-Null

# Override upstream hard-coded intermediate paths without changing the vcxproj.
$overrides = Join-Path $buildRoot 'portable.targets'
$overrideXml = @"
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <ItemDefinitionGroup>
    <ClCompile><ProgramDataBaseFileName>`$(IntDir)compiler.pdb</ProgramDataBaseFileName></ClCompile>
    <Link>
      <ProgramDatabaseFile>`$(IntDir)DiskInfo64.pdb</ProgramDatabaseFile>
      <ProfileGuidedDatabase>`$(IntDir)DiskInfo64.pgd</ProfileGuidedDatabase>
      <ManifestFile>`$(IntDir)DiskInfo64.intermediate.manifest</ManifestFile>
    </Link>
    <BuildLog><Path>`$(IntDir)DiskInfo.log</Path></BuildLog>
  </ItemDefinitionGroup>
</Project>
"@
$overrideXml | Set-Content -LiteralPath $overrides -Encoding UTF8
$buildArgs = @(
    (Join-Path $repo 'DiskInfo.vcxproj'), '/t:Build', '/m:2', '/nologo',
    '/p:Configuration=Release', '/p:Platform=x64', '/p:PlatformToolset=v143',
    "/p:WindowsTargetPlatformVersion=$WindowsSdkVersion", '/p:TargetName=DiskInfo64',
    "/p:OutDir=$bin/", "/p:IntDir=$obj/",
    "/p:ForceImportBeforeCppTargets=$overrides",
    "/bl:$buildRoot/build.binlog", "/flp:logfile=$buildRoot/build.log;verbosity=normal"
)
Push-Location $repo
try {
    & $MSBuildPath @buildArgs
    if ($LASTEXITCODE -ne 0) {
        throw "MSBuild failed with exit code $LASTEXITCODE. See $buildRoot/build.log. Ensure v143 MFC is installed."
    }
} finally {
    Pop-Location
}
$exe = Join-Path $bin 'DiskInfo64.exe'
Require-File $exe

$packResources = Join-Path $package 'CdiResource'
New-Item -ItemType Directory -Path $package, $packResources -Force | Out-Null
Copy-Item -LiteralPath $exe -Destination $package
Copy-Item -LiteralPath (Join-Path $repo 'LICENSE.txt') -Destination $package
Copy-Item -LiteralPath (Join-Path $repo 'PORTABLE.md') -Destination $package
Copy-Item -LiteralPath (Join-Path $resourceRoot 'dialog') -Destination $packResources -Recurse
New-Item -ItemType Directory -Path (Join-Path $packResources 'themes') -Force | Out-Null
foreach ($theme in @('Default', 'Dark', 'FlatSquare', 'Simplicity')) {
    $source = Join-Path $resourceRoot "themes/$theme"
    if (Test-Path -LiteralPath $source -PathType Container) {
        Copy-Item -LiteralPath $source -Destination (Join-Path $packResources 'themes') -Recurse
    }
}
New-Item -ItemType Directory -Path (Join-Path $packResources 'language') -Force | Out-Null
Get-ChildItem -LiteralPath (Join-Path $repo 'Language') -Filter '*.lang' -File |
    Copy-Item -Destination (Join-Path $packResources 'language')

# Explicitly retain x64 storage helpers and email dependencies. Never copy
# downloaded DiskInfo binaries, other CPU architectures, voices, or settings.
$optionalFiles = @(
    'dll/JMS56x64.dll', 'dll/JMB39x64.dll', 'dll/JMS586x64.dll',
    'dll/JMS586_40x64.dll', 'dll/JMS59x64.dll', 'dll/AMD_RC2t7x64.dll',
    'AlertMail.exe', 'AlertMail4.exe', 'AlertMail48.exe',
    'MailKit.dll', 'MimeKit.dll', 'System.Buffers.dll'
)
$missingOptional = @()
foreach ($relative in $optionalFiles) {
    $source = Join-Path $resourceRoot $relative
    if (Test-Path -LiteralPath $source -PathType Leaf) {
        $destination = Join-Path $packResources $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination
    } else {
        $missingOptional += $relative
    }
}
if (Test-Path -LiteralPath (Join-Path $resourceRoot 'opus') -PathType Container) {
    Copy-Item -LiteralPath (Join-Path $resourceRoot 'opus') -Destination $packResources -Recurse
}
if (Test-Path -LiteralPath (Join-Path $distributionRoot 'License') -PathType Container) {
    Copy-Item -LiteralPath (Join-Path $distributionRoot 'License') -Destination $package -Recurse
}
# Also keep notices next to any optional helper libraries.
foreach ($noticeRoot in @($resourceRoot, (Join-Path $resourceRoot 'dll'))) {
    if (Test-Path -LiteralPath $noticeRoot -PathType Container) {
        Get-ChildItem -LiteralPath $noticeRoot -File | Where-Object {
            $_.Extension -in '.txt', '.md' -or $_.Name -match '^(LICENSE|COPYING|NOTICE)'
        } | ForEach-Object {
            $relative = $_.FullName.Substring($resourceRoot.Length).TrimStart('\', '/')
            $destination = Join-Path $packResources $relative
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
            Copy-Item -LiteralPath $_.FullName -Destination $destination
        }
    }
}
if ($missingOptional.Count -gt 0) {
    Write-Warning ('Optional helpers absent (related RAID or email features may be unavailable): ' + ($missingOptional -join ', '))
}
$manifest = Get-ChildItem -LiteralPath $package -Recurse -File | Sort-Object FullName | ForEach-Object {
    $relative = $_.FullName.Substring($package.Length + 1).Replace('\', '/')
    '{0}  {1}' -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(), $relative
}
$manifest | Set-Content -LiteralPath (Join-Path $package 'SHA256SUMS.txt') -Encoding ASCII
$zip = "$package.zip"
Compress-Archive -LiteralPath $package -DestinationPath $zip -CompressionLevel Optimal
$zipHash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
"$zipHash  $([IO.Path]::GetFileName($zip))" | Set-Content -LiteralPath "$zip.sha256" -Encoding ASCII
[pscustomobject]@{
    Executable = (Join-Path $package 'DiskInfo64.exe')
    PackageDirectory = $package
    Zip = $zip
    SHA256 = $zipHash
    BuildLog = (Join-Path $buildRoot 'build.log')
    WindowsSdkVersion = $WindowsSdkVersion
}
