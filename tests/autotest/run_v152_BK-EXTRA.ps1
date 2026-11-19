<#
  run_v152_BK-EXTRA.ps1 -- 1.52 lane BK-EXTRA (backlog B08 / B09 / B12).

  B08  noreturn fact: symbols.directives carries 'noreturn' for a free routine, a second
       one and a class static method (delivered by extractor 1.39, lane EXT). Guard only:
       the noreturn-returns RULE is not added, dcc already reports it (W1080), the
       compiler-messages.md:46 policy.
  B09  attributes table (owner ruling 2026-11-18): one row per custom attribute, with the
       attribute name, the argument text inside the parentheses ('' when bare), its line /
       col and the symbol it decorates (class, field, method, param, free routine,
       property; every name of a multi-name field). Written with or without usage refs.
  B12  ref_receivers for a DEREFERENCED receiver: F()^.M, G(1, 2)^.N (spaced args),
       P^.M and F^.N link the member ref to the ref of F / G / P.
       POSITIVE CONTROL: F().L (no deref) has its row on the base engine too.

  `sql --json` rows are POSITIONAL arrays; Sql() maps them onto column names.
  Usage: pwsh -File tests\autotest\run_v152_BK-EXTRA.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "C:\TEMP\draglint_bkextra_$PID"
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Pass = 0; $script:Fail = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if ($ok) { $script:Pass++ } else { $script:Fail++; $script:Failed = $true }
}
function W($p, $t) { [IO.File]::WriteAllText($p, (($t -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII) }
function Sql($db, $q) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $Exe sql --db $db --json --query $q 2>$null }
  $doc = ($raw -join "`n") | ConvertFrom-Json | ForEach-Object { $_ }
  $cols = @($doc.columns | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } })
  $out = foreach ($r in @($doc.rows)) {
    $h = [ordered]@{}
    for ($i = 0; $i -lt $cols.Count; $i++) { $h[$cols[$i]] = $r[$i] }
    [pscustomobject]$h
  }
  return , @($out)
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $src | Out-Null

W (Join-Path $src 'uAttr.pas') @'
unit uAttr;

interface

uses System.SysUtils;

type
  EImport = class(Exception);

  [ComponentPlatforms($FFFF)]
  TFoo = class
  private
    [Weak] FOwner: TObject;
    [Weak] F1, F2: TObject;
    function GetV: Integer;
  public
    [Deprecated('x')]
    procedure Bar(const [Ref] A: Integer); virtual;
    [A1, A2('q', 2)]
    procedure Baz;
    [S1]
    [S2(1)]
    property V: Integer read GetV;
    class procedure Die; static; noreturn;
  end;

procedure Fail(const AText: string); noreturn;
procedure Fail2; noreturn;
[Hidden]
procedure Plain;

implementation

function TFoo.GetV: Integer;
begin
  Result:= 0;
end;

procedure Fail(const AText: string);
begin
  if AText <> '' then
    raise EImport.Create(AText);
end;

procedure Fail2;
begin
  Halt(1);
end;

procedure Plain;
begin
end;

procedure TFoo.Bar(const [Ref] A: Integer);
begin
end;

procedure TFoo.Baz;
begin
end;

class procedure TFoo.Die;
begin
  Fail('x');
end;

end.
'@

W (Join-Path $src 'uDr.pas') @'
unit uDr;

interface

type
  TRec = record
    M: Integer;
    N: Integer;
    L: Integer;
  end;
  PRec = ^TRec;

function F: PRec;
function G(A, B: Integer): PRec;
procedure Use;

implementation

var
  R: TRec;

function F: PRec;
begin
  Result:= @R;
end;

function G(A, B: Integer): PRec;
begin
  Result:= @R;
end;

procedure Use;
var
  X: Integer;
  P: PRec;
begin
  P:= F;
  X:= F()^.M;
  X:= G(1, 2)^.N;
  X:= P^.M;
  X:= F^.N;
  X:= F().L;
end;

end.
'@

$db = Join-Path $WorkDir 'bk.sqlite'
Push-Location $WorkDir
try { & { $ErrorActionPreference = 'Continue'; & $Exe index $src --db $db 2>&1 | ForEach-Object { "$_" } } | Out-Null } finally { Pop-Location }
Check 'index built' (Test-Path $db)

Write-Host 'B08 noreturn fact'
foreach ($q in 'uAttr.Fail', 'uAttr.Fail2', 'uAttr.TFoo.Die') {
  $r = Sql $db "SELECT directives FROM symbols WHERE qualified_name = '$q' AND kind <> 'param'"
  Check "B08 $q directives has noreturn" (($r.Count -ge 1) -and (" $($r[0].directives) " -match ' noreturn ')) "($($r[0].directives))"
}
$r = Sql $db "SELECT directives FROM symbols WHERE qualified_name = 'uAttr.Plain'"
Check 'B08 control: Plain has no noreturn' (($r.Count -eq 1) -and ("$($r[0].directives)" -notmatch 'noreturn'))

