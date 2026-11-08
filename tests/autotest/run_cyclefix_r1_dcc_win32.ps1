<#
  run_cyclefix_r1_dcc_win32.ps1 -- 148 MF (K5 live proof): `cycles --fix` on a REAL Win32 project.
  Needs RAD Studio (msbuild via rsvars; Platform=Win32 is dcc32). SKIPs (exit 0) without it.

  Tree: tests\fixtures\cyclefix\r1extend (its .dproj targets Win32 and Win64; Win32 is forced by --platform
  win32 AND by the build below). Steps:
    1 the untouched copy builds for Win32 (msbuild /p:Platform=Win32) and the exe is a 32-bit PE (machine 0x014C)
    2 PLATFORM ECHO: `cycles --fix --format json` (dry run) says "platform":"win32"
    3 `cycles --fix --apply --platform win32` (its own compile gate = a Win32 build) exits 0
    4 the followed copy builds for Win32 again (BUILD_EXITCODE=0, no `error E` / `fatal F`)
    5 its stdout is byte-identical to the untouched Win32 build's
  POSITIVE CONTROLS: pc1 the same dry run with --platform win64 echoes "win64" (the echo follows the flag, it is
  not a constant); pc2 the PE check is a 32-bit test that a Win64 build of the same tree FAILS (machine 0x8664);
  The byte compare's own teeth (a broken inversion differs) live in run_cyclefix_r1_dcc.ps1.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-cyclefix-r1-dcc-win32-$PID"
)
$ErrorActionPreference = 'Stop'
$RsVars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
if (-not (Test-Path $RsVars)) { Write-Host 'SKIP: RAD Studio not installed' -ForegroundColor Yellow; exit 0 }
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe   = (Resolve-Path $Exe).Path
$Repo  = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Src   = Join-Path $Repo 'tests\fixtures\cyclefix\r1extend'
$Ascii = [Text.Encoding]::ASCII

function Copy-Tree([string]$From, [string]$To) {
  New-Item -ItemType Directory -Force $To | Out-Null
  Get-ChildItem $From -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $To $_.Name) -Force }
}

# msbuild of pDproj for pPlatform (Win32 / Win64); returns @{ Ok; Errors }.
function Invoke-Build([string]$Dproj, [string]$Platform) {
  $dir = Split-Path $Dproj
  $bat = Join-Path $WorkDir ('build-' + (Split-Path $dir -Leaf) + '-' + $Platform + '.bat')
  $log = "$bat.log"
  $lines = @('@echo off', ('call "{0}"' -f $RsVars), ('cd /d "{0}"' -f $dir),
    ('msbuild /t:Build /p:Config=Debug /p:Platform={2} /v:minimal "{0}" > "{1}" 2>&1' -f $Dproj, $log, $Platform),
    ('>> "{0}" echo BUILD_EXITCODE=%ERRORLEVEL%' -f $log))
  [IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), $Ascii)
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -NoNewWindow -Wait | Out-Null
  $text = if (Test-Path $log) { [IO.File]::ReadAllText($log) } else { '' }
  $errors = @([regex]::Matches($text, '(?m)^.*\b(error|fatal) [EF]\d{4}\b.*$') | ForEach-Object { $_.Value.Trim() } | Select-Object -Unique)
  return @{ Ok = ($text -match 'BUILD_EXITCODE=0') -and ($errors.Count -eq 0); Errors = ($errors -join ' | ') }
}

