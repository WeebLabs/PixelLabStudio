<#
.SYNOPSIS
  Builds the Windows release: Godot export -> portable zip + Inno Setup installer + SHA256SUMS.

.DESCRIPTION
  The version comes from application/config/version in project.godot (semver).
  The Windows preset's product_version must already be its 4-part form
  (AppVersion.windows_numeric, enforced by tests/unit/test_release_contract.gd);
  the build stops if they disagree rather than shipping mismatched metadata.

  Output (.artifacts/, ignored):
    exports/windows/                              raw export
    installer/windows/PixelLabStudio-v<ver>-Windows-x64.zip        portable build
    installer/windows/PixelLabStudio-v<ver>-Windows-x64-Setup.exe  installer
    installer/windows/SHA256SUMS.txt

  Release asset names are fixed: the future auto-updater matches on them.

.PARAMETER Godot
  Godot 4.6 editor executable. Defaults to $env:GODOT_BIN, then `godot` on PATH.

.PARAMETER Iscc
  Inno Setup compiler. Defaults to $env:ISCC, `iscc` on PATH, then the standard install paths.

.PARAMETER Tag
  Release tag being built (CI). The build fails unless it equals "v" + config/version.

.PARAMETER SkipExport
  Reuse the existing export (iterating on the installer script).
#>
param(
    [string]$Godot = $env:GODOT_BIN,
    [string]$Iscc = $env:ISCC,
    [string]$Tag = "",
    [switch]$SkipExport
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path "$PSScriptRoot\..\..").Path
$ExportDir = Join-Path $Root ".artifacts\exports\windows"
$OutDir = Join-Path $Root ".artifacts\installer\windows"
$ExeName = "PixelLab Studio.exe"
$PresetName = "Windows Desktop"

function Get-ConfigValue([string]$file, [string]$key) {
    $line = Select-String -Path (Join-Path $Root $file) -Pattern "^$([regex]::Escape($key))=`"([^`"]+)`"" | Select-Object -First 1
    if (-not $line) { throw "$key is missing from $file" }
    return $line.Matches[0].Groups[1].Value
}

# Mirrors AppVersion.windows_numeric(): alpha.N -> N, beta.N -> 100+N,
# rc.N -> 200+N, release -> 1000 in the fourth field.
function ConvertTo-NumericVersion([string]$semver) {
    if ($semver -notmatch '^(\d+)\.(\d+)\.(\d+)(?:-(alpha|beta|rc)\.(\d+))?$') {
        throw "config/version '$semver' is not MAJOR.MINOR.PATCH[-alpha|beta|rc.N]"
    }
    $build = switch ($Matches[4]) {
        "alpha" { [int]$Matches[5] }
        "beta"  { 100 + [int]$Matches[5] }
        "rc"    { 200 + [int]$Matches[5] }
        default { 1000 }
    }
    return "$($Matches[1]).$($Matches[2]).$($Matches[3]).$build"
}

function Resolve-Tool([string]$given, [string]$command, [string[]]$fallbacks, [string]$label) {
    if ($given) { return $given }
    $cmd = Get-Command $command -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($f in $fallbacks) { if (Test-Path $f) { return $f } }
    throw "$label not found. Pass it explicitly or set the environment variable."
}

$Version = Get-ConfigValue "project.godot" "config/version"
$Numeric = ConvertTo-NumericVersion $Version
if ($Tag -and $Tag -ne "v$Version") {
    throw "Tag '$Tag' does not match project.godot config/version '$Version' (expected 'v$Version')"
}
$PresetVersion = Get-ConfigValue "export_presets.cfg" "application/product_version"
if ($PresetVersion -ne $Numeric) {
    throw "Windows preset product_version is '$PresetVersion' but config/version '$Version' needs '$Numeric'"
}
Write-Host "PixelLab Studio $Version ($Numeric)"

if (-not $SkipExport) {
    $Godot = Resolve-Tool $Godot "godot" @() "Godot (-Godot / `$env:GODOT_BIN)"
    if (Test-Path $ExportDir) { Remove-Item $ExportDir -Recurse -Force }
    New-Item -ItemType Directory -Force $ExportDir | Out-Null

    # Same flags as scripts/run_export_smoke.sh. The editor can exit non-zero
    # after a successful export (extension teardown), so success is judged by
    # the output files. Godot logs to stderr, which Windows PowerShell would
    # turn into a terminating error under "Stop".
    $ErrorActionPreference = "Continue"
    & $Godot --headless --recovery-mode --path $Root --export-release $PresetName (Join-Path $ExportDir $ExeName) 2>&1 |
        ForEach-Object { "$_" } | Where-Object { $_ -match "ERROR|WARNING: Project export" } |
        ForEach-Object { Write-Host "  godot: $_" }
    $ErrorActionPreference = "Stop"

    foreach ($required in @($ExeName, "PixelLab Studio.pck")) {
        if (-not (Test-Path (Join-Path $ExportDir $required))) { throw "Export failed: $required was not produced" }
    }
    # Without the Agility SDK the d3d12 driver falls back to Vulkan and window
    # transparency renders black (docs/architecture_guide.md).
    if (-not (Test-Path (Join-Path $ExportDir "x86_64\D3D12Core.dll"))) {
        throw "Export is missing x86_64\D3D12Core.dll. Put D3D12Core.x86_64.dll in the Godot export templates folder."
    }
}

if (Test-Path $OutDir) { Remove-Item $OutDir -Recurse -Force }
New-Item -ItemType Directory -Force $OutDir | Out-Null
$Base = "PixelLabStudio-v$Version-Windows-x64"
$Zip = Join-Path $OutDir "$Base.zip"
Compress-Archive -Path (Join-Path $ExportDir "*") -DestinationPath $Zip

$Iscc = Resolve-Tool $Iscc "iscc" @(
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) "Inno Setup ISCC (-Iscc / `$env:ISCC)"
& $Iscc /Q "/DAppVersion=$Version" "/DAppVersionNumeric=$Numeric" "/DSourceDir=$ExportDir" "/DOutputDir=$OutDir" (Join-Path $PSScriptRoot "PixelLabStudio.iss")
if ($LASTEXITCODE -ne 0) { throw "ISCC failed with exit code $LASTEXITCODE" }
$Setup = Join-Path $OutDir "$Base-Setup.exe"

$sums = foreach ($f in @($Setup, $Zip)) {
    "{0}  {1}" -f (Get-FileHash $f -Algorithm SHA256).Hash.ToLower(), (Split-Path $f -Leaf)
}
[IO.File]::WriteAllLines((Join-Path $OutDir "SHA256SUMS.txt"), $sums)

Write-Host ""
Write-Host "Built in $OutDir"
Get-ChildItem $OutDir -File | ForEach-Object { "  {0}  ({1:N1} MB)" -f $_.Name, ($_.Length / 1MB) }