Write-Host 'B09 attributes table'
$t = Sql $db "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'attributes'"
Check 'B09 table attributes exists' ($t.Count -eq 1)
if ($t.Count -eq 1) {
  $rows = Sql $db ("SELECT a.attr_name, a.arg_text, a.line, a.col, s.qualified_name AS target, s.kind AS tkind " +
                   "FROM attributes a JOIN files f ON f.id = a.file_id LEFT JOIN symbols s ON s.id = a.symbol_id " +
                   "WHERE f.path LIKE '%uAttr.pas' ORDER BY a.line, a.col")
  function Has($name, $arg, $target) {
    @($rows | Where-Object { $_.attr_name -eq $name -and "$($_.arg_text)" -eq $arg -and $_.target -eq $target }).Count
  }
  Check 'B09 ComponentPlatforms -> TFoo, arg $FFFF' ((Has 'ComponentPlatforms' '$FFFF' 'uAttr.TFoo') -eq 1)
  Check 'B09 Weak -> FOwner'                ((Has 'Weak' '' 'uAttr.TFoo.FOwner') -eq 1)
  Check 'B09 Weak -> F1 and F2 (multi-name field)' (((Has 'Weak' '' 'uAttr.TFoo.F1') -eq 1) -and ((Has 'Weak' '' 'uAttr.TFoo.F2') -eq 1))
  Check "B09 Deprecated('x') -> Bar"        ((Has 'Deprecated' "'x'" 'uAttr.TFoo.Bar') -eq 1)
  Check 'B09 Ref -> param A of Bar (decl)'  ((Has 'Ref' '' 'uAttr.TFoo.Bar.A') -ge 1)
  Check 'B09 A1 -> Baz (list, bare)'        ((Has 'A1' '' 'uAttr.TFoo.Baz') -eq 1)
  Check "B09 A2('q', 2) -> Baz (list, args)" ((Has 'A2' "'q', 2" 'uAttr.TFoo.Baz') -eq 1)
  Check 'B09 S1 + S2(1) stacked -> property V' (((Has 'S1' '' 'uAttr.TFoo.V') -eq 1) -and ((Has 'S2' '1' 'uAttr.TFoo.V') -eq 1))
  Check 'B09 Hidden -> Plain'               ((Has 'Hidden' '' 'uAttr.Plain') -eq 1)
  $w = @($rows | Where-Object { $_.attr_name -eq 'Weak' -and $_.target -eq 'uAttr.TFoo.FOwner' })
  Check 'B09 Weak line/col = 13:6' (($w.Count -eq 1) -and ($w[0].line -eq 13) -and ($w[0].col -eq 6)) "($($w[0].line):$($w[0].col))"
  # every interface-section attribute has a target; the implementation header's [Ref] has none (no param symbol there)
  $implLine = 1 + [array]::IndexOf((Get-Content (Join-Path $src 'uAttr.pas')), 'implementation')
  $orphans = @($rows | Where-Object { -not $_.target -and $_.line -lt $implLine })
  Check 'B09 no interface attribute row without a target' ($orphans.Count -eq 0) "($(@($orphans | ForEach-Object { $_.attr_name }) -join ','))"
  Check 'B09 rows total = 12 (11 decl + impl-header Ref)' ($rows.Count -eq 12) "($($rows.Count))"
  # incremental reindex of a changed file replaces its rows (no duplicates)
  $p = Join-Path $src 'uAttr.pas'
  W $p ((Get-Content $p -Raw) -replace '\[Hidden\]', '[Hidden2]')
  Push-Location $WorkDir
  try { & { $ErrorActionPreference = 'Continue'; & $Exe index $src --db $db 2>&1 | ForEach-Object { "$_" } } | Out-Null } finally { Pop-Location }
  $h = Sql $db "SELECT attr_name FROM attributes WHERE attr_name LIKE 'Hidden%'"
  Check 'B09 reindex replaces rows (Hidden2 only)' (($h.Count -eq 1) -and ($h[0].attr_name -eq 'Hidden2')) "($(@($h | ForEach-Object { $_.attr_name }) -join ','))"
}

Write-Host 'B12 ref_receivers through a postfix deref'
$rr = Sql $db ("SELECT r.name_text AS member, r.start_line AS line, r.receiver_text AS rtext, v.name_text AS rcv, v.kind AS rkind " +
               "FROM refs r JOIN files f ON f.id = r.file_id LEFT JOIN ref_receivers x ON x.ref_id = r.id " +
               "LEFT JOIN refs v ON v.id = x.receiver_ref_id WHERE f.path LIKE '%uDr.pas' AND r.kind = 'member-access' ORDER BY r.start_line")
$lines = Get-Content (Join-Path $src 'uDr.pas')
function LineOf($needle) { for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Contains($needle)) { return $i + 1 } }; return -1 }
function RcvAt($needle) { $ln = LineOf $needle; @($rr | Where-Object { $_.line -eq $ln }) }
$c = RcvAt 'F().L';    Check 'B12 control F().L -> F'  (($c.Count -eq 1) -and ($c[0].rcv -eq 'F')) "($($c[0].rtext) -> $($c[0].rcv))"
$c = RcvAt 'F()^.M';   Check 'B12 F()^.M -> F'         (($c.Count -eq 1) -and ($c[0].rcv -eq 'F')) "($($c[0].rtext) -> $($c[0].rcv))"
$c = RcvAt 'G(1, 2)^'; Check 'B12 G(1, 2)^.N -> G'     (($c.Count -eq 1) -and ($c[0].rcv -eq 'G')) "($($c[0].rtext) -> $($c[0].rcv))"
$c = RcvAt 'P^.M';     Check 'B12 P^.M -> P'           (($c.Count -eq 1) -and ($c[0].rcv -eq 'P')) "($($c[0].rtext) -> $($c[0].rcv))"
$c = RcvAt 'F^.N';     Check 'B12 F^.N -> F'           (($c.Count -eq 1) -and ($c[0].rcv -eq 'F')) "($($c[0].rtext) -> $($c[0].rcv))"

if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
Write-Host ("run_v152_BK-EXTRA: {0} passed, {1} failed" -f $script:Pass, $script:Fail)
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
