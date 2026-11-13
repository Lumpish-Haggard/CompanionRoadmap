<#
.SYNOPSIS
    Builds CompanionRoadmap.pak (and a Nexus-ready zip) with LSLib's Divine.exe.

.DESCRIPTION
    1. Validates meta.lsx, Config.json and MCM_blueprint.json.
    2. Optionally re-validates the roadmap data against the game (tools/build_data.py).
    3. Stages ONLY Mods/CompanionRoadmap into build/pak (README, tools and caches never
       end up inside the pak) and packs it with Divine.exe.
    4. Lists the package to verify the expected files are inside.
    5. Writes dist/CompanionRoadmap.pak, dist/info.json and dist/CompanionRoadmap-<version>.zip
       (the zip is what you upload to Nexus; BG3 Mod Manager and Vortex both import it).

.PARAMETER DivinePath
    Path to Divine.exe. Auto-detected from PATH, ./tools, LSLib/ExportTool folders and Vortex.

.PARAMETER OutputDir
    Output folder (default: ./dist).

.PARAMETER Install
    Also copy the .pak into %LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Mods.
    You still need to enable it in BG3 Mod Manager / Vortex.

.PARAMETER SkipDataCheck
    Do not run tools/build_data.py --check-only before packing.

.EXAMPLE
    .\pack.ps1
    .\pack.ps1 -DivinePath "C:\Tools\ExportTool\tools\Divine.exe" -Install
#>
[CmdletBinding()]
param(
    [string]$DivinePath = "",
    [string]$OutputDir = "",
    [switch]$Install,
    [switch]$SkipDataCheck
)

$ErrorActionPreference = "Stop"
$ModName = "CompanionRoadmap"
$Root = $PSScriptRoot
$ModDir = Join-Path $Root "Mods\$ModName"
if (-not $OutputDir) { $OutputDir = Join-Path $Root "dist" }
$BuildDir = Join-Path $Root "build\pak"

function Fail([string]$Message) {
    Write-Host "ERROR: $Message" -ForegroundColor Red
    exit 1
}

Write-Host "== Companion & Romance Roadmap packager ==" -ForegroundColor Cyan

# ----------------------------------------------------------------- 1. validate
$MetaPath = Join-Path $ModDir "meta.lsx"
if (-not (Test-Path $MetaPath)) { Fail "meta.lsx not found at $MetaPath" }
try { [xml]$meta = Get-Content -Raw -Encoding UTF8 $MetaPath } catch { Fail "meta.lsx is not valid XML: $_" }

$info = @{}
foreach ($attr in $meta.save.region.node.children.node | Where-Object { $_.id -eq "ModuleInfo" } | ForEach-Object { $_.attribute }) {
    $info[$attr.id] = $attr.value
}
if ($info["Folder"] -ne $ModName) { Fail "meta.lsx Folder is '$($info["Folder"])', expected '$ModName'" }
[long]$v64 = $info["Version64"]
$major = $v64 -shr 55
$minor = ($v64 -shr 47) -band 0xFF
$revision = ($v64 -shr 31) -band 0xFFFF
$build = $v64 -band 0x7FFFFFFF
$Version = "$major.$minor.$revision.$build"
Write-Host "Mod: $($info["Name"]) v$Version  UUID $($info["UUID"])"

foreach ($json in @("ScriptExtender\Config.json", "MCM_blueprint.json")) {
    $p = Join-Path $ModDir $json
    if (-not (Test-Path $p)) { Fail "$json is missing" }
    try { Get-Content -Raw -Encoding UTF8 $p | ConvertFrom-Json | Out-Null } catch { Fail "$json is not valid JSON: $_" }
}
$cfg = Get-Content -Raw -Encoding UTF8 (Join-Path $ModDir "ScriptExtender\Config.json") | ConvertFrom-Json
if ($cfg.ModTable -ne $ModName) { Fail "Config.json ModTable must be '$ModName'" }
if (-not ($cfg.FeatureFlags -contains "Lua")) { Fail "Config.json must enable the 'Lua' feature flag" }

# ------------------------------------------------------- 2. data check (optional)
if (-not $SkipDataCheck) {
    $py = Get-Command py -ErrorAction SilentlyContinue
    if (-not $py) { $py = Get-Command python -ErrorAction SilentlyContinue }
    $cache = Join-Path $Root "tools\.cache\flags.tsv"
    if ($py -and (Test-Path $cache)) {
        Write-Host "Validating roadmap data against the game cache..." -ForegroundColor DarkGray
        & $py.Source (Join-Path $Root "tools\build_data.py") --check-only
        if ($LASTEXITCODE -ne 0) { Fail "Data validation failed (see above). Fix it or pass -SkipDataCheck." }
    } else {
        Write-Host "Skipping data validation (needs Python and tools\.cache from tools\extract_game_data.py)." -ForegroundColor DarkGray
    }
}

