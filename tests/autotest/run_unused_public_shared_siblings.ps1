<#
  run_unused_public_shared_siblings.ps1 -- `unused-public-symbol` CONSULTS the
  sibling projects a shared unit's own `dl:shared` header names, instead of
  telling the reader to go and check by hand.

  THE PROBLEM. IsReferenced asks ONE project's index. YADF, YADFOT and YADFSetup
  are three projects over one source folder, so a routine defined in a shared
  unit and called only from a sibling is unreferenced HERE and very much alive.
  Measured on the real corpus 2026-08-17: of 9 findings, SIX were false this way
  (SaveOptionsToIni, EmitTokens x2, EncodingOf, DetectSourceEncoding,
  RenderGroupTree -- each with >=1 caller ref in a named sibling) and three were
  the SAME genuinely-dead routine (OptionsHelpText, 0 refs in all three).

  Note the corpus figures correct the backlog note, which said "8 are alive in a
  sibling and OptionsHelpText is genuinely dead (x3)" -- 8 + 3 does not fit in 9.

  WHY CONSULTING THOSE DBs IS LEGITIMATE. It does not violate the standing
  authoritative-set rule (platform library + project DB, nothing else): the
  unit's OWN header declares the relationship. This is following a statement the
  source makes about itself, not a name-match sweep across every index on the box.

  WHAT THE FIXTURE BUILDS. One shared unit (Shared.Lib.pas, declaring TWO
  exported routines and carrying `// dl:shared AppOne, AppTwo`), compiled into
  two projects. AppOne references neither. AppTwo references exactly ONE of them.

    LiveRoutine  -- referenced from AppTwo  -> must be SUPPRESSED when linting AppOne
    DeadRoutine  -- referenced from nowhere -> must still be REPORTED

  THE DISCRIMINATION IS THE POINT. Both routines sit in the same unit, are both
  exported, and are both unreferenced *within AppOne*. Only consulting AppTwo can
  tell them apart -- so a single fixture proves the suppression fires AND that it
  is not a blanket "shared units are exempt". A rule that simply skipped shared
  units would lose DeadRoutine, which is precisely the false negative the caveat
  message was invented to avoid.

  Usage: pwsh -File tests/autotest/run_unused_public_shared_siblings.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-unused-public-siblings"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# --- The shared unit and the two projects that compile it. -----------------------
$one = Join-Path $WorkDir 'AppOne'; New-Item -ItemType Directory $one | Out-Null
$two = Join-Path $WorkDir 'AppTwo'; New-Item -ItemType Directory $two | Out-Null

# The header is what declares the relationship the rule is allowed to follow.
Write-Ascii (Join-Path $one 'Shared.Lib.pas') @'
unit Shared.Lib;   // dl:shared AppOne, AppTwo

interface

function LiveRoutine(const A: Integer): Integer;
function DeadRoutine(const A: Integer): Integer;

implementation

function LiveRoutine(const A: Integer): Integer;
begin
  Result := A * 2;
end;

function DeadRoutine(const A: Integer): Integer;
begin
  Result := A + 1;
end;

end.
'@
Copy-Item (Join-Path $one 'Shared.Lib.pas') (Join-Path $two 'Shared.Lib.pas') -Force

# AppOne uses the unit but calls NEITHER routine.
Write-Ascii (Join-Path $one 'AppOneMain.pas') @'
unit AppOneMain;

interface

uses Shared.Lib;

procedure RunOne;

implementation

procedure RunOne;
begin
end;

end.
'@

# AppTwo calls exactly ONE of them.
Write-Ascii (Join-Path $two 'AppTwoMain.pas') @'
unit AppTwoMain;

interface

uses Shared.Lib;

procedure RunTwo;

implementation

procedure RunTwo;
var
  N: Integer;
begin
  N := LiveRoutine(21);
  if N > 0 then Exit;
end;

end.
'@

$dbOne = Join-Path $WorkDir 'AppOne.sqlite'
$dbTwo = Join-Path $WorkDir 'AppTwo.sqlite'

# A manifest whose SECTION NAMES are exactly the names the dl:shared header uses.
# That equality is what makes the resolution work and is worth pinning here.
$manifest = Join-Path $WorkDir 'drag-lint.json'
Write-Ascii $manifest (@'
{
  "settings": { "defaultPlatform": "Win64" },
  "indexes": {
    "outDir": "OUTDIR",
    "sections": [
      { "name": "AppOne", "include": ["ONEDIR"] },
      { "name": "AppTwo", "include": ["TWODIR"] }
    ]
  }
}
'@ -replace 'OUTDIR', ($WorkDir -replace '\\', '\\') `
   -replace 'ONEDIR', ($one     -replace '\\', '\\') `
   -replace 'TWODIR', ($two     -replace '\\', '\\'))

Write-Host 'Indexing both projects' -ForegroundColor Cyan
foreach ($pair in @(@($one, $dbOne), @($two, $dbTwo))) {
  $out = & $Exe index $pair[0] --db $pair[1] --quiet 2>&1
  Check ("index {0}" -f (Split-Path $pair[1] -Leaf)) ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE; $($out -join ' | ')"
}

# --- Preconditions: the fixture really is what the assertions assume. -------------
Write-Host ''
Write-Host 'preconditions' -ForegroundColor Cyan

$callsLive = @(& $Exe query find-callers --name LiveRoutine --db $dbTwo --quiet 2>&1) -join "`n"
Check 'precondition: AppTwo really does reference LiveRoutine' ($callsLive -match 'AppTwoMain') $callsLive
$callsDead = @(& $Exe query find-callers --name DeadRoutine --db $dbTwo --quiet 2>&1) -join "`n"
Check 'precondition: AppTwo does NOT reference DeadRoutine' ($callsDead -notmatch 'AppTwoMain') $callsDead

# --- The run under test: lint AppOne, which references neither routine. -----------
Write-Host ''
Write-Host 'lint AppOne -- both routines are unreferenced HERE; only AppTwo can separate them' -ForegroundColor Cyan

$lint = (@(& $Exe lint-all --db $dbOne --config $manifest --rules-dir "$PSScriptRoot\..\..\rules" --quiet 2>&1) |
           ForEach-Object { "$_" }) -join "`n"
$ups = ($lint -split "`n") | Where-Object { $_ -match 'unused-public-symbol' }

Check 'precondition: the rule fired at all on this fixture' ($ups.Count -ge 1) `
  "unused-public-symbol lines=$($ups.Count) -- if 0 the rule never ran and every assertion below is vacuous:`n$lint"

Check 'ASSERT: DeadRoutine is still REPORTED' `
  (($ups -join "`n") -match 'DeadRoutine') `
  "$($ups -join "`n") -- a rule that simply exempted shared units would lose this, trading a false positive for a false negative in the same file"

Check 'ASSERT: LiveRoutine is SUPPRESSED (it is referenced in the named sibling)' `
  (($ups -join "`n") -notmatch 'LiveRoutine') `
  "$($ups -join "`n")"

Check 'ASSERT: the message says the siblings were CHECKED, not that the reader should check' `
  (($ups -join "`n") -match 'nor in the project\(s\) its unit is shared with') `
  "$($ups -join "`n") -- the old wording told the reader to go and look; once the engine has looked, saying so is the honest report"

Write-Host ''
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
