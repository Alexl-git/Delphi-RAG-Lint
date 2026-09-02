<#
  run_hardcoded_path_stage2.ps1 -- B7 Stage 2: ONE interprocedural hop.

  The owner's case, in his words: "Say we suspect Filename contains a path. Then
  2 lines back we see ABC(Filename, XYZ) then we need to examine ABC and XYZ."

  Stage 1 is intra-routine and store-free, so it classifies both of these CLEAN:

      (a)  FN := DefaultPath;      // a first-party FUNCTION RESULT
      (b)  BuildPath(FN);          // FN at a var/out parameter

  Stage 2 resolves the callee through the store (single first-party body, no
  cross-FILE ambiguity), parses it, and asks what it assigns to Result / to that
  formal. The finding is still reported AT THE SINK in the file being linted --
  the callee may not even belong to this project, and the sink is the line the
  reader is looking at.

  THE TRAP THIS FIXTURE EXISTS TO PIN. The first implementation put the
  function-result hook only in Classify's `exprCall` branch, and shape (a) did
  not fire at all -- because Delphi lets a parameterless function be called
  WITHOUT parentheses, so `FN := DefaultPath;` parses as a plain identifier and
  never reaches that branch. Both spellings are asserted below for that reason.
  (The same paren-less shape makes `find-callers` under-report; see
  docs\INBOX-parenless-call-is-not-a-caller.md, found the same day.)

  MUST STAY SILENT, each for a different reason, because "it fires on the two
  good cases" is not evidence that the hop is bounded:
    * the callee computes from the environment      -> not hardcoded
    * the callee takes the argument BY VALUE        -> cannot reach the caller
    * the callee has no body in the index           -> third-party, unresolvable
    * two same-named callees in DIFFERENT files     -> ambiguous, refuse
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_b7_stage2"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$n, [bool]$ok, [string]$d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Body) {
  [System.IO.File]::WriteAllText($Path, ($Body -replace "`r`n", "`n" -replace "`n", "`r`n"),
                                 [System.Text.Encoding]::ASCII)
}

Write-Host '== hardcoded-absolute-path: Stage 2 (one interprocedural hop) ==' -ForegroundColor Cyan
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

# Two units declaring a routine of the SAME NAME in DIFFERENT files. That is the
# only ambiguity that counts: an interface forward-decl and its implementation
# share a file and must NOT be treated as ambiguous.
Write-Ascii (Join-Path $WorkDir 'uAmbigA.pas') @'
unit uAmbigA;

interface

function AmbiguousPath: string;

implementation

function AmbiguousPath: string;
begin
  Result := 'C:\ambig\a.txt';
end;

end.
'@

Write-Ascii (Join-Path $WorkDir 'uAmbigB.pas') @'
unit uAmbigB;

interface

function AmbiguousPath: string;

implementation

function AmbiguousPath: string;
begin
  Result := 'C:\ambig\b.txt';
end;

end.
'@

Write-Ascii (Join-Path $WorkDir 'uStage2.pas') @'
unit uStage2;

interface

procedure FiresVarOut;
procedure FiresFuncResultBare;
procedure FiresFuncResultParens;
procedure SilentFromEnvironment;
procedure SilentValueParam;
procedure SilentThirdParty;
procedure SilentAmbiguous;

implementation

uses
  System.IOUtils, System.SysUtils, uAmbigA, uAmbigB;

procedure BuildPath(var A: string);
begin
  A := 'C:\data\' + 'out.txt';
end;

function DefaultPath: string;
begin
  Result := 'C:\data\default.txt';
end;

function FromConfig: string;
begin
  Result := GetEnvironmentVariable('OUTDIR') + '\x.txt';
end;

procedure TakesByValue(A: string);
begin
  A := 'C:\data\ignored.txt';
end;

procedure FiresVarOut;
var
  FN: string;
begin
  BuildPath(FN);
  TFile.WriteAllText(FN, 'x');
end;

procedure FiresFuncResultBare;
var
  FN: string;
begin
  FN := DefaultPath;
  TFile.WriteAllText(FN, 'x');
end;

procedure FiresFuncResultParens;
var
  FN: string;
begin
  FN := DefaultPath();
  TFile.WriteAllText(FN, 'x');
end;

procedure SilentFromEnvironment;
var
  FN: string;
begin
  FN := FromConfig;
  TFile.WriteAllText(FN, 'x');
end;

procedure SilentValueParam;
var
  FN: string;
begin
  TakesByValue(FN);
  TFile.WriteAllText(FN, 'x');
end;

procedure SilentThirdParty;
var
  FN: string;
begin
  NoBodyAnywhere(FN);
  TFile.WriteAllText(FN, 'x');
end;

procedure SilentAmbiguous;
var
  FN: string;
begin
  FN := AmbiguousPath;
  TFile.WriteAllText(FN, 'x');
end;

end.
'@

$db  = Join-Path $WorkDir 'p.sqlite'
$rep = Join-Path $WorkDir 'rep.txt'
$idx = & $Exe index $WorkDir --db $db 2>&1 | Out-String
& $Exe lint-all --db $db --output $rep --quiet 2>&1 | Out-Null
$out = if (Test-Path $rep) { Get-Content $rep } else { @() }

Check 'control: the fixture units parsed' ($idx -notmatch '-> 0 symbols') `
  'a parse failure would make every silent-arm pass by silence'

# Findings carry a line; map each to its routine so the arms mean something.
$src = Get-Content (Join-Path $WorkDir 'uStage2.pas')
$hit = @()
foreach ($l in $out) {
  if ($l -match 'uStage2\.pas:(\d+):\d+.*hardcoded-absolute-path') {
    $ln = [int]$Matches[1]; $r = '?'
    for ($i = 0; $i -lt $ln -and $i -lt $src.Count; $i++) {
      if ($src[$i] -match '^procedure (\w+);') { $r = $Matches[1] }
    }
    $hit += $r
  }
}
Write-Host ("  routines reported: " + (($hit | Sort-Object -Unique) -join ', '))

Check 'control: Stage 2 reported something at all' ($hit.Count -gt 0) "hits=$($hit.Count)"

Check '(b) var/out parameter fires'            ($hit -contains 'FiresVarOut')            'BuildPath(FN) then a sink'
Check '(a) function result fires -- BARE call' ($hit -contains 'FiresFuncResultBare')    'FN := DefaultPath;  (no parens)'
Check '(a) function result fires -- PARENS'    ($hit -contains 'FiresFuncResultParens')  'FN := DefaultPath();'

Check 'SILENT: callee computes from the environment' (-not ($hit -contains 'SilentFromEnvironment')) ''
Check 'SILENT: argument passed BY VALUE'             (-not ($hit -contains 'SilentValueParam'))      'cannot carry a value back'
Check 'SILENT: callee has no body in the index'      (-not ($hit -contains 'SilentThirdParty'))      'third-party / unresolvable'
Check 'SILENT: two same-named callees in different files' (-not ($hit -contains 'SilentAmbiguous'))  'cross-file ambiguity -> refuse'

Write-Host ''
if ($script:Failed) { Write-Host 'B7 STAGE 2 GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'B7 STAGE 2 GUARD: PASS' -ForegroundColor Green
exit 0
