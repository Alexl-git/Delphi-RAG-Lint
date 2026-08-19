<#
  run_hover_signature_guard.ps1 -- the hover popup's header must show a
  PROPERTY's and a FIELD's declared type.

  THE DEFECT THIS PINS (owner, live IDE, 2026-08-19):
    "When pointing on other properties it doesn't report type. We need type.
     IDE shows type why not us?"

    Hovering TTimer.Enabled rendered

        property Vcl.ExtCtrls.TTimer.Enabled

    where the IDE shows `Enabled: Boolean`.

  THE ENGINE WAS NEVER AT FAULT -- measured before any change:

    hover --qname Vcl.ExtCtrls.TTimer.Enabled --format json
      -> "kind":"property","signature":"Boolean","return_type":"","params":[]

    The type is in SIGNATURE. The popup's composer appended ": X" only from
    return_type -- empty for a property -- and read the raw signature only for
    enum values. The single fact the user asked for was the single fact dropped,
    for every property and every field in every project.

  WHY BOTH COMPOSERS ARE MEASURED. The harness runs each case through the NEW
  composer AND a faithful reproduction of the OLD one, and both are printed:

    * PROP/PROPEV/FIELD assert NEW carries the type while OLD does not -- the
      RED proof, re-run every time rather than once by hand;
    * FUNC asserts a routine is UNCHANGED. Its raw signature is a parameter
      list, so a naive "just append the raw signature" fix renders
      "function Trim(const S: string): (const S: string)". Without this case
      that fix passes.
    * ENUMVAL asserts " = 0" survives. An ordinal is parenthesis-free exactly
      like a property type, so a bare-type rule that did not test enum values
      FIRST would print ": 0". Without this case that bug ships silently.

  Neither direction alone is evidence.
#>
[CmdletBinding()]
param(
  [string]$FixtureDir = "$PSScriptRoot\fixtures\hoversignature",
  [string]$WorkDir    = "$env:TEMP\drag-lint-hoversig-guard"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

# A bare .dpr cannot be built by msbuild, so use dcc64 from rsvars -- the same
# arrangement run_hover_callers_scope_guard.ps1 uses.
$rsvars    = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$pluginDir = "$PSScriptRoot\..\..\src\delphi-plugin"
$outDir    = "$FixtureDir\Win64\Debug"
New-Item -ItemType Directory -Force $outDir | Out-Null
$batPath = "$WorkDir\build_harness.bat"
$logPath = "$WorkDir\build_harness.log"
$batBody = (@(
  '@echo off'
  "call `"$rsvars`""
  "cd /d `"$FixtureDir`""
  "dcc64 -CC -U`"$pluginDir`" -E`"$outDir`" -N0`"$outDir`" HoverSignatureHarness.dpr"
  'echo BUILD_EXITCODE=%ERRORLEVEL%'
) -join "`r`n")
[System.IO.File]::WriteAllText($batPath, $batBody, [System.Text.Encoding]::ASCII)

$null = Start-Process cmd.exe -ArgumentList "/c", "`"$batPath`"" `
          -RedirectStandardOutput $logPath -RedirectStandardError "$logPath.err" `
          -NoNewWindow -Wait -PassThru
$log = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
$buildOk = ($log -match 'BUILD_EXITCODE=0') -and ($log -notmatch 'Error:')
Check 'HoverSignatureHarness.dpr builds (Win64 Debug)' $buildOk `
  (($log -split "`r?`n" | Select-Object -Last 6) -join ' | ')

$exe = "$outDir\HoverSignatureHarness.exe"
if (-not $buildOk -or -not (Test-Path $exe)) {
  Write-Host "FATAL: harness exe not found at $exe -- see $logPath" -ForegroundColor Red
  Write-Host 'FAIL' -ForegroundColor Red
  exit 1
}

$out = & $exe 2>&1 | Out-String
$kv = @{}
foreach ($line in ($out -split "`r?`n")) {
  if ($line -match '^\s*([A-Za-z0-9_.]+)=(.*)$') { $kv[$matches[1]] = $matches[2].Trim() }
}
Check 'harness ran to completion' ($out -match 'DONE') $(($out -split "`r?`n" | Select-Object -First 3) -join ' | ')

# ---- the reported defect --------------------------------------------------
Write-Host ''
Write-Host 'THE DEFECT: a property must show its type' -ForegroundColor Cyan
Check 'PROP: the new composer shows ": Boolean"' ($kv['PROP.NEW'] -eq 'property Vcl.ExtCtrls.TTimer.Enabled: Boolean') `
  "got '$($kv['PROP.NEW'])'"
Check 'PROP: the OLD composer did NOT (the guard discriminates)' ($kv['PROP.OLD'] -eq 'property Vcl.ExtCtrls.TTimer.Enabled') `
  "got '$($kv['PROP.OLD'])'"
Check 'PROPEV: a non-trivial property type survives verbatim' ($kv['PROPEV.NEW'] -match ':\s*TNotifyEvent$') `
  "got '$($kv['PROPEV.NEW'])'"
Check 'FIELD: a field shows its type too' ($kv['FIELD.NEW'] -match ':\s*TComponentName$') `
  "got '$($kv['FIELD.NEW'])'"
Check 'FIELD: the OLD composer did NOT' ($kv['FIELD.OLD'] -notmatch ':') "got '$($kv['FIELD.OLD'])'"

# ---- the controls ---------------------------------------------------------
Write-Host ''
Write-Host 'CONTROLS: the fix must not touch routines or enum values' -ForegroundColor Cyan
Check 'FUNC: a routine is byte-identical to before' ($kv['FUNC.NEW'] -ceq $kv['FUNC.OLD']) `
  "new='$($kv['FUNC.NEW'])' old='$($kv['FUNC.OLD'])'"
Check 'FUNC: the parameter list is NOT pasted where the return type goes' ($kv['FUNC.NEW'] -eq 'function System.SysUtils.Trim(const S: string): string') `
  "got '$($kv['FUNC.NEW'])'"
Check 'ENUMVAL: still renders " = 0", not ": 0"' ($kv['ENUMVAL.NEW'] -match '\s=\s0$') `
  "got '$($kv['ENUMVAL.NEW'])'"
Check 'ENUMVAL: byte-identical to before' ($kv['ENUMVAL.NEW'] -ceq $kv['ENUMVAL.OLD']) `
  "new='$($kv['ENUMVAL.NEW'])' old='$($kv['ENUMVAL.OLD'])'"
Check 'BARE: a symbol with nothing to add is unchanged' ($kv['BARE.NEW'] -ceq $kv['BARE.OLD']) `
  "new='$($kv['BARE.NEW'])' old='$($kv['BARE.OLD'])'"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
