<#
  run_plugin_reference_db.ps1 -- the IDE plugin's optional reference index is read from
  %APPDATA%\drag-lint\drag-lint-plugin.ini ([Databases] ReferenceDb / ReferenceDbFor); no private
  path or project name is compiled into the resolver.

  1. Builds and runs tests\ReferenceDbTests.dpr over src\delphi-plugin\DragLint.Plugin.ReferenceDb.pas
     (its own positive control is cases 1a / 2a / 2b: a unit that always answers '' fails them).
  2. Source anchors: the resolver asks the unit, the package contains it, and no string literal in
     src\delphi-plugin names a C:\Projects path or a private project.

  RED BASELINE, measured 2026-11-24 (lane v154-relplug, base 38a14def9): stub unit 14 passed / 3
  failed (1a 2a 2b); all four anchors failed.

  Usage: pwsh -File tests\plugin\run_plugin_reference_db.ps1 [-SrcDir <src\delphi-plugin>]
#>
[CmdletBinding()]
param(
  [string]$SrcDir  = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-referencedb-build-$PID"
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $SrcDir) { $SrcDir = "$PSScriptRoot\..\..\src\delphi-plugin" }
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  Write-Host ("  [{0}] {1} {2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $n, $d)
  if (-not $ok) { $script:Failed = $true }
}

$SrcDir = (Resolve-Path $SrcDir).Path
$Repo   = (Resolve-Path "$PSScriptRoot\..\..").Path
$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
if (-not (Test-Path $rs)) { Write-Host "FATAL: rsvars not found: $rs" -ForegroundColor Red; exit 2 }
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
[void][IO.Directory]::CreateDirectory("$WorkDir\dcu")

Write-Host '== 1. the unit =='
$bat = "$WorkDir\build.bat"
$lines = @('@echo off', ('call "{0}"' -f $rs), ('cd /d "{0}"' -f "$Repo\tests"),
           ('dcc64 -B -Q -E"{0}" -N0"{0}\dcu" -U"{1}" ReferenceDbTests.dpr' -f $WorkDir, $SrcDir),
           'echo BUILD_EXITCODE=%ERRORLEVEL%')
[IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
$log = "$WorkDir\build.log"
[void](Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $log `
        -RedirectStandardError "$log.err" -NoNewWindow -Wait -PassThru)
$b = Get-Content $log -Raw
if ($b -notmatch 'BUILD_EXITCODE=0') { Write-Host $b; Write-Host 'FATAL: compile failed' -ForegroundColor Red; exit 2 }
$r = & { $ErrorActionPreference = 'Continue'; & "$WorkDir\ReferenceDbTests.exe" 2>&1 | ForEach-Object { "$_" } } | Out-String
$rc = $LASTEXITCODE
Write-Host $r.TrimEnd()
Check 'ReferenceDbTests' ($rc -eq 0) "exit $rc"

Write-Host '== 2. source anchors =='
$db   = [IO.File]::ReadAllText((Join-Path $SrcDir 'DragLint.Plugin.DbResolver.pas'))
$dpk  = [IO.File]::ReadAllText((Join-Path $SrcDir 'dclDragLintWizard.dpk'))
$proj = [IO.File]::ReadAllText((Join-Path $SrcDir 'dclDragLintWizard.dproj'))
Check 'ResolveActiveIndexDbs asks ReferenceDbFor' ($db -match '(?s)function ResolveActiveIndexDbs\(const ASettings: TDragLintSettings\): TArray<string>;\s+var.{0,3500}?ReferenceDbFor\(PluginIniPath\(GetEnvironmentVariable\(''APPDATA''\)\), ManifestDb\)')
Check 'the package contains the unit' ($dpk -match 'DragLint\.Plugin\.ReferenceDb in ''DragLint\.Plugin\.ReferenceDb\.pas''')
Check 'the project lists the unit' ($proj -match 'DCCReference Include="DragLint\.Plugin\.ReferenceDb\.pas"')
# A string literal only: the doc comments may keep their measurement notes. Comments are dropped first
# (///, //, { } and (* *)), so a quoted example inside one is not a hit.
$hits = foreach ($f in [IO.Directory]::GetFiles($SrcDir, '*.pas')) {
  $t = [IO.File]::ReadAllText($f)
  $code = [regex]::Replace($t, "(?s)'[^'\r\n]*'|\{.*?\}|\(\*.*?\*\)|//[^\r\n]*", { param($m) if ($m.Value[0] -eq "'") { $m.Value } else { '' } })
  foreach ($m in [regex]::Matches($code, "(?i)'[^'\r\n]*(C:\\Projects\\|Micronite|ORM3|M2022)[^'\r\n]*'")) {
    '{0}: {1}' -f [IO.Path]::GetFileName($f), $m.Value
  }
}
Check 'no private path or project name in a plugin string literal' (-not $hits) ($hits -join ' | ')

[IO.Directory]::Delete($WorkDir, $true)
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0