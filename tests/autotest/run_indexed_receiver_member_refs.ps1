<#
  run_indexed_receiver_member_refs.ps1 -- a member reached through an INDEXED
  receiver (`S[i].IsWhiteSpace`, `A[i].Field`, `A[i].Fn`) must reach the
  reference index as a 'member-access' ref, and unused-unit-in-uses must then
  count a type-helper member called that way as a use of the helper's unit.

  THE DEFECT (B-13; INBOX-unused-unit-charhelper-indexed.md, duplicate
  INBOX-lint-fp-unused-unit-helper-on-indexed-char.md). Walk's exprDot case
  emitted the member of `obj.Member` (ref-gap G) and of `A.B.C.Member`
  (ref-gap G2) only when the receiver was an identifier or a dotted chain of
  identifiers. An exprSubscript receiver was excluded on purpose ("the future
  expression stage's problem"), so in EXPRESSION or assignment-target position

      while (First <= Last) and S[First].IsWhiteSpace do Inc(First);
      A[I].IdxField:= 1;
      N:= A[0].IdxFn;

  emitted no ref for IsWhiteSpace / IdxField / IdxFn at all. A STATEMENT call
  `A[I].IdxMethod;` was unaffected -- EmitStatementCall emits it as a 'call'.
  unused-unit-in-uses matches helper member NAMES against the file's ref names,
  so with no ref the rule reported System.Character (TCharHelper) as a dead
  import, and removing it fails E2671. The checker needs no element type: the
  helper surface is name-matched (FindHelperMemberNamesInUnit), so the missing
  REF was the whole defect.

  CONTROLS (pass on the pre-fix engine):
    * the same helper on a LOCAL Char variable (`C.IdxBlank`) is counted;
    * a unit importing the helper unit and naming nothing from it IS flagged --
      a fix that silenced the rule wholesale fails here;
    * `A[I].IdxMethod;` and `A[I].IdxMethod();` stay exactly one 'call' each
      (no regression, no second call row);
    * `R.IdxField` on a plain record variable keeps its member-access ref.

  Exit code: 0 on full pass, 1 on any failure. pwsh 7. Run from a neutral CWD.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: engine not found at $Exe" -ForegroundColor Red; exit 1 }
$exePath = (Resolve-Path $Exe).Path
$work = Join-Path $env:TEMP ('draglint_idxrcv_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work | Out-Null
$db = Join-Path $work 'idxrcv.sqlite'

$units = [ordered]@{}
$units['uIdxHelp'] = @'
unit uIdxHelp;

interface

type
  TIdxCharHelper = record helper for Char
    function IdxBlank: Boolean;
  end;

implementation

function TIdxCharHelper.IdxBlank: Boolean;
begin
  Result:= Self = ' ';
end;

end.
'@
$units['uIdxIndexed'] = @'
unit uIdxIndexed;

interface

uses uIdxHelp;

type
  TIdxSub = record
    IdxLeaf: Integer;
  end;

  TIdxRec = record
    IdxField: Integer;
    IdxSub: TIdxSub;
    procedure IdxMethod;
    function IdxFn: Integer;
  end;

function SkipBlanks(const S: string): Integer;
procedure UseRecs(var A: TArray<TIdxRec>; var R: TIdxRec);

implementation

procedure TIdxRec.IdxMethod;
begin
end;

function TIdxRec.IdxFn: Integer;
begin
  Result:= IdxField;
end;

function SkipBlanks(const S: string): Integer;
var
  First: Integer;
begin
  First:= 1;
  while (First <= Length(S)) and S[First].IdxBlank do
    Inc(First);
  Result:= First;
end;

procedure UseRecs(var A: TArray<TIdxRec>; var R: TIdxRec);
var
  I, N: Integer;
begin
  I:= 0;
  A[I].IdxField:= 1;
  A[I].IdxMethod;
  A[I].IdxMethod();
  N:= A[0].IdxFn;
  N:= N + A[I].IdxSub.IdxLeaf;
  R.IdxField:= N;
end;

end.
'@
$units['uIdxLocal'] = @'
unit uIdxLocal;

interface

uses uIdxHelp;

function CountBlanks(const S: string): Integer;

implementation

function CountBlanks(const S: string): Integer;
begin
  Result:= 0;
  for var C in S do
    if C.IdxBlank then Inc(Result);
end;

end.
'@
$units['uIdxDead'] = @'
unit uIdxDead;

interface

uses uIdxHelp;

function Nothing: Integer;

implementation

function Nothing: Integer;
begin
  Result:= 0;
end;

end.
'@
$units['uIdxLib'] = @'
unit uIdxLib;

interface

uses System.Character;

function TrimLeftCount(const S: string): Integer;

implementation

function TrimLeftCount(const S: string): Integer;
var
  First: Integer;
begin
  First:= 1;
  while (First <= Length(S)) and S[First].IsWhiteSpace do
    Inc(First);
  Result:= First - 1;
end;

end.
'@
foreach ($k in $units.Keys) {
  $norm = $units[$k] -replace "`r`n", "`n" -replace "`n", "`r`n"
  [IO.File]::WriteAllText((Join-Path $work "$k.pas"), $norm, [Text.Encoding]::ASCII)
}

Push-Location $env:TEMP
try {
  & $exePath index $work --db $db 2>&1 | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

  # sql --json rows are POSITIONAL arrays: [0]=file, [1]=name, [2]=kind, [3]=line, [4]=receiver.
  $q = "select f.path, r.name_text, r.kind, r.start_line, coalesce(r.receiver_text, '') from refs r join files f on f.id = r.file_id"
  $j = (& $exePath sql --db $db --query $q --json 2>$null) -join "`n" | ConvertFrom-Json
  $rows = @(foreach ($row in $j.rows) {
    [pscustomobject]@{ File = [IO.Path]::GetFileNameWithoutExtension([string]$row[0]); Name = [string]$row[1]
                       Kind = [string]$row[2]; Line = [int]$row[3]; Rcv = [string]$row[4] } })
  Check 'refs were read for the fixture (premise)' (@($rows | Where-Object { $_.Name -eq 'IdxBlank' }).Count -ge 1) "rows=$($rows.Count)"

  function Sel($file, $name, $kind, $line) {
    @($rows | Where-Object { $_.File -eq $file -and $_.Name -eq $name -and $_.Kind -eq $kind -and $_.Line -eq $line })
  }

  Write-Host 'CONTROLS (pass on the pre-fix engine):' -ForegroundColor Cyan
  Check 'local Char var C.IdxBlank has a member-access ref' ((Sel 'uIdxLocal' 'IdxBlank' 'member-access' 15).Count -eq 1)
  Check 'A[I].IdxMethod; is exactly one call' ((Sel 'uIdxIndexed' 'IdxMethod' 'call' 49).Count -eq 1)
  Check 'A[I].IdxMethod(); is exactly one call' ((Sel 'uIdxIndexed' 'IdxMethod' 'call' 50).Count -eq 1)
  Check 'R.IdxField keeps its member-access ref' ((Sel 'uIdxIndexed' 'IdxField' 'member-access' 53).Count -eq 1)

  Write-Host 'DEFECT -- member on an index-expression receiver:' -ForegroundColor Cyan
  $ws = Sel 'uIdxIndexed' 'IdxBlank' 'member-access' 38
  Check 'S[First].IdxBlank has ONE member-access ref' ($ws.Count -eq 1) "n=$($ws.Count)"
  Check '... with receiver text S[First]' ($ws.Count -eq 1 -and $ws[0].Rcv -eq 'S[First]') "rcv='$(if ($ws.Count) { $ws[0].Rcv })'"
  $lib = Sel 'uIdxLib' 'IsWhiteSpace' 'member-access' 16
  Check 'S[First].IsWhiteSpace (the exact INBOX shape) has ONE member-access ref' ($lib.Count -eq 1) "n=$($lib.Count)"
  Check 'A[I].IdxField:= 1 has ONE member-access ref' ((Sel 'uIdxIndexed' 'IdxField' 'member-access' 48).Count -eq 1)
  Check 'N:= A[0].IdxFn has ONE member-access ref' ((Sel 'uIdxIndexed' 'IdxFn' 'member-access' 51).Count -eq 1)
  Check 'A[I].IdxSub.IdxLeaf: IdxSub has ONE member-access ref' ((Sel 'uIdxIndexed' 'IdxSub' 'member-access' 52).Count -eq 1)
  Check 'A[I].IdxSub.IdxLeaf: IdxLeaf has ONE member-access ref' ((Sel 'uIdxIndexed' 'IdxLeaf' 'member-access' 52).Count -eq 1)

  Write-Host 'unused-unit-in-uses:' -ForegroundColor Cyan
  $out = (& $exePath lint-project --db $db --rule unused-unit-in-uses 2>$null | Out-String) -replace "`r`n", "`n"
  $hits = @($out -split "`n" | Where-Object { $_ -match 'unused-unit-in-uses' })
  Write-Host ("  findings:`n    " + ($hits -join "`n    ")) -ForegroundColor DarkGray
  Check 'CONTROL: uIdxDead (imports uIdxHelp, names nothing) IS flagged' (@($hits | Where-Object { $_ -match 'uIdxDead' -and $_ -match "'uIdxHelp'" }).Count -eq 1)
  Check 'CONTROL: uIdxLocal (helper on a local Char) is NOT flagged' (@($hits | Where-Object { $_ -match 'uIdxLocal' }).Count -eq 0)
  Check 'uIdxIndexed (helper on S[First]) is NOT flagged' (@($hits | Where-Object { $_ -match 'uIdxIndexed' }).Count -eq 0)
  Check 'uIdxLib: System.Character via S[First].IsWhiteSpace is NOT flagged' (@($hits | Where-Object { $_ -match 'uIdxLib' }).Count -eq 0)
} finally { Pop-Location; Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
