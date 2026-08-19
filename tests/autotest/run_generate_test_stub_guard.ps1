<#
  run_generate_test_stub_guard.ps1 -- `drag-lint generate-test` must emit a unit
  that COMPILES, and must not invent an expected value.

  THE DEFECT THIS PINS (docs\INBOX-generate-test-treats-unit-segment-as-class.md,
  2026-08-18). For a FREE routine in a dotted-name unit the generator emitted:

      var Subject: Returns;              <- "Returns" is a UNIT segment
      Subject := Returns.Create;         <- constructing a unit
      Assert.AreEqual(0, Subject.MineReturnExpressions(0), '...');

  It took the second-to-last dotted segment to be the enclosing class, which is
  only true when the unit name has ONE segment. Delphi unit names are routinely
  dotted, so the output was uncompilable for most of this codebase -- and the
  assertion fabricated both an argument and an expected value, which is worse
  than no assertion because it can go green by accident.

  WHY THE FIXTURE LOOKS LIKE IT DOES:

  * `Dotted.Sample.Api` has THREE segments. A single-segment unit name makes the
    old heuristic accidentally correct and hides the bug entirely.
  * BOTH a free routine and a real method are generated. The method case passed
    before the fix; a method-only guard would have stayed green through the
    whole defect. Case C is therefore a positive control -- it asserts the
    method stub STILL declares a Subject, so a fix that simply deleted Subject
    everywhere fails here.
  * B1.2 is checked by actually running dcc64 over the emitted text, against
    the real DUnitX that ships with RAD Studio. "Looks right" is not a compile.

  RED PROOF (recorded 2026-08-18), run with
  -Exe third_party\dll-win64\drag-lint.exe (the pre-fix engine). For
  Dotted.Sample.Api.AddNumbers it emitted, verbatim:

      TApiAddNumbersTests = class      <- fixture named after a UNIT segment
      var Subject: Api;                <- "Api" is the last unit segment
      Subject := Api.Create;
      Assert.AreEqual(0, Subject.AddNumbers(0), 'AddNumbers happy path');

  -- with no unit header, no uses clause and no registration, so it is a
  fragment that cannot be compiled at all. Every case A assertion fails.

  NOTE WHICH SEGMENT IT MISTOOK: "Api", the LAST segment of the unit name, not
  "Sample". The first version of this guard asserted against "Sample" and would
  have passed against the broken engine while claiming to pin the defect --
  which is the failure mode this repo keeps meeting. The verbatim red output
  above is the reason the names below are what they are.
#>

[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_teststub_guard"
)

$ErrorActionPreference = 'Stop'
$script:Failed = $false

function Check([string]$n, [bool]$ok, [string]$d) {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

Write-Host 'run_generate_test_stub_guard -- generated stubs must compile, and must not invent assertions' -ForegroundColor Cyan

if (-not (Test-Path $Exe)) {
  Write-Host "FATAL: engine not found at $Exe" -ForegroundColor Red
  Write-Host 'FAIL' -ForegroundColor Red
  exit 1
}

$fixtureDir = "$PSScriptRoot\fixtures\teststub"
$unitFile   = "$fixtureDir\Dotted.Sample.Api.pas"
if (-not (Test-Path $unitFile)) {
  Write-Host "FATAL: fixture unit missing -- $unitFile" -ForegroundColor Red
  Write-Host 'FAIL' -ForegroundColor Red
  exit 1
}

if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

# ---- index the fixture into a scratch DB ----------------------------------
$db = "$WorkDir\teststub.sqlite"
$idx = & $Exe index $fixtureDir --db $db 2>&1 | Out-String
Check 'fixture indexed into a scratch DB' (Test-Path $db) `
  (($idx -split "`r?`n" | Where-Object { $_ -match 'file|symbol' } | Select-Object -Last 1))

if (-not (Test-Path $db)) {
  Write-Host "FATAL: index produced no DB. Output:`n$idx" -ForegroundColor Red
  Write-Host 'FAIL' -ForegroundColor Red
  exit 1
}

