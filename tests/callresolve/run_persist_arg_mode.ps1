<#
  run_persist_arg_mode.ps1 -- 150-RS2 (2) / 150-RB2-a: the var / out ARGUMENT use of a
  member access is persisted by the calls pass (member_accesses.accessor_kind = 'var-arg' /
  'out-arg', mode stays 'read'), and `usages --rw` reads it.
  Spec: docs\superpowers\specs\2026-11-09-persist-arg-mode.md (option B).

  CASES (markers in uUser.pas)
    V1 SetIt(B.FCount)        var parameter      -> accessor_kind var-arg
    O1 GetIt(B.FCount)        out parameter      -> out-arg
    V2 SetIt(GVal)            var, unit var      -> var-arg
    O2 GetIt(uVals.GVal)      out, unit-qualified-> out-arg
    C1 ByVal(B.FCount)        by value           -> NULL (CONTROL)
    I1 Inc(B.FCount)          Inc                -> NULL (Inc/Dec stays read-time, text only)
    U1 usages --rw FCount: writers carry var-arg (V1), out-arg (O1), inc-dec (I1); readers carry V1
       (read+write) and C1 -- the read-time answer of 1.49, unchanged (identity)
    U2 STORED, not re-derived: the V1 line is rewritten AFTER the index (`SetIt(B.FCount)` ->
       `SetIt(B.FCount+0)`, columns kept): the read-time classifier says "no whole argument";
       the stored mode still lists V1 as a var-arg writer. (RED on 1.49 by construction.)
  `sql --json` rows are POSITIONAL arrays; Sql() maps them onto column names.
  Usage: pwsh -File tests\callresolve\run_persist_arg_mode.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_arg_mode_$PID"
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
function W($p,$t){ [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

W (Join-Path $WorkDir 'uVals.pas') @'
unit uVals;

interface

type
  TBox = class
  public
    FCount: Integer;
  end;

var
  GVal: Integer;

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
$userText = @'
unit uUser;

interface

procedure Work;

implementation

uses
  uVals;

procedure Work;
var
  B: TBox;
begin
  B := TBox.Create;
  SetIt(B.FCount); // V1
  GetIt(B.FCount); // O1
  SetIt(GVal); // V2
  GetIt(uVals.GVal); // O2
  ByVal(B.FCount); // C1
  Inc(B.FCount); // I1
  B.Free;
end;

end.
'@
W (Join-Path $WorkDir 'uUser.pas') $userText
W (Join-Path $WorkDir 'App.dpr') @'
program App;

uses
  uVals in 'uVals.pas',
  uUser in 'uUser.pas';

begin
  Work;
end.
'@

$db = Join-Path $WorkDir 'App.sqlite'
Push-Location C:\TEMP
try {
& $Exe index --project (Join-Path $WorkDir 'App.dpr') --db $db 2>&1 | Out-Null
Check 'V the fixture index was built' (Test-Path $db) $db

function Sql([string]$Q) {
  $j = & $Exe sql --db $db --json --limit 1000 --query $Q 2>$null | ConvertFrom-Json
  if ($null -eq $j) { return ,@() }
  $cols = @($j.columns | ForEach-Object { $_.name })
  $out = @()
  foreach ($row in $j.rows) {
    $o = [ordered]@{}
    for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $row[$i] }
    $out += [pscustomobject]$o
  }
  return ,$out
}
$lines = [IO.File]::ReadAllLines((Join-Path $WorkDir 'uUser.pas'))
function LineOf([string]$Marker) { for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match ('// ' + $Marker + '$')) { return $i + 1 } }; return -1 }
function KindAt([string]$Marker, [string]$Name) {
  $ln = LineOf $Marker
  return ,(Sql ("SELECT ma.mode AS m, ma.accessor_kind AS k FROM member_accesses ma JOIN refs r ON r.id = ma.ref_id " +
                "JOIN files f ON f.id = r.file_id WHERE r.name_text = '$Name' AND r.start_line = $ln AND f.path LIKE '%\uUser.pas'"))
}
foreach ($c in @(@('V1','FCount','var-arg'), @('O1','FCount','out-arg'), @('V2','GVal','var-arg'), @('O2','GVal','out-arg'),
                 @('C1','FCount',$null), @('I1','FCount',$null))) {
  $r = KindAt $c[0] $c[1]
  $ok = ($r.Count -eq 1) -and ($r[0].m -eq 'read') -and ($r[0].k -eq $c[2])
  Check ("{0}  {1} stored accessor_kind = {2}" -f $c[0], $c[1], $(if ($c[2]) { $c[2] } else { 'NULL' })) $ok ("rows=$($r.Count) mode=$($r[0].m) kind=$($r[0].k)")
}

function UsagesRw([string]$Name) {
  $raw = & $Exe usages --name $Name --rw --json --db $db 2>$null | Out-String
  return $raw
}
function ArgsOf($json, [string]$Side) {
  $o = $json | ConvertFrom-Json
  $rows = @()
  foreach ($t in @($o.targets)) { foreach ($r in @($t.$Side)) { $rows += ("{0}:{1}" -f $r.line, $r.arg) } }
  return ($rows | Sort-Object) -join ' '
}
$u1 = UsagesRw 'FCount'
[IO.File]::WriteAllText((Join-Path $WorkDir 'usages-FCount.json'), $u1)
[IO.File]::WriteAllText((Join-Path $WorkDir 'usages-GVal.json'), (UsagesRw 'GVal'))
$w = ArgsOf $u1 'writers'; $rd = ArgsOf $u1 'readers'
$want = @("$(LineOf 'V1'):var-arg", "$(LineOf 'O1'):out-arg", "$(LineOf 'I1'):inc-dec") | Sort-Object
Check 'U1  usages --rw FCount writers: V1 var-arg, O1 out-arg, I1 inc-dec' (@($want | Where-Object { $w -notmatch ([regex]::Escape($_)) }).Count -eq 0) "writers=[$w] readers=[$rd]"
Check 'U1  usages --rw FCount readers hold V1 (var-arg) and C1' (($rd -match ([regex]::Escape("$(LineOf 'V1'):var-arg"))) -and ($rd -match ("(^| )$(LineOf 'C1'):"))) "readers=[$rd]"

# U2: rewrite the V1 site AFTER the index, columns kept up to the argument -- the read-time
# classifier no longer sees a whole argument, the stored mode does.
$ln = LineOf 'V1'
$lines[$ln - 1] = $lines[$ln - 1].Replace('SetIt(B.FCount);', 'SetIt(B.FCount+0);')
[IO.File]::WriteAllText((Join-Path $WorkDir 'uUser.pas'), (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
$u2 = UsagesRw 'FCount'
$w2 = ArgsOf $u2 'writers'
Check 'U2  STORED: after the V1 line is rewritten (no reindex), usages --rw still lists V1 as a var-arg writer' ($w2 -match ([regex]::Escape("${ln}:var-arg"))) "writers=[$w2]"
} finally { Pop-Location }

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} catch {
  Write-Host "FATAL: $_" -ForegroundColor Red
  exit 2
}