# ------------------------------------------------------------- 3. find Divine
$candidates = @()
if ($DivinePath) { $candidates += $DivinePath }
$onPath = Get-Command Divine.exe -ErrorAction SilentlyContinue
if ($onPath) { $candidates += $onPath.Source }
$candidates += (Join-Path $Root "Divine.exe"), (Join-Path $Root "tools\Divine.exe")
$patterns = @(
    "$env:LOCALAPPDATA\Programs\LSLib\Divine.exe",
    "$env:APPDATA\Vortex\baldursgate3\mods\ExportTool*\tools\Divine.exe"
)
foreach ($drive in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
    $r = $drive.Root
    $patterns += "${r}Tools\LSLib\Divine.exe", "${r}Tools\ExportTool*\Tools\Divine.exe",
        "${r}Modding\ExportTool*\Tools\Divine.exe", "${r}Vortex Mods\baldursgate3\ExportTool*\tools\Divine.exe"
}
foreach ($pattern in $patterns) {
    try { $candidates += (Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) } catch { }
}
$Divine = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $Divine) {
    Write-Host "Divine.exe (LSLib) was not found." -ForegroundColor Yellow
    Write-Host "Download ExportTool from https://github.com/Norbyte/lslib/releases and pass -DivinePath <path>\Tools\Divine.exe"
    exit 1
}
Write-Host "Divine: $Divine" -ForegroundColor Green

# --------------------------------------------------------------- 4. stage+pack
if (Test-Path $BuildDir) { Remove-Item -Recurse -Force $BuildDir }
$stageMod = Join-Path $BuildDir "Mods\$ModName"
New-Item -ItemType Directory -Force -Path (Split-Path $stageMod) | Out-Null
Copy-Item -Recurse -Path $ModDir -Destination $stageMod

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$PakPath = Join-Path $OutputDir "$ModName.pak"
if (Test-Path $PakPath) { Remove-Item -Force $PakPath }

Write-Host "Packing..." -ForegroundColor Cyan
& $Divine -g bg3 -a create-package -s $BuildDir -d $PakPath -l warn
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $PakPath)) { Fail "Divine failed with exit code $LASTEXITCODE" }

# ------------------------------------------------------------------- 5. verify
$listing = & $Divine -g bg3 -a list-package -s $PakPath -l warn
$required = @(
    "Mods/$ModName/meta.lsx",
    "Mods/$ModName/MCM_blueprint.json",
    "Mods/$ModName/ScriptExtender/Config.json",
    "Mods/$ModName/ScriptExtender/Lua/BootstrapServer.lua",
    "Mods/$ModName/ScriptExtender/Lua/BootstrapClient.lua",
    "Mods/$ModName/ScriptExtender/Lua/Data/Flags.lua"
)
foreach ($file in $required) {
    if (-not ($listing | Select-String -SimpleMatch $file)) { Fail "Package is missing $file" }
}
$stray = $listing | Where-Object { $_ -and ($_ -notmatch "^Mods/$ModName/") }
if ($stray) { Fail "Package contains files outside Mods/$ModName/: $($stray -join ', ')" }
$fileCount = ($listing | Where-Object { $_ }).Count
Write-Host "Package verified ($fileCount files)." -ForegroundColor Green

# --------------------------------------------------------- 6. info.json + zip
$md5 = (Get-FileHash -Algorithm MD5 $PakPath).Hash.ToLowerInvariant()
$infoJson = [ordered]@{
    Mods = @([ordered]@{
        Author = $info["Author"]
        Name = $info["Name"]
        Folder = $info["Folder"]
        Version = "$v64"
        Description = $info["Description"]
        UUID = $info["UUID"]
        Created = (Get-Date).ToString("o")
        Dependencies = @()
        Group = $info["UUID"]
    })
    MD5 = $md5
}
$InfoPath = Join-Path $OutputDir "info.json"
[System.IO.File]::WriteAllText($InfoPath, ($infoJson | ConvertTo-Json -Depth 5 -Compress), (New-Object System.Text.UTF8Encoding($false)))

$ZipPath = Join-Path $OutputDir "$ModName-$Version.zip"
if (Test-Path $ZipPath) { Remove-Item -Force $ZipPath }
Compress-Archive -Path $PakPath, $InfoPath -DestinationPath $ZipPath

Remove-Item -Recurse -Force (Join-Path $Root "build")

$size = [Math]::Round((Get-Item $PakPath).Length / 1KB, 1)
Write-Host ""
Write-Host "Built $PakPath ($size KB)" -ForegroundColor Green
Write-Host "Built $ZipPath (upload this to Nexus)" -ForegroundColor Green

# ----------------------------------------------------------------- 7. install
if ($Install) {
    $modsFolder = Join-Path $env:LOCALAPPDATA "Larian Studios\Baldur's Gate 3\Mods"
    New-Item -ItemType Directory -Force -Path $modsFolder | Out-Null
    Copy-Item -Force $PakPath $modsFolder
    Write-Host "Copied to $modsFolder - enable it in BG3 Mod Manager or Vortex." -ForegroundColor Green
}