function Generate([string]$qname) {
  # stdout ONLY. Merging stderr with 2>&1 interleaves the engine's config banner
  # ("loaded defaults from ...", "FTS5 probe") INTO the unit at an unpredictable
  # point -- which showed up as a compile error on a line the generator never
  # emitted, i.e. as a fault in the code under test rather than in the harness.
  $raw = & $Exe generate-test --qname $qname --framework dunitx --db $db 2>$null | Out-String
  # Keep from the `unit` line to `end.` so the file written is only source.
  #
  # When there is NO unit header the whole output is returned instead of
  # nothing. That matters for the red run: the pre-fix engine emitted a bare
  # fragment, and bailing out here would have skipped every B1.1/B1.3 assertion
  # and reported the defect merely as "no stub generated" -- which is not what
  # the guard claims to detect.
  $lines = $raw -split "`r?`n"
  $start = ($lines | Select-String -Pattern '^unit ' | Select-Object -First 1).LineNumber
  if (-not $start) { return $raw.Trim() }
  $endIdx = $null
  for ($i = $lines.Count - 1; $i -ge 0; $i--) { if ($lines[$i].Trim() -eq 'end.') { $endIdx = $i; break } }
  if ($null -eq $endIdx) { return $raw.Trim() }
  return (($lines[($start - 1)..$endIdx]) -join "`r`n")
}

# dcc64 compiles a bare unit directly. The DUnitX that ships with RAD Studio is
# used rather than a local stand-in, so "it compiles" means against the real API.
function CompileUnit([string]$path, [string]$tag) {
  $rsvars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
  $dunitx  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\source\DunitX'
  $outDir  = "$WorkDir\out_$tag"
  New-Item -ItemType Directory -Force $outDir | Out-Null
  $bat = "$WorkDir\build_$tag.bat"
  $log = "$WorkDir\build_$tag.log"
  $body = (@(
    '@echo off'
    "call `"$rsvars`""
    "cd /d `"$WorkDir`""
    "dcc64 -CC -U`"$fixtureDir`";`"$dunitx`" -N0`"$outDir`" -E`"$outDir`" `"$path`""
    'echo BUILD_EXITCODE=%ERRORLEVEL%'
  ) -join "`r`n")
  [System.IO.File]::WriteAllText($bat, $body, [System.Text.Encoding]::ASCII)
  $null = Start-Process cmd.exe -ArgumentList "/c","`"$bat`"" -RedirectStandardOutput $log -RedirectStandardError "$log.err" -NoNewWindow -Wait -PassThru
  $out = Get-Content $log -Raw -ErrorAction SilentlyContinue
  return [pscustomobject]@{
    Ok  = ($out -match 'BUILD_EXITCODE=0') -and ($out -notmatch '\bError\b')
    Log = (($out -split "`r?`n" | Where-Object { $_ -match 'Error|Fatal|BUILD_EXITCODE' } | Select-Object -First 4) -join ' | ')
  }
}

# ---- CASE A: the free routine in a dotted-name unit ------------------------
Write-Host ''
Write-Host 'CASE A: a FREE routine in a dotted-name unit' -ForegroundColor Cyan
$freeSrc = Generate 'Dotted.Sample.Api.AddNumbers'
Check 'a stub was generated' (-not [string]::IsNullOrWhiteSpace($freeSrc)) 'generate-test produced output'
Check 'B1.2 the output is a whole UNIT, not a fragment' ($freeSrc -match '(?m)^unit ') 'unit header present'

if (-not [string]::IsNullOrWhiteSpace($freeSrc)) {
  $freePath = "$WorkDir\Test.AddNumbers.pas"
  [System.IO.File]::WriteAllText($freePath, $freeSrc, [System.Text.Encoding]::ASCII)

  # B1.1 -- the defect itself. "Api" is the segment the old code mistook for a
  # class (the LAST one, see the red output in the header); it must appear
  # nowhere as a type.
  Check 'B1.1 no variable is declared of the unit segment "Api"' `
    ($freeSrc -notmatch '(?m)^\s*Subject\s*:\s*Api\s*;') 'the reported defect, verbatim'
  Check 'B1.1 nothing is constructed from a unit segment' `
    ($freeSrc -notmatch 'Api\.Create') 'no `Api.Create`'
  Check 'B1.1 the fixture class is not named after a unit segment' `
    ($freeSrc -notmatch 'TApiAddNumbersTests') 'the old name inherited the same assumption'
  Check 'B1.1 a free routine gets no Subject at all' `
    ($freeSrc -notmatch '(?m)^\s*Subject\s*:') 'there is no class to instantiate'
  Check 'the routine is called, qualified by its unit' `
    ($freeSrc -match 'Dotted\.Sample\.Api\.AddNumbers\(') 'called as a free routine'
  Check 'the parameters come from the stored signature' `
    (($freeSrc -match '(?m)^\s*A\s*:\s*Integer;') -and ($freeSrc -match '(?m)^\s*B\s*:\s*Integer;')) `
    'A and B declared as Integer'

  # B1.3 -- no fabricated expected value.
  Check 'B1.3 no fabricated expected value is asserted' `
    ($freeSrc -notmatch 'AreEqual') 'no Assert.AreEqual against an invented value'
  Check 'B1.3 the stub fails until a human writes it' `
    ($freeSrc -match 'Assert\.Fail') 'cannot go green by accident'

  # B1.2 -- it actually compiles.
  $c = CompileUnit $freePath 'free'
  Check 'B1.2 the generated unit compiles (dcc64, real DUnitX)' $c.Ok $c.Log
}

