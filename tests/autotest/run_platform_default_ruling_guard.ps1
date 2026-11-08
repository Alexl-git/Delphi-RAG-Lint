<#
  run_platform_default_ruling_guard.ps1 -- owner ruling a3 (L-C20 / E-C20-DEFAULTS-RULING, lane 147 K5):
  the project file's current platform is DECISIVE; a project that names no platform (Delphi 7: no
  .dproj at all; Delphi 2007..XE: a .dproj without a recognised <Platform Condition=...> token) is Win32.
  The old engine resolved every platform-less index / cycles --fix run to Win64.

  Per fixture: `index --project <X> --db <own db>` from a neutral CWD with a private engine copy and
  its own drag-lint.json, then the Preprocess line's platform= and the stored fingerprint's plat=.
    xe      XE-era .dproj, no Platform element             -> Win32  (RED on 1.46: Win64)
    d2007   .dproj whose Platform token is AnyCPU          -> Win32  (RED on 1.46: Win64)
    d7      .dpr only, no .dproj                           -> Win32  (RED on 1.46: Win64)
    w32     .dproj active Platform Win32                   -> Win32  (RED on 1.46: Win64)
    w64     .dproj active Platform Win64                   -> Win64  (control: the dproj is read)
    w64arg  Win64 .dproj + --platform Win32                -> Win32  (control: an explicit arg wins)
  cycles --fix --format json echoes the platform it builds for: xe -> win32, w64 -> win64.
  Run from any CWD, pwsh 7. -Exe defaults to the worktree build, else the deployed engine.
