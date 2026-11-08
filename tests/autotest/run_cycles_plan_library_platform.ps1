# run_cycles_plan_library_platform.ps1 -- lane 148 CY (fabcyc D4/D5): `cycles --plan` and
# `cycles --causes --format json` without --library-db open the platform library of the platform the
# --fix build uses (K5 ruling a3: --platform, else the --project's active platform, else Win32), not a
# fixed win64.
#
# The engine runs from a private copy with its OWN drag-lint.json: one registry-libraries section whose
# outDir holds two stand-in libraries, library-Win32.sqlite and library-Win64.sqlite (copies of the
# fixture's own index: any readable store opens). The stderr note "reads class ancestry from <path>"
# names the one that was opened.
#
#   w1  Win32 .dproj, --plan            -> library-Win32   (RED on 1.46.0: library-Win64)
#   w2  Win32 .dproj, --causes json     -> library-Win32   (RED on 1.46.0: library-Win64)
#   pc1 Win64 .dproj, --plan            -> library-Win64   (positive control: the platform is read, not fixed)
#   pc2 Win32 .dproj, --platform win64  -> library-Win64   (an explicit --platform still wins)
#   pc3 --library-db <file> named       -> that file, neither stand-in
#
# Usage: pwsh -File run_cycles_plan_library_platform.ps1 [-Exe <drag-lint.exe>] [-WorkDir <dir>] [-KeepWorkDir]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-cycles-plan-libplat-$PID",
  [switch]$KeepWorkDir
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Fx  = Join-Path $PSScriptRoot '..\fixtures\cyclefix\leafmerge'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail) {
  if ($Ok) { Write-Host "  [PASS] $Name" -ForegroundColor Green }
  else { Write-Host "  [FAIL] $Name -- $Detail" -ForegroundColor Red; $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text, [Text.Encoding]::ASCII) }

function New-Project([string]$Tag, [string]$Platform) {
  $d = Join-Path $WorkDir $Tag
  New-Item -ItemType Directory -Force $d | Out-Null
  Get-ChildItem $Fx -File | ForEach-Object { Copy-Item $_.FullName (Join-Path $d $_.Name) }
  $p = Join-Path $d 'LeafMerge.dproj'
  $x = [IO.File]::ReadAllText($p) -replace "(<Platform Condition=`"'\`$\(Platform\)'==''`">)Win\d\d(</Platform>)", "`${1}$Platform`${2}"
  Write-Ascii $p $x
  return $p
}

function Invoke-Plan([string]$Dproj, [string]$Db, [string[]]$Extra) {
  $err = Join-Path $WorkDir ('err-' + [guid]::NewGuid().ToString('N') + '.txt')
  $out = Join-Path $WorkDir ('out-' + [guid]::NewGuid().ToString('N') + '.txt')
  $a = @('cycles', '--db', $Db, '--project', $Dproj) + $Extra
  $p = Start-Process -FilePath $EngExe -ArgumentList $a -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
    -RedirectStandardOutput $out -RedirectStandardError $err
  return @{ Exit = $p.ExitCode; Err = [IO.File]::ReadAllText($err); Out = [IO.File]::ReadAllText($out) }
}

function Lib-Of([string]$ErrText) {
  $m = [regex]::Match($ErrText, 'reads class ancestry from (\S+)')
  if ($m.Success) { return $m.Groups[1].Value } else { return '' }
}

try {
  New-Item -ItemType Directory -Force $WorkDir | Out-Null
  $eng = Join-Path $WorkDir 'engine'; New-Item -ItemType Directory -Force $eng | Out-Null
  $src = Split-Path $Exe
  Copy-Item $Exe (Join-Path $eng 'drag-lint.exe')
  Get-ChildItem $src -Filter '*.dll' | ForEach-Object { Copy-Item $_.FullName (Join-Path $eng $_.Name) }
  if (Test-Path (Join-Path $src 'rules')) { Copy-Item (Join-Path $src 'rules') (Join-Path $eng 'rules') -Recurse }
  $EngExe = Join-Path $eng 'drag-lint.exe'
  $libs = Join-Path $WorkDir 'libs'; New-Item -ItemType Directory -Force $libs | Out-Null
  $o = $libs.Replace('\', '/')
  Write-Ascii (Join-Path $eng 'drag-lint.json') ("{ `"settings`": { `"defaultPlatform`": `"Win32`", `"maxJobs`": 1 }, `"indexes`": { `"outDir`": `"$o`", " +
    "`"sections`": [ { `"name`": `"Library`", `"db`": `"library-{platform}.sqlite`", `"source`": `"registry-libraries`", `"platforms`": [`"Win32`", `"Win64`"] } ] } }")

  $p32 = New-Project 'w32' 'Win32'
  $p64 = New-Project 'w64' 'Win64'
  $db32 = Join-Path $WorkDir 'w32.sqlite'; $db64 = Join-Path $WorkDir 'w64.sqlite'
  & $EngExe index --project $p32 --db $db32 *> (Join-Path $WorkDir 'index-w32.log')
  & $EngExe index --project $p64 --db $db64 *> (Join-Path $WorkDir 'index-w64.log')
  if (-not (Test-Path $db32) -or -not (Test-Path $db64)) { Write-Host 'FATAL: fixture index failed' -ForegroundColor Red; exit 2 }
  $L32 = Join-Path $libs 'library-Win32.sqlite'; $L64 = Join-Path $libs 'library-Win64.sqlite'
  Copy-Item $db32 $L32; Copy-Item $db32 $L64
  $named = Join-Path $WorkDir 'named-lib.sqlite'; Copy-Item $db32 $named

  Write-Host '== --plan / --causes without --library-db read the build platform''s library' -ForegroundColor Cyan
  $r = Invoke-Plan $p32 $db32 @('--plan')
  $l = Lib-Of $r.Err
  Check 'w1 Win32 project, --plan: library-Win32' ($l -like '*library-Win32.sqlite') "opened [$l] exit=$($r.Exit) err=[$($r.Err.Trim())]"
  $r = Invoke-Plan $p32 $db32 @('--causes', '--format', 'json')
  $l = Lib-Of $r.Err
  Check 'w2 Win32 project, --causes --format json: library-Win32' ($l -like '*library-Win32.sqlite') "opened [$l] exit=$($r.Exit) err=[$($r.Err.Trim())]"

  Write-Host '== positive controls' -ForegroundColor Cyan
  $r = Invoke-Plan $p64 $db64 @('--plan')
  $l = Lib-Of $r.Err
  Check 'pc1 Win64 project, --plan: library-Win64' ($l -like '*library-Win64.sqlite') "opened [$l] exit=$($r.Exit)"
  $r = Invoke-Plan $p32 $db32 @('--plan', '--platform', 'win64')
  $l = Lib-Of $r.Err
  Check 'pc2 --platform win64 on a Win32 project: library-Win64' ($l -like '*library-Win64.sqlite') "opened [$l] exit=$($r.Exit)"
  $r = Invoke-Plan $p32 $db32 @('--plan', '--library-db', $named)
  $l = Lib-Of $r.Err
  Check 'pc3 a named --library-db wins' ($l -like '*named-lib.sqlite') "opened [$l] exit=$($r.Exit)"
} finally {
  if (-not $KeepWorkDir) {
    for ($i = 0; ($i -lt 10) -and (Test-Path -LiteralPath $WorkDir); $i++) {
      try { [IO.Directory]::Delete($WorkDir, $true) } catch { Start-Sleep -Seconds 1 }
    }
  }
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