# ---- CASE B: a real method -------------------------------------------------
Write-Host ''
Write-Host 'CASE B: a real method on a real class' -ForegroundColor Cyan
$methSrc = Generate 'Dotted.Sample.Api.TSampleWorker.Describe'
Check 'a stub was generated' (-not [string]::IsNullOrWhiteSpace($methSrc)) 'generate-test produced output'
Check 'B1.2 the output is a whole UNIT, not a fragment' ($methSrc -match '(?m)^unit ') 'unit header present'

if (-not [string]::IsNullOrWhiteSpace($methSrc)) {
  $methPath = "$WorkDir\Test.TSampleWorker.Describe.pas"
  [System.IO.File]::WriteAllText($methPath, $methSrc, [System.Text.Encoding]::ASCII)

  # POSITIVE CONTROL. A "fix" that just stopped emitting Subject everywhere
  # would satisfy every case A assertion and be wrong. Here it must be present.
  Check 'the method stub DOES declare a Subject of the real class' `
    ($methSrc -match '(?m)^\s*Subject\s*:\s*TSampleWorker\s*;') 'positive control'
  Check 'the method stub constructs and frees it' `
    (($methSrc -match 'TSampleWorker\.Create') -and ($methSrc -match 'Subject\.Free')) 'try..finally around the call'
  Check 'the method is called on the instance' `
    ($methSrc -match 'Subject\.Describe\(') 'not as a free routine'
  Check 'both parameters are declared from the signature' `
    (($methSrc -match '(?m)^\s*AName\s*:\s*string;') -and ($methSrc -match '(?m)^\s*ACount\s*:\s*Integer;')) `
    'AName: string, ACount: Integer'
  Check 'the string return type is captured' `
    ($methSrc -match '(?m)^\s*Actual\s*:\s*string;') 'function result assigned'

  $c2 = CompileUnit $methPath 'method'
  Check 'B1.2 the generated unit compiles (dcc64, real DUnitX)' $c2.Ok $c2.Log
}

# ---- CASE C: a procedure has no result to capture --------------------------
Write-Host ''
Write-Host 'CASE C: a procedure gets no Actual and no result assignment' -ForegroundColor Cyan
$procSrc = Generate 'Dotted.Sample.Api.LogSomething'
if (-not [string]::IsNullOrWhiteSpace($procSrc)) {
  Check 'no Actual variable for a procedure' ($procSrc -notmatch '(?m)^\s*Actual\s*:') 'nothing to assign'
  Check 'the call is a bare statement'      ($procSrc -notmatch 'Actual :=')          'no invented result'
  $procPath = "$WorkDir\Test.LogSomething.pas"
  [System.IO.File]::WriteAllText($procPath, $procSrc, [System.Text.Encoding]::ASCII)
  $c3 = CompileUnit $procPath 'proc'
  Check 'B1.2 the generated unit compiles (dcc64, real DUnitX)' $c3.Ok $c3.Log
} else {
  Check 'a stub was generated for the procedure' $false 'generate-test produced nothing'
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
