<#
  run_hover_callers_scope_guard.ps1 -- the hover popup's "CALLED FROM" list must
  contain call sites of the HOVERED SYMBOL, not of every symbol sharing its name.

  THE DEFECT THIS PINS (owner, 2026-08-18, live IDE). Hovering
  `EException.TEurekaExceptionInfo.Create` produced "CALLED FROM (55)" listing
  TMemIniFile.Create, TTimer.Create, TStringList.Create, Exception.Create --
  every Create in the project except the one asked about.

  The shipped code was already filtering: it kept only rows whose source line
  was qualified by the target's own class, and ON ZERO MATCHES FELL BACK TO THE
  UNFILTERED LIST. DataCopy never constructs TEurekaExceptionInfo, so the filter
  correctly matched nothing -- and the fallback published the noise.

  That is the shape worth guarding: a fail-open fallback emits its most
  confident garbage precisely when the exact answer is EMPTY.

  WHY BOTH POLICIES ARE MEASURED. The harness runs each fixture through the new
  SelectCallers AND through a faithful re-implementation of the old policy. A
  guard that only asserted "case A returns 0 rows" would pass against a policy
  that returns 0 rows for EVERYTHING -- which is a different bug with the same
  green tick. So:

    * case A asserts NEW=0 while OLD=3  -> the guard discriminates, and the old
      code really did fail this case (this is the RED proof, run every time
      rather than once by hand);
    * case D asserts NEW=2              -> the permissive fallback still works
      for instance-variable calls, so the fix is not "always return nothing".

  Both directions are required. Neither alone is evidence.
#>
[CmdletBinding()]
param(
  [string]$FixtureDir = "$PSScriptRoot\fixtures\callerfilter",
  [string]$WorkDir    = "$env:TEMP\drag-lint-callerfilter-guard"
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

# --- build the harness (Win64 Debug) exactly as run_dbresolver_probe.ps1 does:
# a bare .dpr cannot be built by msbuild, so use dcc64 from rsvars.
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
  "dcc64 -CC -U`"$pluginDir`" -E`"$outDir`" -N0`"$outDir`" CallerFilterHarness.dpr"
  'echo BUILD_EXITCODE=%ERRORLEVEL%'
) -join "`r`n")
[System.IO.File]::WriteAllText($batPath, $batBody, [System.Text.Encoding]::ASCII)

$null = Start-Process cmd.exe -ArgumentList "/c", "`"$batPath`"" `
          -RedirectStandardOutput $logPath -RedirectStandardError "$logPath.err" `
          -NoNewWindow -Wait -PassThru
$log = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
$buildOk = ($log -match 'BUILD_EXITCODE=0') -and ($log -notmatch 'Error:')
Check 'CallerFilterHarness.dpr builds (Win64 Debug)' $buildOk `
  (($log -split "`r?`n" | Select-Object -Last 6) -join ' | ')

$exe = "$outDir\CallerFilterHarness.exe"
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

# ---- A: the reported defect ----
Write-Host ''
Write-Host 'CASE A: same-named callers of OTHER types must not be listed' -ForegroundColor Cyan
Check 'class qualifier is TEurekaExceptionInfo.Create' `
  ($kv['A.classqual'] -eq 'TEurekaExceptionInfo.Create') "got: $($kv['A.classqual'])"
Check 'NEW returns no callers' ($kv['A.new.count'] -eq '0') "got: $($kv['A.new.count'])"
Check 'NEW reports it as "name resolves elsewhere"' `
  ($kv['A.new.source'] -eq 'noneresolved') "got: $($kv['A.new.source'])"
# The RED proof, asserted rather than remembered.
Check 'OLD policy DID list the unrelated Creates (guard discriminates)' `
  ($kv['A.old.count'] -eq '3') "got: $($kv['A.old.count'])"

# ---- B: a real resolved hit ----
Write-Host ''
Write-Host 'CASE B: an exact resolved edge wins' -ForegroundColor Cyan
Check 'NEW returns exactly the one real caller' ($kv['B.new.count'] -eq '1') "got: $($kv['B.new.count'])"
Check 'NEW reports source=resolved' ($kv['B.new.source'] -eq 'resolved') "got: $($kv['B.new.source'])"
# The resolved query reports a bare file name; the popup needs a full path to
# open the file. Matching on base name + line must return the NAME-INDEX row.
Check 'NEW keeps the FULL path, not the resolved bare name' `
  ($kv['B.new.path'] -eq 'C:\Proj\uUse.pas') "got: $($kv['B.new.path'])"

# ---- C: resolver blind, class-qualified text still works ----
Write-Host ''
Write-Host 'CASE C: no resolved edges, but the line names the class' -ForegroundColor Cyan
Check 'NEW finds it by class qualifier' ($kv['C.new.count'] -eq '1') "got: $($kv['C.new.count'])"
Check 'NEW reports source=classqual' ($kv['C.new.source'] -eq 'classqual') "got: $($kv['C.new.source'])"

# ---- D: POSITIVE CONTROL ----
Write-Host ''
Write-Host 'CASE D: POSITIVE CONTROL -- instance-variable calls still listed' -ForegroundColor Cyan
Check 'NEW keeps both instance-var call sites' ($kv['D.new.count'] -eq '2') "got: $($kv['D.new.count'])"
Check 'NEW reports source=unresolvedall' `
  ($kv['D.new.source'] -eq 'unresolvedall') "got: $($kv['D.new.source'])"

# ---- E: de-duplication ----
Write-Host ''
Write-Host 'CASE E: one call site listed once' -ForegroundColor Cyan
Check 'duplicate (file,line) collapsed' ($kv['E.new.count'] -eq '1') "got: $($kv['E.new.count'])"

# ---- F: dotted unit names ----
Write-Host ''
Write-Host 'CASE F: a dotted UNIT name does not confuse the qualifier' -ForegroundColor Cyan
Check 'DRagLint.LSP.Server.TLSPServer.HandleHover -> TLSPServer.HandleHover' `
  ($kv['F.classqual'] -eq 'TLSPServer.HandleHover') "got: $($kv['F.classqual'])"
Check 'a free routine keeps its Unit.Routine form' `
  ($kv['F.free'] -eq 'MyUnit.SomeFreeRoutine') "got: $($kv['F.free'])"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
