<#
  run_v152_BK-USEEDGES_used_in_args.ps1 -- E-USE-EDGES-PHASE2 close-out (1.52 lane BK-USEEDGES).

  Phase 2 of docs\superpowers\specs\2026-09-14-use-edges-design.md shipped in waves 147/148
  (member_accesses with mode + accessor echo, 'Used in:' / 'Used in (via property X):' in
  autodoc and hover). Two things were still open against the spec's test plan (sec 10):

   (a) 'Used in:' disagreed with `usages --rw` on an Inc/Dec or var/out ARGUMENT: the index
       stores such a site as a read, `usages --rw` lists it as a writer (inc-dec, out-arg) or
       a reader AND writer (var-arg), but 'Used in:' printed [r]. The fix folds the same
       argument classification into 'Used in:' (Doc.Facts), so both surfaces agree.
   (b) T2 / T4 / T6 had no guard: an indexed property write, a property with no setter /
       no getter, two classes sharing a property name, an unresolvable receiver.

  CHECKS
    1  POSITIVE CONTROL / fixture health: the plain read in ReadIt renders 'Used in: ...
       ReadIt (uC.pas) [r]' on field Cnt, and the Inc site owns a member_accesses row with
       mode read (FATAL exit 2 when not: the guard would test nothing)
    2  Inc(FA.Cnt) in IncIt: 'Used in:' says IncIt [w]                       (RED before)
    3  Bump(FA.Cnt) (var parameter) in VarIt: [rw]                          (RED before)
    4  Take(FA.Cnt) (out parameter) in OutIt: [w]                           (RED before)
    5  NEGATIVE: Show(FA.Cnt) (const parameter) in ConstIt stays [r]
    6  agreement: the writers `usages --rw --name Cnt` lists are exactly the 'Used in:'
       entries carrying w                                                  (RED before)
    7  T2: `FA.Items[0] := 1` is mode write with accessor SetItem (method) and a call edge
       to SetItem; `L := FA.Items[1]` is a read through GetItem
    8  T6: a write of the setter-less RO is mode write with NO accessor; a read of the
       getter-less WO is mode read with NO accessor
    9  T4 (negative): `B := FA.Flag` binds TAlpha.Flag; TBeta.Flag (same name, other
       class) owns no member_accesses row; `FU.Flag` (receiver of an unknown type) binds
       nothing while `usages --name Flag` still lists it by name

  Line numbers are located by `{ Xn }` anchors, never hard-coded.
  Usage: pwsh -File tests\autotest\run_v152_BK-USEEDGES_used_in_args.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = '')
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }
. (Join-Path $PSScriptRoot 'exe-hint.ps1')
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check([string]$n, [bool]$ok, [string]$d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $(if ($ok) { '' } else { $d })) -ForegroundColor $c
  if (-not $ok) { $script:fail = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: engine not found: $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP ("draglint_used_in_args-{0}" -f $PID)
if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory $scratch | Out-Null

function W([string]$name, [string]$body) {
  [IO.File]::WriteAllText((Join-Path $scratch $name), ($body -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
}
function LineOf([string]$path, [string]$anchor) {
  $lines = [IO.File]::ReadAllText($path) -split "`r`n"
  $hits = @(); for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Contains($anchor)) { $hits += ($i + 1) } }
  if ($hits.Count -ne 1) { Write-Host "FATAL: anchor '$anchor' matched $($hits.Count) lines -- broken FIXTURE" -ForegroundColor Red; exit 2 }
  return $hits[0]
}
# sql --json rows are POSITIONAL arrays: map them onto columns[].name.
function Sql([string]$db, [string]$q) {
  $j = (& { $ErrorActionPreference = 'Continue'; & $exePath sql --db $db --query $q --json 2>$null }) -join "`n"
  try { $o = $j | ConvertFrom-Json } catch { return ,@() }
  $cols = @($o.columns | ForEach-Object { $_.name }); $out = @()
  foreach ($r in @($o.rows)) { $h = [ordered]@{}; for ($i = 0; $i -lt $cols.Count; $i++) { $h[$cols[$i]] = @($r)[$i] }; $out += [pscustomobject]$h }
  return ,$out
}
# The member-access ref named $name at $line of uC.pas, with its member_accesses row (if any).
function Site([string]$db, [int]$line, [string]$name) {
  return Sql $db ("SELECT s.qualified_name AS qn, ma.mode AS mode, a.name AS acc, ma.accessor_kind AS ak, " +
                  "(SELECT t.name FROM call_edges ce JOIN symbols t ON t.id = ce.target_symbol_id WHERE ce.ref_id = r.id) AS edge " +
                  "FROM refs r JOIN files f ON f.id = r.file_id LEFT JOIN symbols s ON s.id = r.symbol_id " +
                  "LEFT JOIN member_accesses ma ON ma.ref_id = r.id LEFT JOIN symbols a ON a.id = ma.accessor_symbol_id " +
                  "WHERE f.path LIKE '%\uC.pas' AND r.start_line = {0} AND r.kind = 'member-access' AND r.name_text = '{1}'" -f $line, $name)
}
# The 'Used in:' line of the md hover of $qname ('' when none).
function UsedIn([string]$db, [string]$qname) {
  $md = (& { $ErrorActionPreference = 'Continue'; & $exePath hover --qname $qname --db $db --format md 2>$null }) -join "`n"
  $m = [regex]::Match($md, '(?m)^.*Used in: .*$')
  return $(if ($m.Success) { $m.Value } else { '' })
}
function Entry([string]$line, [string]$routine) {
  $m = [regex]::Match($line, [regex]::Escape("uC.TUser.$routine (uC.pas) [") + '(r|w|rw)\]')
  return $(if ($m.Success) { $m.Groups[1].Value } else { '' })
}

try {
  W 'uP.pas' @'
unit uP;

interface

type
  TAlpha = class
  private
    FFlag: Boolean;
    FRO: Integer;
    function GetItem(pI: Integer): Integer;
    procedure SetItem(pI: Integer; const pV: Integer);
    procedure SetWO(const pV: Integer);
  public
    Cnt: Integer;
    property Flag: Boolean read FFlag write FFlag;
    property RO: Integer read FRO;
    property WO: Integer write SetWO;
    property Items[pI: Integer]: Integer read GetItem write SetItem;
  end;

  TBeta = class
  private
    FFlag: Boolean;
  public
    property Flag: Boolean read FFlag write FFlag;
  end;

procedure Bump(var pV: Integer);
procedure Take(out pV: Integer);
procedure Show(const pV: Integer);

implementation

function TAlpha.GetItem(pI: Integer): Integer;
begin
  Result := pI;
end;

procedure TAlpha.SetItem(pI: Integer; const pV: Integer);
begin
end;

procedure TAlpha.SetWO(const pV: Integer);
begin
end;

procedure Bump(var pV: Integer);
begin
  pV := pV + 1;
end;

procedure Take(out pV: Integer);
begin
  pV := 0;
end;

procedure Show(const pV: Integer);
begin
end;

end.
'@
  W 'uC.pas' @'
unit uC;

interface

uses uP;

type
  TUser = class
  private
    FA: TAlpha;
    FU: TNoSuchType;
  public
    procedure ReadIt;
    procedure IncIt;
    procedure VarIt;
    procedure OutIt;
    procedure ConstIt;
    procedure Props;
  end;

implementation

procedure TUser.ReadIt;
var
  L: Integer;
begin
  L := FA.Cnt; { R1 }
end;

procedure TUser.IncIt;
begin
  Inc(FA.Cnt); { I1 }
end;

procedure TUser.VarIt;
begin
  Bump(FA.Cnt); { V1 }
end;

procedure TUser.OutIt;
begin
  Take(FA.Cnt); { O1 }
end;

procedure TUser.ConstIt;
begin
  Show(FA.Cnt); { K1 }
end;

procedure TUser.Props;
var
  L: Integer;
  B: Boolean;
begin
  FA.Items[0] := 1; { P1 }
  L := FA.Items[1]; { P2 }
  FA.RO := 2; { P3 }
  L := FA.WO; { P4 }
  B := FA.Flag; { P5 }
  B := FU.Flag; { P6 }
end;

end.
'@
  $fC = Join-Path $scratch 'uC.pas'
  $I1 = LineOf $fC '{ I1 '; $P1 = LineOf $fC '{ P1 '; $P2 = LineOf $fC '{ P2 '; $P3 = LineOf $fC '{ P3 '
  $P4 = LineOf $fC '{ P4 '; $P5 = LineOf $fC '{ P5 '; $P6 = LineOf $fC '{ P6 '
  $db = Join-Path $scratch 'p.sqlite'
  & { $ErrorActionPreference = 'Continue'; & $exePath index $scratch --db $db *> (Join-Path $scratch 'index.log') }
  if ($LASTEXITCODE -ne 0) { $hint = Get-ExeStartFailureHint $LASTEXITCODE; if ($hint) { Write-Host "FATAL: $hint" -ForegroundColor Red }; Write-Host "FATAL: index exit $LASTEXITCODE" -ForegroundColor Red; exit 2 }

  Write-Host '== check 1: POSITIVE CONTROL ==' -ForegroundColor Cyan
  $used = UsedIn $db 'uP.TAlpha.Cnt'
  $inc = Site $db $I1 'Cnt'
  $ok = ((Entry $used 'ReadIt') -eq 'r') -and (@($inc).Count -eq 1) -and ($inc[0].qn -eq 'uP.TAlpha.Cnt') -and ($inc[0].mode -eq 'read')
  Check '1 ReadIt [r] rendered; Inc site stored as a read of uP.TAlpha.Cnt' $ok ("used='$used' inc=" + ($inc | ConvertTo-Json -Compress))
  if (-not $ok) { Write-Host 'FATAL: fixture does not exercise the defect' -ForegroundColor Red; exit 2 }

  Write-Host '== checks 2-6: Used in folds Inc/Dec and var/out arguments ==' -ForegroundColor Cyan
  Check '2 Inc(FA.Cnt): IncIt [w]' ((Entry $used 'IncIt') -eq 'w') $used
  Check '3 Bump(FA.Cnt) var: VarIt [rw]' ((Entry $used 'VarIt') -eq 'rw') $used
  Check '4 Take(FA.Cnt) out: OutIt [w]' ((Entry $used 'OutIt') -eq 'w') $used
  Check '5 NEGATIVE Show(FA.Cnt) const: ConstIt [r]' ((Entry $used 'ConstIt') -eq 'r') $used
  $rw = (& { $ErrorActionPreference = 'Continue'; & $exePath usages --name Cnt --rw --db $db --json 2>$null }) -join "`n"
  $s0 = $rw.IndexOf('{'); $e0 = $rw.LastIndexOf('}'); $doc = $null
  if ($s0 -ge 0 -and $e0 -gt $s0) { try { $doc = $rw.Substring($s0, $e0 - $s0 + 1) | ConvertFrom-Json } catch { $doc = $null } }
  $writers = @(@($doc.targets) | ForEach-Object { @($_.writers) } | ForEach-Object { ([string]$_.caller -split '\.')[-1] } | Sort-Object -Unique)
  $wIn = @('ReadIt', 'IncIt', 'VarIt', 'OutIt', 'ConstIt') | Where-Object { (Entry $used $_) -match 'w' } | Sort-Object -Unique
  Check '6 usages --rw writers == Used in w entries' (($writers.Count -gt 0) -and (($writers -join ',') -eq ($wIn -join ','))) ("rw=[" + ($writers -join ',') + "] usedin=[" + ($wIn -join ',') + "]")

  Write-Host '== checks 7-9: spec T2 / T6 / T4 ==' -ForegroundColor Cyan
  $r1 = Site $db $P1 'Items'; $r2 = Site $db $P2 'Items'
  Check '7 T2 Items[0] := 1 write via SetItem; Items[1] read via GetItem' ((@($r1).Count -eq 1) -and ($r1[0].mode -eq 'write') -and ($r1[0].acc -eq 'SetItem') -and ($r1[0].ak -eq 'method') -and ($r1[0].edge -eq 'SetItem') -and (@($r2).Count -eq 1) -and ($r2[0].mode -eq 'read') -and ($r2[0].acc -eq 'GetItem')) (($r1 + $r2) | ConvertTo-Json -Compress)
  $r3 = Site $db $P3 'RO'; $r4 = Site $db $P4 'WO'
  Check '8 T6 RO write / WO read: moded, no accessor' ((@($r3).Count -eq 1) -and ($r3[0].qn -eq 'uP.TAlpha.RO') -and ($r3[0].mode -eq 'write') -and (-not $r3[0].acc) -and (@($r4).Count -eq 1) -and ($r4[0].qn -eq 'uP.TAlpha.WO') -and ($r4[0].mode -eq 'read') -and (-not $r4[0].acc)) (($r3 + $r4) | ConvertTo-Json -Compress)
  $r5 = Site $db $P5 'Flag'; $r6 = Site $db $P6 'Flag'
  $beta = Sql $db "SELECT COUNT(*) AS n FROM member_accesses ma JOIN symbols s ON s.id = ma.member_symbol_id WHERE s.qualified_name = 'uP.TBeta.Flag'"
  $pj = $null; try { $pj = ((& { $ErrorActionPreference = 'Continue'; & $exePath usages --name Flag --db $db --json 2>$null }) -join "`n") | ConvertFrom-Json } catch { $pj = $null }
  $byName = @(@($pj.reads) + @($pj.writes) + @($pj.calls) | Where-Object { $_ -and ([string]$_.file).EndsWith('\uC.pas') -and [int]$_.line -eq $P6 -and $_.resolution -eq 'name-only' }).Count -eq 1
  Check '9 T4 A.Flag binds TAlpha only; TBeta.Flag unused; FU.Flag unbound but name-listed' ((@($r5).Count -eq 1) -and ($r5[0].qn -eq 'uP.TAlpha.Flag') -and ($r5[0].mode -eq 'read') -and ([int]$beta[0].n -eq 0) -and (@($r6).Count -eq 1) -and (-not $r6[0].qn) -and (-not $r6[0].mode) -and $byName) ("r5=" + ($r5 | ConvertTo-Json -Compress) + " beta=" + $beta[0].n + " r6=" + ($r6 | ConvertTo-Json -Compress) + " byName=$byName")
}
finally {
  if (Test-Path $scratch) { try { [IO.Directory]::Delete($scratch, $true) } catch { } }
}
if ($script:fail) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
