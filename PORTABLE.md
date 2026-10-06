# Portable x64 build

This builds the Standard Edition from this checkout and packages it as a portable
folder and ZIP. Extract the whole ZIP into a writable folder, then launch
`DiskInfo64.exe`. Keep `CdiResource` beside it. Windows requests administrator
permission to read drive information. Settings and SMART history are written
beside the executable; preserve that folder when updating or moving the app.

## Build

Prerequisites: Windows, PowerShell 5.1 or newer, Visual Studio 2022 C++ build tools,
the v143 MFC component for x86/x64, and a Windows 10/11 SDK. The main executable
uses static MFC and CRT linking. The script does not install prerequisites.

The upstream repository does not include all runtime resources. Download and
extract the official **Standard Edition ZIP** matching the source version
(`PRODUCT_VERSION` in `Library/stdafx.h`). The repository's download helper pins
the official archive and checks its SHA-256 checksum:

```powershell
.\scripts\get-portable-resources.ps1
.\scripts\build-portable.ps1 -ResourcePath .\artifacts\resources
```

Alternatively, pass your own extracted distribution from the
[upstream download page](https://crystalmark.info/en/software/crystaldiskinfo/).
`-ResourcePath` accepts either the folder containing `CdiResource`, or
`CdiResource` itself. Keep the sibling `License` directory with those resources.

The script selects installed VS 2022 and the latest complete installed Windows
SDK. To pin the build environment, supply `-MSBuildPath 'C:\...\MSBuild.exe'
-WindowsSdkVersion '10.0.26100.0'` using versions installed on your machine.
Retain the same source revision, resource ZIP and toolchain to reproduce a build;
binary-identical ZIP output is not promised.

Every invocation uses fresh directories under `artifacts/build` and
`artifacts/portable`. It outputs a package folder, ZIP, ZIP SHA-256 checksum, and
per-file `SHA256SUMS.txt`. Build logs are retained as `build.log` and
`build.binlog`. A failed build does not create a ZIP or reuse an older executable.

## Package contents and dependencies

- The `DiskInfo64.exe` compiled from this checkout, MIT license, and this guide.
- `CdiResource/dialog`: graph HTML, JavaScript, and supporting assets.
- `CdiResource/themes`: Default and supplied standard Dark, FlatSquare and
  Simplicity themes.
- `CdiResource/language`: all translations from this checkout's `Language` folder.
- Supplied x64 AMD/JMicron RAID DLLs, email helpers and their libraries, Opus
  decoder, and resource license notices. Missing optional DLLs disable their
  corresponding device support; missing email helpers affect notifications.

The downloaded distribution's DiskInfo executables, other architectures, edition
voices, and pre-existing settings are excluded. `Graph.html`, the Default theme,
and `English.lang` are checked before compilation. The graph UI relies on Windows'
MSHTML/COM components; optional email helpers may require .NET. Helper binaries
come from the supplied official resources and are not rebuilt by this script;
retain their accompanying licenses when redistributing.

After building, launch the packaged executable and verify drive detection, the
graph window, language selection, and retained settings on the target Windows
system. Building alone does not verify hardware-specific RAID/USB support.