function Get-ExePath([string]$Dproj, [string]$Platform) {
  return Join-Path (Split-Path $Dproj) ("$Platform\Debug\" + [IO.Path]::GetFileNameWithoutExtension($Dproj) + '.exe')
}

# PE COFF Machine field: 0x014C = i386 (Win32), 0x8664 = x64; 0 when no exe.
function Get-PeMachine([string]$ExePath) {
  if (-not (Test-Path $ExePath)) { return 0 }
  $b = [IO.File]::ReadAllBytes($ExePath)
  $pe = [BitConverter]::ToInt32($b, 0x3C)
  return [int][BitConverter]::ToUInt16($b, $pe + 4)
}

function Invoke-Program([string]$ExePath) {
  if (-not (Test-Path $ExePath)) { return '<no exe>' }
  $o = "$ExePath.stdout"
  Start-Process -FilePath $ExePath -WorkingDirectory (Split-Path $ExePath) -NoNewWindow -Wait `
    -RedirectStandardOutput $o -RedirectStandardError "$ExePath.stderr" | Out-Null
  return [Convert]::ToBase64String([IO.File]::ReadAllBytes($o))
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  $base = Join-Path $WorkDir 'base'; $edit = Join-Path $WorkDir 'edit'
  Copy-Tree $Src $base; Copy-Tree $Src $edit
  $bd = Join-Path $base 'R1Extend.dproj'; $ed = Join-Path $edit 'R1Extend.dproj'

  Write-Host '== untouched copy, Win32' -ForegroundColor Cyan
  $b0 = Invoke-Build $bd 'Win32'
  Check '1a the untouched copy builds for Win32' $b0.Ok $b0.Errors
  $m32 = Get-PeMachine (Get-ExePath $bd 'Win32')
  Check '1b its exe is a 32-bit PE (machine 0x014C)' ($m32 -eq 0x014C) ('machine=0x{0:X}' -f $m32)
  $out0 = Invoke-Program (Get-ExePath $bd 'Win32')

  Write-Host '== pc2: the PE check has teeth (Win64 build of the same tree)' -ForegroundColor Cyan
  $b64 = Invoke-Build $bd 'Win64'
  $m64 = Get-PeMachine (Get-ExePath $bd 'Win64')
  Check 'pc2 a Win64 build is NOT machine 0x014C' ($b64.Ok -and ($m64 -eq 0x8664)) ('machine=0x{0:X}' -f $m64)

  Write-Host '== platform echo' -ForegroundColor Cyan
  $db = Join-Path $WorkDir 'edit.sqlite'
  & $Exe index --project $ed --db $db *> (Join-Path $WorkDir 'index.log')
  foreach ($pl in 'win32', 'win64') {
    $o = Join-Path $WorkDir "dry-$pl.json"
    $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
      -ArgumentList @('cycles', '--db', ('"' + $db + '"'), '--fix', '--project', ('"' + $ed + '"'), '--platform', $pl, '--library-db', 'none', '--format', 'json') `
      -RedirectStandardOutput $o -RedirectStandardError (Join-Path $WorkDir "dry-$pl.err")
    $j = $null; try { $j = [IO.File]::ReadAllText($o) | ConvertFrom-Json } catch { }
    $tag = if ($pl -eq 'win32') { '2' } else { 'pc1' }
    Check "$tag dry run --platform $pl echoes platform=$pl" (($p.ExitCode -eq 0) -and ($null -ne $j) -and ($j.platform -ceq $pl)) "exit=$($p.ExitCode) platform=$($j.platform)"
  }

  Write-Host '== apply on Win32' -ForegroundColor Cyan
  $ao = Join-Path $WorkDir 'apply.out'
  $ap = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
    -ArgumentList @('cycles', '--fix', '--apply', '--no-backup', '--build-timeout', '600', '--cycle', '1', '--platform', 'win32',
      '--project', ('"' + $ed + '"'), '--db', ('"' + $db + '"'), '--library-db', 'none') `
    -RedirectStandardOutput $ao -RedirectStandardError (Join-Path $WorkDir 'apply.err')
  Check '3 cycles --fix --apply --platform win32 exits 0' ($ap.ExitCode -eq 0) ("exit=$($ap.ExitCode) " + ([IO.File]::ReadAllText($ao) -replace "`r?`n", ' | ').Substring(0, [Math]::Min(300, [IO.File]::ReadAllText($ao).Length)))
  $changed = @(Get-ChildItem $edit -File -Filter *.pas | Where-Object { [IO.File]::ReadAllText($_.FullName) -cne [IO.File]::ReadAllText((Join-Path $base $_.Name)) })
  Check '3b the apply really edited source (>= 1 .pas differs from the untouched copy; else step 5 is vacuous)' ($changed.Count -ge 1) ($changed.Name -join ',')
  $b1 = Invoke-Build $ed 'Win32'
  Check '4 the followed copy builds for Win32 (BUILD_EXITCODE=0, no error E / fatal F)' $b1.Ok $b1.Errors
  Check '4b it is a 32-bit PE' ((Get-PeMachine (Get-ExePath $ed 'Win32')) -eq 0x014C) ''
  $out1 = Invoke-Program (Get-ExePath $ed 'Win32')
  Check '5 its stdout is byte-identical to the untouched Win32 build''s' (($out0 -ne '<no exe>') -and ($out1 -ceq $out0)) ''
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }