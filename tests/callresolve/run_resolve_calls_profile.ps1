<#
  run_resolve_calls_profile.ps1 -- 151 PF: the calls-stage profile switch DRAGLINT_PROFILE_CALLS
  and the two calls-stage costs it named (BindExternally's per-ref uses read, PersistArgUses'
  per-candidate refs query).

  CASES
    P1 switch ON : `resolve: calls      profile: stream main ... 1 entries` and a
       `stream arg-uses` line are printed, and TypeReceiverCore has > 0 entries (POSITIVE
       CONTROL: fails when the instrumentation is removed or the switch is not read)
    P2 switch OFF: no `profile:` line at all (OFF prints nothing)
    I1 identity  : call_edges, member_accesses, refs (id, symbol_id, receiver_text,
       external_target), ref_types, ref_receivers -- full sorted rows -- are byte-identical
       between the ON run and the OFF run (the switch only times, it never changes a row)
    A1 arg-uses  : the ON and OFF runs both store the var-arg of SetIt(B.FCount) and the
       out-arg of GetIt(B.FCount) and nothing for ByVal(B.FCount) -- PersistArgUses' per-file
       callee map reaches the same callee the per-candidate query did (positive: 2 stored)
  Rows are dumped with `sql --output` (text, every row), never `sql --json` (positional,
  capped at 200 rows by default).
  Usage: pwsh -File tests\callresolve\run_resolve_calls_profile.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_calls_profile_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function W($p, $t) { [IO.File]::WriteAllText($p, (($t -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII) }

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

W (Join-Path $WorkDir 'uVals.pas') @'
unit uVals;

interface

uses
  System.Classes;

type
  TBox = class
  public
    FCount: Integer;
    FList: TStringList;
  end;

procedure SetIt(var A: Integer);
procedure GetIt(out A: Integer);
procedure ByVal(A: Integer);

implementation

procedure SetIt(var A: Integer);
begin
  A := A + 1;
end;

procedure GetIt(out A: Integer);
begin
  A := 1;
end;

procedure ByVal(A: Integer);
begin
end;

end.
'@
W (Join-Path $WorkDir 'uUser.pas') @'
unit uUser;

interface

procedure Run;

implementation

uses
  uVals;

procedure Run;
var
  B: TBox;
begin
  B := TBox.Create;
  SetIt(B.FCount);
  GetIt(B.FCount);
  ByVal(B.FCount);
  B.FList.Add('x');
  B.Free;
end;

end.
'@
W (Join-Path $WorkDir 'ProfApp.dpr') @'
program ProfApp;

uses
  uVals in 'uVals.pas',
  uUser in 'uUser.pas';

begin
  Run;
end.
'@

$db = Join-Path $WorkDir 'p.sqlite'
$env:DRAGLINT_PROFILE_CALLS = $null
& $Exe index --project (Join-Path $WorkDir 'ProfApp.dpr') --db $db *> (Join-Path $WorkDir 'index.log')
if ($LASTEXITCODE -ne 0) { Write-Host "FATAL: index exit $LASTEXITCODE" -ForegroundColor Red; exit 2 }

function Resolve-Arm([string]$Tag, [bool]$On) {
  $d = Join-Path $WorkDir "$Tag.sqlite"
  Copy-Item $db $d -Force
  $env:DRAGLINT_PROFILE_CALLS = if ($On) { '1' } else { $null }
  & $Exe index --project (Join-Path $WorkDir 'ProfApp.dpr') --db $d --resolve-only *> (Join-Path $WorkDir "$Tag.log")
  $ec = $LASTEXITCODE
  $env:DRAGLINT_PROFILE_CALLS = $null
  if ($ec -ne 0) { Write-Host "FATAL: resolve-only ($Tag) exit $ec" -ForegroundColor Red; exit 2 }
  return $d
}
$dbOn  = Resolve-Arm 'on'  $true
$dbOff = Resolve-Arm 'off' $false
$logOn  = [IO.File]::ReadAllLines((Join-Path $WorkDir 'on.log'))
$logOff = [IO.File]::ReadAllLines((Join-Path $WorkDir 'off.log'))

$main = @($logOn | Where-Object { $_ -match 'calls      profile: stream main\s+[\d.]+ s\s+1 entries' })
$argu = @($logOn | Where-Object { $_ -match 'calls      profile: stream arg-uses\s' })
$trc  = @($logOn | Where-Object { $_ -match 'calls      profile: TypeReceiverCore\s+[\d.]+ s\s+(\d+) entries' })
$trcN = if ($trc.Count -eq 1 -and $trc[0] -match '\s(\d+) entries') { [int64]$Matches[1] } else { 0 }
Check 'P1' (($main.Count -eq 1) -and ($argu.Count -eq 1) -and ($trcN -gt 0)) "(main $($main.Count), arg-uses $($argu.Count), TypeReceiverCore entries $trcN)"
$offProf = @($logOff | Where-Object { $_ -match 'profile:' })
Check 'P2' ($offProf.Count -eq 0) "(profile lines with the switch off: $($offProf.Count))"

$qs = [ordered]@{
  call_edges      = 'SELECT ref_id, target_symbol_id, confidence, receiver_type_symbol_id FROM call_edges ORDER BY ref_id'
  member_accesses = 'SELECT ref_id, member_symbol_id, mode, accessor_symbol_id, accessor_kind, receiver_type_symbol_id FROM member_accesses ORDER BY ref_id'
  refs            = 'SELECT id, symbol_id, receiver_text, external_target FROM refs ORDER BY id'
  ref_types       = 'SELECT ref_id, type_symbol_id, type_qname, via FROM ref_types ORDER BY ref_id'
  ref_receivers   = 'SELECT ref_id, receiver_ref_id FROM ref_receivers ORDER BY ref_id'
}
$diff = @()
$rowsTotal = 0
foreach ($k in $qs.Keys) {
  $a = Join-Path $WorkDir "on.$k.txt"
  $b = Join-Path $WorkDir "off.$k.txt"
  & $Exe sql --db $dbOn  --query $qs[$k] --limit 100000000 --output $a *> $null
  & $Exe sql --db $dbOff --query $qs[$k] --limit 100000000 --output $b *> $null
  # the trailing "N row(s) in M ms" line carries a timing: compare the rows only
  $ra = @([IO.File]::ReadAllLines($a) | Where-Object { $_ -notmatch '^\d+ row\(s\) in ' })
  $rb = @([IO.File]::ReadAllLines($b) | Where-Object { $_ -notmatch '^\d+ row\(s\) in ' })
  $rowsTotal += $ra.Count
  if (($ra -join "`n") -ne ($rb -join "`n")) { $diff += $k }
}
Check 'I1' (($diff.Count -eq 0) -and ($rowsTotal -gt 10)) "(tables differing: $($diff -join ',') ; dumped lines $rowsTotal)"

$q = "SELECT r.start_line, ma.accessor_kind FROM member_accesses ma JOIN refs r ON r.id = ma.ref_id JOIN files f ON f.id = r.file_id WHERE f.path LIKE '%uUser.pas' AND r.name_text = 'FCount' ORDER BY r.start_line"
$ka = Join-Path $WorkDir 'on.kinds.txt'
$kb = Join-Path $WorkDir 'off.kinds.txt'
& $Exe sql --db $dbOn  --query $q --limit 1000 --output $ka *> $null
& $Exe sql --db $dbOff --query $q --limit 1000 --output $kb *> $null
foreach ($pair in @(@('on', $ka), @('off', $kb))) {
  $t = [IO.File]::ReadAllText($pair[1])
  $v = [regex]::IsMatch($t, '(?m)^17\s+var-arg\s*$')
  $o = [regex]::IsMatch($t, '(?m)^18\s+out-arg\s*$')
  $n = [regex]::IsMatch($t, '(?m)^19\s+NULL\s*$')
  Check "A1-$($pair[0])" ($v -and $o -and $n) "(line 17 var-arg $v, line 18 out-arg $o, line 19 NULL $n)"
}

if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
} finally {
  $env:DRAGLINT_PROFILE_CALLS = $null
}
