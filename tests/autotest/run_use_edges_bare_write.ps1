<#
  run_use_edges_bare_write.ps1 -- E-USE-EDGES-PHASE2 (wave 147 lane B1): a BARE,
  `Self.`-qualified or `with`-scoped WRITE of a property or field records its use
  edge exactly as the read of the same member and the dotted write already do.

  THE DEFECT (measured on the deployed 1.46.0-alpha engine, 2026-11-07). The
  resolver binds a bare write `FFlag := True` / `Value := 5` / `Flag := False`
  (refs.kind 'write', D13) IDENTITY ONLY: refs.symbol_id, but no
  member_accesses row and no call_edges row. The bare READ of the same member
  (`if FFlag`, `L := Value`) and the dotted write (`FProv.Value := 3`) DO get a
  member_accesses row (mode, accessor) and, for a method accessor, a call edge.
  So `find-callers --name SetValue --resolved` misses every `Value := v` inside
  the class or a `with` body, and member_accesses carries reads but not writes
  for every own-class site.

  CHECKS
    1  POSITIVE CONTROL / fixture health: the bare READ B2 of FFlag owns a
       member_accesses row, mode read (green before the fix too: proves the
       guard reads the table; FATAL exit 2 when not)
    2  bare field write B1 `FFlag := True`: member_accesses mode write    (RED before)
    3  bare property write B3 `Value := 5`: mode write, accessor SetValue
       (method), and a call edge to SetValue                              (RED before)
    4  bare field-backed property write B5 `Flag := False`: mode write,
       accessor FFlag (field), no call edge                               (RED before)
    5  bare write of an INHERITED field B6 `FInh := L`                    (RED before)
    6  `Self.FFlag := False` B8                                            (RED before)
    7  `with FProv do Flag := True` C4: mode write, accessor FFlag        (RED before)
    8  NEGATIVE: the local write `L := 1` stays identity-only (no row), and
       every write ref keeps its refs.symbol_id
    9  find-callers --name SetValue --resolved: the dotted C2 (control) AND
       the bare B3 (RED before)
   10  find-callers --name Work --resolved is unchanged: exactly one caller
   11  usages --rw: FFlag lists each write site ONCE (no double row from the
       new member_accesses row beside the bound-usage arm); SetValue lists
       B3 and C2 once each

  Line numbers are located by `{ Xn }` anchors, never hard-coded.
  Usage: pwsh -File tests\autotest\run_use_edges_bare_write.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
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
$scratch = Join-Path C:\TEMP ("draglint_use_edges_bare_write-{0}" -f $PID)
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
  $j = (& $exePath sql --db $db --query $q --json 2>$null) -join "`n"
  try { $o = $j | ConvertFrom-Json } catch { return ,@() }
  $cols = @($o.columns | ForEach-Object { $_.name }); $out = @()
  foreach ($r in @($o.rows)) { $h = [ordered]@{}; for ($i = 0; $i -lt $cols.Count; $i++) { $h[$cols[$i]] = @($r)[$i] }; $out += [pscustomobject]$h }
  return ,$out
}
# The member_accesses row (or none) of the ONE write/read ref of a name at a line.
function Site([string]$db, [string]$file, [int]$line, [string]$kind, [string]$name) {
  return Sql $db ("SELECT s.qualified_name AS qn, ma.mode AS mode, a.name AS acc, ma.accessor_kind AS ak, " +
                  "(SELECT t.name FROM call_edges ce JOIN symbols t ON t.id = ce.target_symbol_id WHERE ce.ref_id = r.id) AS edge " +
                  "FROM refs r JOIN files f ON f.id = r.file_id LEFT JOIN symbols s ON s.id = r.symbol_id " +
                  "LEFT JOIN member_accesses ma ON ma.ref_id = r.id LEFT JOIN symbols a ON a.id = ma.accessor_symbol_id " +
                  "WHERE f.path LIKE '%\{0}' AND r.start_line = {1} AND r.kind = '{2}' AND r.name_text = '{3}'" -f $file, $line, $kind, $name)
}
function UsagesRw([string]$db, [string]$name) {
  $raw = (& $exePath usages --name $name --rw --db $db --json 2>$null) -join "`n"
  $s = $raw.IndexOf('{'); $e = $raw.LastIndexOf('}')
  if ($s -lt 0 -or $e -lt $s) { return $null }
  try { return ($raw.Substring($s, $e - $s + 1) | ConvertFrom-Json) } catch { return $null }
}
function CountAt($arr, [string]$file, [int]$line) {
  return @(@($arr) | Where-Object { $_ -and ([string]$_.path).EndsWith('\' + $file) -and [int]$_.line -eq $line }).Count
}

try {
  W 'uProv.pas' @'
unit uProv;

interface

type
  TBase = class
  protected
    FInh: Integer;
  end;

  TProvider = class(TBase)
  private
    FFlag: Boolean;
    FValue: Integer;
    function GetValue: Integer;
    procedure SetValue(const pV: Integer);
  public
    procedure Work;
    property Flag: Boolean read FFlag write FFlag;
    property Value: Integer read GetValue write SetValue;
  end;

implementation

function TProvider.GetValue: Integer;
begin
  Result := FValue;
end;

procedure TProvider.SetValue(const pV: Integer);
begin
  FValue := pV;
end;

procedure TProvider.Work;
var
  L: Integer;
begin
  FFlag := True; { B1 }
  if FFlag then { B2 }
    L := 1; { B9 }
  Value := 5; { B3 }
  L := Value;
  Flag := False; { B5 }
  FInh := L; { B6 }
  Self.FFlag := False; { B8 }
end;

end.
'@
  W 'uCons.pas' @'
unit uCons;

interface

uses uProv;

type
  TConsumer = class
  private
    FProv: TProvider;
  public
    procedure Go;
  end;

implementation

procedure TConsumer.Go;
begin
  FProv.Work;
  FProv.Value := 3; { C2 }
  with FProv do
    Flag := True; { C4 }
end;

end.
'@
  $fP = Join-Path $scratch 'uProv.pas'; $fC = Join-Path $scratch 'uCons.pas'
  $B1 = LineOf $fP '{ B1 '; $B2 = LineOf $fP '{ B2 '; $B3 = LineOf $fP '{ B3 '; $B5 = LineOf $fP '{ B5 '
  $B6 = LineOf $fP '{ B6 '; $B8 = LineOf $fP '{ B8 '; $B9 = LineOf $fP '{ B9 '
  $C2 = LineOf $fC '{ C2 '; $C4 = LineOf $fC '{ C4 '
  $db = Join-Path $scratch 'p.sqlite'
  & $exePath index $scratch --db $db *> (Join-Path $scratch 'index.log')
  if ($LASTEXITCODE -ne 0) { $hint = Get-ExeStartFailureHint $LASTEXITCODE; if ($hint) { Write-Host "FATAL: $hint" -ForegroundColor Red }; Write-Host "FATAL: index exit $LASTEXITCODE" -ForegroundColor Red; exit 2 }

  Write-Host '== check 1: POSITIVE CONTROL -- the bare read owns its row ==' -ForegroundColor Cyan
  $r = Site $db 'uProv.pas' $B2 'read' 'FFlag'
  $ok = (@($r).Count -eq 1) -and ($r[0].qn -eq 'uProv.TProvider.FFlag') -and ($r[0].mode -eq 'read')
  Check '1 bare read B2 FFlag: member_accesses mode read' $ok ($r | ConvertTo-Json -Compress)
  if (-not $ok) { Write-Host 'FATAL: fixture does not exercise the defect' -ForegroundColor Red; exit 2 }

  Write-Host '== checks 2-7: every write of a property/field records its use ==' -ForegroundColor Cyan
  $r = Site $db 'uProv.pas' $B1 'write' 'FFlag'
  Check '2 B1 FFlag := True: mode write, no accessor' ((@($r).Count -eq 1) -and ($r[0].qn -eq 'uProv.TProvider.FFlag') -and ($r[0].mode -eq 'write') -and (-not $r[0].acc)) ($r | ConvertTo-Json -Compress)
  $r = Site $db 'uProv.pas' $B3 'write' 'Value'
  Check '3 B3 Value := 5: mode write, accessor SetValue (method), call edge SetValue' ((@($r).Count -eq 1) -and ($r[0].qn -eq 'uProv.TProvider.Value') -and ($r[0].mode -eq 'write') -and ($r[0].acc -eq 'SetValue') -and ($r[0].ak -eq 'method') -and ($r[0].edge -eq 'SetValue')) ($r | ConvertTo-Json -Compress)
  $r = Site $db 'uProv.pas' $B5 'write' 'Flag'
  Check '4 B5 Flag := False: mode write, accessor FFlag (field), no edge' ((@($r).Count -eq 1) -and ($r[0].qn -eq 'uProv.TProvider.Flag') -and ($r[0].mode -eq 'write') -and ($r[0].acc -eq 'FFlag') -and ($r[0].ak -eq 'field') -and (-not $r[0].edge)) ($r | ConvertTo-Json -Compress)
  $r = Site $db 'uProv.pas' $B6 'write' 'FInh'
  Check '5 B6 inherited FInh := L: mode write' ((@($r).Count -eq 1) -and ($r[0].qn -eq 'uProv.TBase.FInh') -and ($r[0].mode -eq 'write')) ($r | ConvertTo-Json -Compress)
  $r = Site $db 'uProv.pas' $B8 'write' 'FFlag'
  Check '6 B8 Self.FFlag := False: mode write' ((@($r).Count -eq 1) -and ($r[0].qn -eq 'uProv.TProvider.FFlag') -and ($r[0].mode -eq 'write')) ($r | ConvertTo-Json -Compress)
  $r = Site $db 'uCons.pas' $C4 'write' 'Flag'
  Check '7 C4 with FProv do Flag := True: mode write, accessor FFlag' ((@($r).Count -eq 1) -and ($r[0].qn -eq 'uProv.TProvider.Flag') -and ($r[0].mode -eq 'write') -and ($r[0].acc -eq 'FFlag')) ($r | ConvertTo-Json -Compress)

  Write-Host '== check 8: NEGATIVE -- a local write stays identity-only ==' -ForegroundColor Cyan
  $r = Site $db 'uProv.pas' $B9 'write' 'L'
  Check '8a L := 1: bound to the local, no member_accesses row' ((@($r).Count -eq 1) -and ($r[0].qn -like '*Work.L') -and (-not $r[0].mode)) ($r | ConvertTo-Json -Compress)
  $u = Sql $db "SELECT COUNT(*) AS n FROM refs WHERE kind = 'write' AND symbol_id IS NULL AND name_text <> 'Result'"
  Check '8b every write ref keeps its binding' ([int]$u[0].n -eq 0) ($u | ConvertTo-Json -Compress)

  Write-Host '== checks 9-10: find-callers ==' -ForegroundColor Cyan
  $t = (& $exePath query find-callers --name SetValue --resolved --db $db 2>$null) -join "`n"
  Check '9a SetValue: dotted write C2 (control)' ($t.Contains("uCons.pas:$C2)")) $t
  Check '9b SetValue: bare write B3' ($t.Contains("uProv.pas:$B3)")) $t
  $t = (& $exePath query find-callers --name Work --resolved --db $db 2>$null) -join "`n"
  Check '10 Work: exactly one caller' ($t -match '(?m)^1 callers') $t

  Write-Host '== check 11: usages --rw lists each site once ==' -ForegroundColor Cyan
  $q = UsagesRw $db 'FFlag'
  $w = if ($q) { @($q.targets)[0].writers } else { @() }
  $okW = ((CountAt $w 'uProv.pas' $B1) -eq 1) -and ((CountAt $w 'uProv.pas' $B5) -eq 1) -and ((CountAt $w 'uProv.pas' $B8) -eq 1) -and ((CountAt $w 'uCons.pas' $C4) -eq 1) -and (@($w).Count -eq 4)
  Check '11a FFlag writers: B1 B5 B8 C4, once each' $okW ($w | ConvertTo-Json -Compress)
  $q = UsagesRw $db 'SetValue'
  $w = if ($q) { @($q.targets)[0].writers } else { @() }
  Check '11b SetValue writers: B3 and C2, once each' (((CountAt $w 'uProv.pas' $B3) -eq 1) -and ((CountAt $w 'uCons.pas' $C2) -eq 1) -and (@($w).Count -eq 2)) ($w | ConvertTo-Json -Compress)
}
finally {
  try { [IO.Directory]::Delete($scratch, $true) } catch { }
}
if ($script:fail) { Write-Host 'run_use_edges_bare_write: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_use_edges_bare_write: PASS' -ForegroundColor Green; exit 0
