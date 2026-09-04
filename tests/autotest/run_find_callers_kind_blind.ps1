<#
  run_find_callers_kind_blind.ps1 -- `query find-callers` must not report a
  WRITE, or a read of a same-named LOCAL, as a caller.

  THE DEFECT. FindCallersByName is name-keyed and KIND-BLIND: it returns every
  ref carrying the name, of any kind. Measured on the session-60 fixture, five
  shapes of the name `Ticks`, and the verb listed ALL FIVE:

    | shape             | kind  | is it a caller?                     |
    |-------------------|-------|-------------------------------------|
    | Consume(Ticks())  | call  | YES                                 |
    | N := Ticks;       | read  | YES -- paren-less call              |
    | F := Ticks;       | read  | no -- takes the ADDRESS             |
    | Ticks := 7;       | write | no -- a same-named LOCAL            |
    | Consume(Ticks)    | read  | no -- reads that same local         |

  Answering "who calls X" with a WRITE to an unrelated local is a worse failure
  than missing a caller: the answer looks complete and is wrong in the direction
  that invents work.

  WHY THE FIX IS A POST-FILTER AND NOT A BETTER QUERY. FindCallersByName is
  SHARED by rename/refactor (which must rewrite every occurrence, writes
  included), `usages` (which GROUPS by kind and needs the writes), the dead-code
  rules, the context bundler, and LSP/MCP references. DRagLint.Doc.Facts.pas:2580
  already records that excluding rows inside the shared query breaks those
  callers, and screens locally instead. So case 6 below is not decoration -- it
  is the assertion that stops this fix being pushed down into the store.

  >>> WHAT THIS DOES **NOT** FIX, ASSERTED SEPARATELY AND ON PURPOSE.
  `F := Ticks` takes a routine's address -- the shape of every VCL event wiring
  (`Button.OnClick := HandleClick`). It STAYS listed. Telling it apart from a
  paren-less call needs bare reads bound to symbols scope-aware, which is the
  resolver batch (R1/R2) and an owner scheduling decision. Case 3 pins it as
  KEPT so the guard states what it covers rather than implying more. When the
  resolver batch lands, that assertion is the one to flip -- deliberately.

  RED-CHECK: against a build without the post-filter, cases 4 and 5 fail and
  everything else passes. Verified.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_find_callers_kinds",
  [switch]$Quiet
)
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n, $ok, $d = '') {
  if ($Quiet) { if (-not $ok) { $script:fail = $true }; return }
  Write-Host ("  [{0}] {1}" -f (@('FAIL', 'PASS')[[int]$ok]), $n) -ForegroundColor (@('Red', 'Green')[[int]$ok])
  if (-not $ok) { if ($d) { Write-Host "        $d" -ForegroundColor DarkGray }; $script:fail = $true }
}
function W($p, $s) {
  [System.IO.File]::WriteAllText($p, (($s -replace "`r`n", "`n") -replace "`n", "`r`n"),
                                 (New-Object System.Text.UTF8Encoding($false)))
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path (Join-Path $WorkDir '_D-RAG') | Out-Null

W (Join-Path $WorkDir 'uProbe.pas') @'
unit uProbe;

interface

procedure Run;

implementation

procedure Consume(const AValue: Integer);
begin
end;

function Ticks: Integer;
begin
  Result := 42;
end;

type
  TFn = function: Integer;

procedure RealCall;
begin
  Consume(Ticks());
end;

procedure ParenlessCall;
var
  N: Integer;
begin
  N := Ticks;
  Consume(N);
end;

procedure ProceduralValue;
var
  F: TFn;
begin
  F := Ticks;
  Consume(F());
end;

procedure SameNamedLocal;
var
  Ticks: Integer;
begin
  Ticks := 7;
  Consume(Ticks);
end;

procedure Run;
begin
  RealCall;
end;

end.
'@
W (Join-Path $WorkDir 'App.dpr') @'
program App;
uses
  uProbe in 'uProbe.pas';
begin
end.
'@

$db = Join-Path $WorkDir '_D-RAG\App.sqlite'
& $Exe index --project (Join-Path $WorkDir 'App.dpr') --db $db 2>&1 | Out-Null

# Line numbers are DERIVED from the fixture, never hardcoded: an edit above
# would otherwise silently move the assertions onto the wrong statements.
$src = Get-Content (Join-Path $WorkDir 'uProbe.pas')
function LineOf($needle) {
  for ($i = 0; $i -lt $src.Count; $i++) { if ($src[$i] -like "*$needle*") { return $i + 1 } }
  return 0
}
$lnCall      = LineOf 'Consume(Ticks());'
$lnParenless = LineOf 'N := Ticks;'
$lnProcVal   = LineOf 'F := Ticks;'
$lnWrite     = LineOf 'Ticks := 7;'
$lnLocalRead = LineOf 'Consume(Ticks);'
Check 'all five fixture lines located' `
  (($lnCall -gt 0) -and ($lnParenless -gt 0) -and ($lnProcVal -gt 0) -and ($lnWrite -gt 0) -and ($lnLocalRead -gt 0)) `
  "call=$lnCall parenless=$lnParenless procval=$lnProcVal write=$lnWrite localread=$lnLocalRead"

$out = (& $Exe query find-callers --name Ticks --db $db 2>&1)
$lines = @()
foreach ($l in $out) { if ("$l" -match 'uProbe\.pas:(\d+):') { $lines += [int]$Matches[1] } }
$lines = @($lines | Sort-Object -Unique)
if (-not $Quiet) { Write-Host ("  find-callers listed lines: " + ($lines -join ', ')) -ForegroundColor DarkGray }

Write-Host '== find-callers must not call a write or a same-named local a caller ==' -ForegroundColor Cyan

# 1 + 2. CONTROLS FIRST -- the genuine callers must survive. A filter that
# removes everything satisfies cases 4 and 5 and destroys the verb.
Check "CONTROL: the real call (line $lnCall) is still listed" ($lines -contains $lnCall) `
  'the filter removed a genuine call -- find-callers is now under-reporting'
Check "CONTROL: the paren-less call (line $lnParenless) is still listed" ($lines -contains $lnParenless) `
  'paren-less invocation is idiomatic Delphi and is a real caller'

# 3. STATED NON-COVERAGE. Flip this when the resolver batch lands.
Check "NOT FIXED HERE (asserted as such): the procedural VALUE (line $lnProcVal) is still listed" `
  ($lines -contains $lnProcVal) `
  'if this now passes as EXCLUDED, the resolver work landed -- update this guard deliberately rather than deleting the case'

# 4 + 5. THE DEFECT.
Check "the WRITE to a same-named local (line $lnWrite) is NOT listed" (-not ($lines -contains $lnWrite)) `
  'a write is never a call -- kind alone disqualifies it'
Check "the READ of that same-named local (line $lnLocalRead) is NOT listed" (-not ($lines -contains $lnLocalRead)) `
  'the enclosing routine declares a local of that name, so Delphi scoping says this is the local'

# 6. >>> THE SHARED QUERY MUST STAY KIND-BLIND. `usages` groups by kind and
#    rename rewrites every occurrence, so if the filter were pushed down into
#    FindCallersByName both would silently lose the write.
$usg = (& $Exe usages --name Ticks --db $db --format json 2>&1) -join "`n"
Check 'CONTROL: `usages` still sees the write (the shared query stayed kind-blind)' `
  ($usg -match '(?i)"?writes"?') `
  'usages lost its writes group -- the filter was pushed into the shared store query, which also breaks rename'

Write-Host ''
if ($script:fail) { Write-Host 'FIND-CALLERS-KIND GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'FIND-CALLERS-KIND GUARD: PASS' -ForegroundColor Green
exit 0
