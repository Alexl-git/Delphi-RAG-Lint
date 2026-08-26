<#
  run_lint_file_flow_matches_lintall.ps1 -- `lint <file>` and `lint-all` must
  reach the SAME definite-assignment verdict for the same file.

  THE DEFECT THIS PINS:
    The flow-sensitive checks (used-before-assignment, overwrite-before-read)
    resolve types through the symbol store. IsRecordType deliberately carries NO
    naming-convention fallback, so with no store it answers False for every type
    -- and the "a method call on a RECORD local DEFINES it" rule, which exists
    because a record has no constructor, silently switches off.

    lint-all passed the store. `lint <file>` called TFlowChecker.Check(EffPath)
    with no store at all, even when --db was given: the store DoLint opens is
    gated on --fix, and sat 60 lines BELOW the flow-check call.

    So the same file got two different answers from two verbs. Measured
    2026-08-26 over this project's own 90 scanned files:

        store-free (lint <file>)   23 used-before-assignment ERRORS
        store-backed (lint-all)     3

    while the OTHER two counts agreed exactly -- 34 used-before-assignment
    warnings and 29 overwrite-before-read -- proving the store was the only
    variable and that all 20 extra errors were false.

    This is the verb the editor gutter runs. DragLint.Plugin.LiveDiagnostics
    issues `drag-lint lint "<file>"` with no --db, and used-before-assignment
    became error-severity in 9f78db3. 20 of 23 red marks on our own source were
    manufactured by the missing store.

  WHY THE CONTROL IS NOT OPTIONAL:
    "the two verbs agree" is satisfied just as well by a build where the rule
    never fires at all. So the fixture carries a GENUINE use-before-assignment
    that BOTH verbs must still report, and a record local that NEITHER may
    report. A build that goes silent fails the first; a store-free build fails
    the second.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lint-file-flow"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Text) {
  $norm = ($Text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
$app  = Join-Path $WorkDir 'app'
$drag = Join-Path $app '_D-RAG'
foreach ($d in @($WorkDir, $app, $drag)) { New-Item -ItemType Directory $d -Force | Out-Null }

# TProf is a RECORD, so `P.Init` is how it establishes its own value -- there is
# no constructor to call. Store-free the analysis cannot know that and calls the
# later `P.Mark` a read of an unassigned local.
Write-Ascii (Join-Path $app 'uFlow.pas') @'
unit uFlow;

interface

type
  TProf = record
    FActive: Boolean;
    FMark  : Integer;
    procedure Init(const AName: string);
    procedure Stamp;
  end;

function RecordLocalIsDefinedByItsOwnMethodCall: Integer;
function GenuinelyUnassignedLocal: Integer;

implementation

procedure TProf.Init(const AName: string);
begin
  FActive := AName <> '';
  FMark   := 0;
end;

procedure TProf.Stamp;
begin
  Inc(FMark);
end;

{ MUST NOT be reported: P.Init defines P. }
function RecordLocalIsDefinedByItsOwnMethodCall: Integer;
var
  P: TProf;
begin
  P.Init('run');
  P.Stamp;
  Result := P.FMark;
end;

{ MUST be reported by BOTH verbs -- the live control. }
function GenuinelyUnassignedLocal: Integer;
var
  N: Integer;
begin
  Result := N + 1;
end;

end.
'@

Write-Ascii (Join-Path $app 'App.dpr') @'
program App;
uses
  uFlow in 'uFlow.pas';
begin
  Writeln(RecordLocalIsDefinedByItsOwnMethodCall);
end.
'@
Write-Ascii (Join-Path $drag 'drag-lint-project.json') '{ "ownRoots": ["."] }'

$db    = Join-Path $drag 'app.sqlite'
$src   = Join-Path $app 'uFlow.pas'
$proj  = Join-Path $app 'App.dpr'
& $Exe index $app --db $db 2>&1 | Out-Null

function Flow-Lines([string]$Text) {
  @($Text -split "`r?`n" | Where-Object { $_ -match 'used-before-assignment' -and $_ -match 'uFlow\.pas' })
}
function Sev-Of([string[]]$Lines, [string]$VarName) {
  $m = $Lines | Where-Object { $_ -match ('"' + $VarName + '"') } | Select-Object -First 1
  if (-not $m) { return 'none' }
  if ($m -match '\[(error|warning|info|hint)\]') { return $Matches[1] }
  return 'unknown'
}

Push-Location $app
try {
  $lintOut    = & $Exe lint $src --db $db 2>&1 | Out-String
  $lintAllOut = & $Exe lint-all --project $proj --db $db 2>&1 | Out-String
} finally { Pop-Location }

$lintLines    = Flow-Lines $lintOut
$lintAllLines = Flow-Lines $lintAllOut

Write-Host 'LIVE CONTROL: the genuine defect is reported by BOTH verbs' -ForegroundColor Cyan
# Without this, every "not reported" assertion below passes on a dead rule.
$nLint    = Sev-Of $lintLines    'n'
$nLintAll = Sev-Of $lintAllLines 'n'
Check 'lint <file> still reports the genuinely unassigned local' `
  ($nLint -ne 'none') ("severity: {0}" -f $nLint)
Check 'lint-all still reports the genuinely unassigned local' `
  ($nLintAll -ne 'none') ("severity: {0}" -f $nLintAll)

Write-Host ''
Write-Host 'THE ASSERTION: the record local is reported by NEITHER verb' -ForegroundColor Cyan
$pLint    = Sev-Of $lintLines    'p'
$pLintAll = Sev-Of $lintAllLines 'p'
Check 'lint-all does not report the record local' `
  ($pLintAll -eq 'none') ("got: {0}" -f $pLintAll)
Check 'lint <file> does not report the record local (needs the store)' `
  ($pLint -eq 'none') ("got: {0}" -f $pLint)

Write-Host ''
Write-Host 'AGREEMENT: the two verbs return the same verdict per variable' -ForegroundColor Cyan
Check 'the two verbs agree on the record local'      ($pLint -eq $pLintAll) ("lint={0} lint-all={1}" -f $pLint, $pLintAll)
Check 'the two verbs agree on the genuine defect'    ($nLint -eq $nLintAll) ("lint={0} lint-all={1}" -f $nLint, $nLintAll)

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
