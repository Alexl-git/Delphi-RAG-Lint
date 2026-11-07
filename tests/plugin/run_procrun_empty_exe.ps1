<#
  run_procrun_empty_exe.ps1 -- O-PLUGIN-EMPTY-EXE: no engine resolved means nothing is spawned.

  Builds and runs ProcRunEmptyExeTests.dpr (the runner every site passes through), then
  source-anchors the sites that do NOT pass through it: each direct CreateProcess of an engine
  command and each .bat builder must refuse an empty exe first, with the shared report.
  A live IDE with no engine beside the BPL is the owed proof.

  RED BASELINE, measured 2026-11-06 on the pre-fix tree: cases 1a/1b/2 fail (exit -1 and an EMPTY
  output) and the source anchors fail.

  Usage: pwsh -File tests\plugin\run_procrun_empty_exe.ps1 [-SrcDir <older src\delphi-plugin>]
#>
[CmdletBinding()]
param(
  [string]$Dpr     = "$PSScriptRoot\..\ProcRunEmptyExeTests.dpr",
  [string]$WorkDir = "$env:TEMP\drag-lint-procrun-emptyexe-build-$PID",
  [string]$SrcDir = "$PSScriptRoot\..\..\src\delphi-plugin"
)
try {
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Dpr)) { Write-Host "FATAL: dpr not found: $Dpr" -ForegroundColor Red; exit 2 }
$Dpr     = (Resolve-Path $Dpr).Path
$DprDir  = Split-Path $Dpr -Parent
$DprName = Split-Path $Dpr -Leaf

$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
if (-not (Test-Path $rs)) { Write-Host "FATAL: rsvars not found: $rs" -ForegroundColor Red; exit 2 }

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$DcuDir = Join-Path $WorkDir 'dcu'
New-Item -ItemType Directory $DcuDir | Out-Null

# dcc64 refuses to create output into a directory that does not exist (F2039),
# hence both are made above rather than relying on the compiler to do it.
$bat = Join-Path $WorkDir 'build.bat'
$lines = @(
  '@echo off',
  ('call "{0}"' -f $rs),
  ('cd /d "{0}"' -f $DprDir),
  ('dcc64 -B -E"{0}" -N0"{1}" {2}' -f $WorkDir, $DcuDir, $DprName),
  'echo BUILD_EXITCODE=%ERRORLEVEL%'
)
[System.IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), [System.Text.Encoding]::ASCII)

$buildLog = Join-Path $WorkDir 'build.log'
$p = Start-Process cmd.exe -ArgumentList "/c","`"$bat`"" `
       -RedirectStandardOutput $buildLog -RedirectStandardError "$buildLog.err" `
       -NoNewWindow -Wait -PassThru
$buildOut = Get-Content $buildLog -Raw
if ($buildOut -notmatch 'BUILD_EXITCODE=0') {
  Write-Host 'FATAL: compile failed' -ForegroundColor Red
  Write-Host $buildOut
  exit 2
}

$exe = Join-Path $WorkDir ([System.IO.Path]::GetFileNameWithoutExtension($DprName) + '.exe')
if (-not (Test-Path $exe)) { Write-Host "FATAL: exe not produced: $exe" -ForegroundColor Red; exit 2 }

$out = & $exe 2>&1 | Out-String
$rc  = $LASTEXITCODE
Write-Host $out.TrimEnd()

# Sites outside the runner. Each row: unit, a regex that pins the refusal in front of the spawn.
$sites = @(
  @('DragLint.Plugin.Editor.pas',         'FullCompileSweep',  '(?s)ExePath:= DLExe64;\s+if not DLEngineFound\(ExePath\) then Exit;\s+TThread\.CreateAnonymousThread\(\s+procedure\s+var\s+CmdLine\s*:\s*string\s*;\s+CmdLineW'),
  @('DragLint.Plugin.Editor.pas',         'ghost lint',        '(?s)ExePath:= DLExe64;\s+if not DLEngineFound\(ExePath\) then Exit;\s+\{ Spawn detached: drag-lint lint'),
  @('DragLint.Plugin.Editor.pas',         'YADF project bat',  '(?s)if not DLEngineFound\(DLExe64\) then Exit;\s+Bat:= ''@echo off''#13#10;\s+for i:= 0 to High\(Units\)'),
  @('DragLint.Plugin.Editor.pas',         'auto-document bat', '(?s)if not DLEngineFound\(DLExe64\) then Exit;\s+Bat:=\s+''@echo off''#13#10 \+\s+Format\(''"%s" index'),
  @('DragLint.Plugin.ProjectNotifier.pas','SpawnIndexer (its one caller)', '(?s)if ExePath = '''' then Exit;.{0,1500}?SpawnIndexer\(ExePath, FileName, DbPath\)'),
  @('DragLint.Plugin.StructureCache.pas', 'outline spawn',     '(?s)if IsEmptyExeCommand\(ACmdLine\) then\s+begin\s+ReportEngineMissing;\s+Exit;\s+end;.{0,1200}?CreateProcessW')
)
foreach ($s in $sites) {
  $text = [IO.File]::ReadAllText((Join-Path $SrcDir $s[0]))
  $ok = $text -match $s[2]
  Write-Host ("  [{0}] source anchor: {1} refuses an empty exe" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $s[1])
  if (-not $ok) { $rc = 1 }
}
# Positive control: the anchor machinery fails on a synthetic site with no refusal.
$synth = "ExePath:= DLExe64;`r`n  { Spawn detached: drag-lint lint"
if ($synth -match $sites[1][2]) { Write-Host '  [FAIL] positive control: anchor matched a site with no refusal'; $rc = 1 }
else { Write-Host '  [PASS] positive control: anchor rejects a site with no refusal' }
# Every CreateProcess in the plugin is on this list, so a new direct spawn has to be looked at here.
$known = 'Editor=2 GraphWindow=1 LiveDiagnostics=1 LspClient=1 ProcRun=1 ProjectNotifier=2 StructureCache=1'
$seen = @()
foreach ($f in (Get-ChildItem $SrcDir -Filter 'DragLint.Plugin.*.pas' | Sort-Object Name)) {
  $n = ([regex]::Matches([IO.File]::ReadAllText($f.FullName), '(?m)^(?!\s*(///|\{)).*\bCreateProcess[W]?\(')).Count
  if ($n -gt 0) { $seen += ('{0}={1}' -f ($f.BaseName -replace '^DragLint\.Plugin\.',''), $n) }
}
$seenText = $seen -join ' '
$okList = $seenText -eq $known
Write-Host ("  [{0}] the direct CreateProcess sites are the reviewed list: {1}" -f $(if ($okList) { 'PASS' } else { 'FAIL' }), $seenText)
if (-not $okList) { $rc = 1 }

if ($rc -ne 0) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
if ($out -notmatch '(\d+) passed, 0 failed') {
  # A run that printed nothing would otherwise sail through on exit 0.
  Write-Host 'FAIL: no pass/fail summary in output' -ForegroundColor Red; exit 1
}
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  foreach ($d23 in @("$env:TEMP\drag-lint-procrun-emptyexe-build-$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
