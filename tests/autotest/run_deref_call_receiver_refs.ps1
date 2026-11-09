<#
  run_deref_call_receiver_refs.ps1 -- wave 149 EX1 item (2), 145 gaps e.

  A member read through a POSTFIX DEREFERENCE of a call receiver had no ref
  row: `X := F()^.M`, `X := G(1, 2)^.N`, `X := PRec(P)^.K`. The G5
  (IsHardCastRootedReceiver) and G6 (IsCallRootedReceiver) rungs took the call
  and the dotted chain rooted in it, not an exprUnary `^` around it, so M / N / K
  were invisible to find-callers, ref_types and unused-public-symbol.
  Fix: both predicates look through a postfix deref (IsPostfixDeref), so each
  shape still answers to exactly ONE rung.

  RED on drag-lint 1.48.0-alpha: lines 37-39 carry no M / N / K row.
  POSITIVE CONTROL: `X := F().L` (G6 without the deref) has its row on the
  base engine too -- the guard fails if the rung or the query is broken.
  NO-DUPLICATE: each member exactly one row (a second rung firing = E1 shape).
  Run from a NEUTRAL CWD. pwsh 7.
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

$exePath = (Resolve-Path $Exe).Path
$work = Join-Path $env:TEMP ('draglint_deref_call_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($work) | Out-Null
$db = Join-Path $work 'deref.sqlite'
$pas = Join-Path $work 'uDerefCall.pas'

$unit = @'
unit uDerefCall;

interface

type
  PRec = ^TRec;
  TRec = record
    M: Integer;
    N: Integer;
    K: Integer;
    L: Integer;
  end;

function F: PRec;
function G(A, B: Integer): PRec;
procedure Run(P: Pointer);

implementation

var
  R: TRec;

function F: PRec;
begin
  Result := @R;
end;

function G(A, B: Integer): PRec;
begin
  Result := @R;
end;

procedure Run(P: Pointer);
var
  X: Integer;
begin
  X := F()^.M;
  X := G(1, 2)^.N;
  X := PRec(P)^.K;
  X := F().L;
  if X = 0 then;
end;

end.
'@
[IO.File]::WriteAllText($pas, ($unit -replace "`r?`n", "`r`n"))

& $exePath index $work --db $db 2>&1 | Out-Null
Check 'index' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

# sql --json rows are POSITIONAL arrays: name_text, kind, start_line, receiver_text
$q = "select name_text, kind, start_line, receiver_text from refs where name_text in ('M','N','K','L') order by start_line, start_col"
$rows = @((& $exePath sql --query $q --db $db --json 2>$null | ConvertFrom-Json).rows)
$got = ($rows | ForEach-Object { '{0}:{1}:{2}:{3}' -f $_[0], $_[1], $_[2], $_[3] }) -join ' '
Write-Host "  rows: $got"
Check 'positive control F().L (G6) has one row' (@($rows | Where-Object { $_[0] -eq 'L' -and $_[2] -eq 40 }).Count -eq 1)
Check 'F()^.M emits one member-access' (@($rows | Where-Object { $_[0] -eq 'M' -and $_[1] -eq 'member-access' -and $_[2] -eq 37 }).Count -eq 1)
Check 'G(1, 2)^.N emits one member-access' (@($rows | Where-Object { $_[0] -eq 'N' -and $_[1] -eq 'member-access' -and $_[2] -eq 38 }).Count -eq 1)
Check 'PRec(P)^.K emits one member-access (G5 rung)' (@($rows | Where-Object { $_[0] -eq 'K' -and $_[1] -eq 'member-access' -and $_[2] -eq 39 }).Count -eq 1)
Check 'no duplicate rows (4 total)' ($rows.Count -eq 4)
Check 'receiver text keeps the deref' (@($rows | Where-Object { $_[3] -eq 'F()^' }).Count -eq 1)

try { [IO.Directory]::Delete($work, $true) } catch { Write-Host "  (scratch kept: $work)" }
if ($script:Failed) { Write-Host 'run_deref_call_receiver_refs: FAIL'; exit 1 }
Write-Host 'run_deref_call_receiver_refs: PASS'
exit 0