#>
[CmdletBinding()]
param([string]$Exe = '')
$ErrorActionPreference = 'Stop'; $script:fail = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int][bool]$ok]); if(-not $ok){$script:fail=$true} }
function Write-Ascii([string]$Path,[string]$Body){ [IO.File]::WriteAllText($Path, ($Body -replace "`r?`n","`r`n"), [Text.Encoding]::ASCII) }
if (-not $Exe) {
  $Exe = Join-Path $PSScriptRoot '..\..\src\cli\Win64\Debug\drag-lint.exe'
  if (-not (Test-Path $Exe)) { $Exe = Join-Path $PSScriptRoot '..\..\third_party\dll-win64\drag-lint.exe' }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$exeSrc = (Resolve-Path $Exe).Path; $exeSrcDir = Split-Path -Parent $exeSrc
$root = Join-Path C:\TEMP "draglint_platruling_$PID"
$dprojXE = @'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <ProjectGuid>{6F1C2E1A-3B7D-4C55-9A0E-2D1F7A9B0C11}</ProjectGuid>
    <ProjectVersion>12.3</ProjectVersion>
    <MainSource>App.dpr</MainSource>
    <Config Condition="'$(Config)'==''">Debug</Config>
    <DCC_DCCCompiler>DCC32</DCC_DCCCompiler>
  </PropertyGroup>
</Project>
'@
$dproj2007 = @'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <ProjectGuid>{0B6C3D52-8E44-4E0F-B1A2-77C9D3E4F512}</ProjectGuid>
    <Configuration Condition=" '$(Configuration)' == '' ">Debug</Configuration>
    <Platform Condition=" '$(Platform)' == '' ">AnyCPU</Platform>
    <DCC_DCCCompiler>DCC32</DCC_DCCCompiler>
    <MainSource>App.dpr</MainSource>
  </PropertyGroup>
</Project>
'@
function DprojFor([string]$plat) { @"
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <MainSource>App.dpr</MainSource>
    <Config Condition="'`$(Config)'==''">Debug</Config>
    <Platform Condition="'`$(Platform)'==''">$plat</Platform>
  </PropertyGroup>
</Project>
"@ }
try {
  if (Test-Path $root) { [IO.Directory]::Delete($root, $true) }
  $eng = Join-Path $root 'eng'; $out = Join-Path $root 'out'
  New-Item -ItemType Directory -Path $eng,$out | Out-Null
  Copy-Item $exeSrc (Join-Path $eng 'drag-lint.exe') -Force
  Get-ChildItem $exeSrcDir -Filter '*.dll' | ForEach-Object { Copy-Item $_.FullName (Join-Path $eng $_.Name) -Force }
  if (Test-Path (Join-Path $exeSrcDir 'rules')) { Copy-Item (Join-Path $exeSrcDir 'rules') (Join-Path $eng 'rules') -Recurse -Force }
  $exe = Join-Path $eng 'drag-lint.exe'
  $o = $out.Replace('\','/')
  Write-Ascii (Join-Path $eng 'drag-lint.json') "{ `"settings`": { `"defaultPlatform`": `"Win32`", `"maxJobs`": 1 }, `"indexes`": { `"outDir`": `"$o`", `"sections`": [] } }"
  $cases = [ordered]@{
    xe     = @{ dproj = $dprojXE;           arg = '';      want = 'win32' }
    d2007  = @{ dproj = $dproj2007;         arg = '';      want = 'win32' }
    d7     = @{ dproj = $null;              arg = '';      want = 'win32' }
    w32    = @{ dproj = (DprojFor 'Win32'); arg = '';      want = 'win32' }
    w64    = @{ dproj = (DprojFor 'Win64'); arg = '';      want = 'win64' }
    w64arg = @{ dproj = (DprojFor 'Win64'); arg = 'Win32'; want = 'win32' }
  }
  $projOf = @{}
  Push-Location C:\TEMP
  try {
    foreach ($k in $cases.Keys) {
      $c = $cases[$k]; $app = Join-Path $root "app_$k"; New-Item -ItemType Directory -Path $app | Out-Null
      Write-Ascii (Join-Path $app 'App.dpr') "program App;`n`nuses`n  UMain in 'UMain.pas';`n`nbegin`nend.`n"
      Write-Ascii (Join-Path $app 'UMain.pas') "unit UMain;`n`ninterface`n`nprocedure Hello;`n`nimplementation`n`nprocedure Hello;`nbegin`nend;`n`nend.`n"
      $proj = Join-Path $app 'App.dpr'
      if ($null -ne $c.dproj) { Write-Ascii (Join-Path $app 'App.dproj') $c.dproj; $proj = Join-Path $app 'App.dproj' }
      $projOf[$k] = $proj
      $db = Join-Path $out "$k.sqlite"
      $argv = @('index', '--project', $proj, '--db', $db)
      if ($c.arg) { $argv += @('--platform', $c.arg) }
      $txt = (& $exe @argv 2>&1 | Out-String)
      $pp = [regex]::Match($txt, 'Preprocess: ON[^\r\n]*platform=([A-Za-z0-9]+)').Groups[1].Value.ToLowerInvariant()
      $fpRow = (& $exe sql --query "select value from schema_meta where key='indexer_fingerprint'" --db $db 2>&1 | Out-String)
      $fp = [regex]::Match($fpRow, 'plat=([A-Za-z0-9]*)').Groups[1].Value.ToLowerInvariant()
      Check "$k index Preprocess platform = $($c.want)" ($pp -eq $c.want) "(got '$pp')"
      Check "$k fingerprint plat = $($c.want)"          ($fp -eq $c.want) "(got '$fp')"
    }
    # index --all: a manifest project section names no platform -> the section's .dproj decides.
    foreach ($k in 'xe','w32','w64') {
      $sec = "Sec_$k"; $secDb = Join-Path $out "sec_$k.sqlite"
      Write-Ascii (Join-Path $eng 'drag-lint.json') "{ `"settings`": { `"defaultPlatform`": `"Win32`", `"maxJobs`": 1 }, `"indexes`": { `"outDir`": `"$o`", `"sections`": [ { `"name`": `"$sec`", `"db`": `"sec_$k.sqlite`", `"include`": [`"$($projOf[$k].Replace('\','/'))`"] } ] } }"
      & $exe index --all --only $sec 2>&1 | Out-Null
      $fpRow = (& $exe sql --query "select value from schema_meta where key='indexer_fingerprint'" --db $secDb 2>&1 | Out-String)
      $fp = [regex]::Match($fpRow, 'plat=([A-Za-z0-9]*)').Groups[1].Value.ToLowerInvariant()
      Check "$k index --all section fingerprint plat = $($cases[$k].want)" ($fp -eq $cases[$k].want) "(got '$fp')"
    }
    foreach ($k in 'xe','w64') {
      $db = Join-Path $out "$k.sqlite"
      $txt = (& $exe cycles --fix --project $projOf[$k] --db $db --format json 2>&1 | Out-String)
      $m = [regex]::Match($txt, '"platform"\s*:\s*"([^"]*)"')
      Check "$k cycles --fix JSON platform = $($cases[$k].want)" ($m.Success -and $m.Groups[1].Value -eq $cases[$k].want) "(got '$($m.Groups[1].Value)')"
    }
  } finally { Pop-Location }
} finally {
  if (Test-Path $root) { try { [IO.Directory]::Delete($root, $true) } catch { Write-Host "note: could not delete $root" } }
}
if ($script:fail) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS' -ForegroundColor Green
