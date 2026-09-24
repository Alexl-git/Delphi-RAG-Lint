<#
  run_find_callers_reports_bound_writes.ps1 -- D31: `query find-callers
  --resolved` reports a BOUND bare WRITE as a site with mode `write`
  (docs\INBOX-d13-write-refs-bound-but-no-member-access.md).

  THE DEFECT. Since resolver 1.8.0-alpha (D13) the resolve pass binds a bare
  write (`FFlag := True;`, `GCount := 1;`) -- refs.kind = 'write',
  refs.symbol_id set -- IDENTITY ONLY: no call_edges row, no member_accesses
  row. FindResolvedCallers is a UNION of three arms (call_edges;
  member_accesses; bound usages over plain refs) and its third arm admitted
  only `r.kind IN ('read', 'member-access')`. So a bound write was reported by
  NO arm, and a consumer that trusts find-callers (the charts `who-writes`)
  stated a false "no write sites".

  THE FIX (read side only; no resolver or extractor bump). The bound-usage arm
  admits 'write' and DERIVES its mode from the ref kind:
  `CASE r.kind WHEN 'write' THEN 'write' ELSE 'read' END`. Owner ruling R7
  (an enum value's qualified read, ref kind 'member-access', reports mode
  'read') is preserved by the ELSE.

  CHECKS
    1  fixture health: indexes clean, and every write site in the fixture is
       BOUND in refs (without that, check 2 would be testing nothing)
    2  every bound write site is listed by find-callers --resolved with
       mode = write                                         (RED before D31)
    3  POSITIVE CONTROL: the bound reads of FFlag (Self.FFlag, and T.Flag via
       the field-backed property) are still listed with mode = read
    4  no site is listed twice. The fixture holds a DOTTED write
       (`T.FFlag := False`, ref kind 'member-access', bound) that owns a
       member_accesses row: the member arm lists it, and the bound-usage arm
       must NOT list it a second time -- the `NOT EXISTS` exclusion is what
       this check pins
    5  R7 CONTROL: enum values still report mode = read, for both the bare
       read (kind 'read') and the qualified read (kind 'member-access')
    6  no row anywhere carries a mode other than read/write (a raw `r.kind`
       leaking through would render 'member-access')

  NO FIXTURE LINE NUMBER IS HARD-CODED: sites are located at run time by
  their `{ Wn ... }` / `{ Rn ... }` comment anchors (LineOf fails loud, exit
  2, on a non-unique anchor -- a broken fixture, not a RED).

  `sql --json` rows are POSITIONAL arrays and are mapped onto columns[].name
  (Sql below); `find-callers --resolved --json` is an array of objects with
  caller_qname, file, confidence, target_qname, line (the SITE line),
  caller_line, mode -- measured raw on 1.17.0-alpha before any assertion here
  was written.

  Usage: pwsh -File tests\callresolve\run_find_callers_reports_bound_writes.ps1 [-Exe <drag-lint.exe>]
  Scratch: C:\TEMP\draglint_find_callers_bound_writes-<PID>, removed on exit.
#>
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check([string]$n, [bool]$ok, [string]$d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:fail = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: engine not found: $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP ("draglint_find_callers_bound_writes-{0}" -f $PID)
if (Test-Path $scratch) { Remove-Item -Recurse -Force $scratch }
New-Item -ItemType Directory $scratch | Out-Null

function W([string]$name, [string]$body) {
  [IO.File]::WriteAllText((Join-Path $scratch $name), ($body -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
}
function Sql([string]$db, [string]$q) {
  $j = (& $exePath sql --db $db --query $q --json 2>$null) -join "`n"
  if ([string]::IsNullOrWhiteSpace($j)) { return ,@() }
  try { $o = $j | ConvertFrom-Json } catch { return ,@() }
  $cols = @($o.columns | ForEach-Object { $_.name })
  $out = @()
  foreach ($r in @($o.rows)) {
    $h = [ordered]@{}
    for ($i = 0; $i -lt $cols.Count; $i++) { $h[$cols[$i]] = @($r)[$i] }
    $out += [pscustomobject]$h
  }
  return ,$out
}
function LineOf([string]$path, [string]$anchor) {
  $lines = [IO.File]::ReadAllText($path) -split "`r`n"
  $hits = @()
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Contains($anchor)) { $hits += ($i + 1) } }
  if ($hits.Count -ne 1) {
    Write-Host ("FATAL: fixture anchor '{0}' matched {1} line(s) in {2} -- the FIXTURE is broken, not the engine" -f $anchor, $hits.Count, $path) -ForegroundColor Red
    exit 2
  }
  return $hits[0]
}
function Resolved([string]$db, [string]$name) {
  $raw = & $exePath query find-callers --name $name --resolved --json --db $db 2>$null | Out-String
  if ($raw.Trim() -eq '') { return @() }
  try { return @(($raw | ConvertFrom-Json)) } catch { return @() }
}
function RowsAt($rows, [string]$file, [int]$line) {
  return @($rows | Where-Object { $_.file -eq $file -and [int]$_.line -eq $line })
}

try {
  W 'uFlag.pas' @'
unit uFlag;
interface
type
  TKind = (kOne, kTwo);
  TThing = class
  private
    FFlag: Boolean;
  public
    procedure SetIt;
    function GetSelf: Boolean;
    property Flag: Boolean read FFlag;
  end;
var
  GCount: Integer;
procedure Bump;
procedure Reset(T: TThing);
function Kinds: Integer;
implementation
procedure TThing.SetIt;
begin
  FFlag := True;                      { W1 FFlag bare write }
end;
function TThing.GetSelf: Boolean;
begin
  Result := Self.FFlag;               { R1 FFlag dotted read }
end;
procedure Bump;
begin
  GCount := 1;                        { W3 GCount bare write }
end;
procedure Reset(T: TThing);
begin
  T.FFlag := False;                   { W2 FFlag DOTTED write, owns a member_accesses row }
end;
function Kinds: Integer;
var
  K: TKind;
begin
  K := kTwo;                          { E1 enum bare read }
  K := TKind.kOne;                    { E2 enum qualified read }
  Result := Ord(K);
end;
end.
'@

  W 'uUser.pas' @'
unit uUser;
interface
uses uFlag;
procedure UseAll(T: TThing);
implementation
procedure UseAll(T: TThing);
begin
  GCount := 2;                        { W4 GCount bare write, cross-unit }
  if T.Flag then                      { R2 FFlag read through the field-backed property }
    Exit;
end;
end.
'@

  $fFlag = Join-Path $scratch 'uFlag.pas'
  $fUser = Join-Path $scratch 'uUser.pas'
  $db    = Join-Path $scratch 'p.sqlite'
  $Sites = @{
    W1 = @{ f = 'uFlag.pas'; l = (LineOf $fFlag '{ W1 '); k = 'write';         n = 'FFlag';  q = 'uFlag.TThing.FFlag'; caller = 'uFlag.TThing.SetIt' }
    W2 = @{ f = 'uFlag.pas'; l = (LineOf $fFlag '{ W2 '); k = 'member-access'; n = 'FFlag';  q = 'uFlag.TThing.FFlag'; caller = 'uFlag.Reset'    }
    W3 = @{ f = 'uFlag.pas'; l = (LineOf $fFlag '{ W3 '); k = 'write';         n = 'GCount'; q = 'uFlag.GCount';       caller = 'uFlag.Bump' }
    W4 = @{ f = 'uUser.pas'; l = (LineOf $fUser '{ W4 '); k = 'write';         n = 'GCount'; q = 'uFlag.GCount';       caller = 'uUser.UseAll' }
    R1 = @{ f = 'uFlag.pas'; l = (LineOf $fFlag '{ R1 '); n = 'FFlag';  q = 'uFlag.TThing.FFlag'; caller = 'uFlag.TThing.GetSelf' }
    R2 = @{ f = 'uUser.pas'; l = (LineOf $fUser '{ R2 '); n = 'FFlag';  q = 'uFlag.TThing.FFlag'; caller = 'uUser.UseAll' }
    E1 = @{ f = 'uFlag.pas'; l = (LineOf $fFlag '{ E1 '); n = 'kTwo';   q = 'uFlag.TKind.kTwo';   caller = 'uFlag.Kinds' }
    E2 = @{ f = 'uFlag.pas'; l = (LineOf $fFlag '{ E2 '); n = 'kOne';   q = 'uFlag.TKind.kOne';   caller = 'uFlag.Kinds' }
  }
  $writes = @('W1', 'W2', 'W3', 'W4')

  Write-Host ''
  Write-Host '== check 1: fixture health ==' -ForegroundColor Cyan
  $idx = & $exePath index $scratch --db $db 2>&1 | Out-String
  Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
  Check 'index reported no parse errors' ($idx -notmatch '(?<!\d)[1-9]\d* errors') ''
  foreach ($k in $writes) {
    $s = $Sites[$k]
    $r = Sql $db ("SELECT s.qualified_name AS qn FROM refs r JOIN files f ON f.id = r.file_id LEFT JOIN symbols s ON s.id = r.symbol_id " +
                  "WHERE f.path LIKE '%\{0}' AND r.start_line = {1} AND r.kind = '{3}' AND r.name_text = '{2}'" -f $s.f, $s.l, $s.n, $s.k)
    Check ("{0} ({1}:{2}) is one {5} ref of {3}, BOUND to {4}" -f $k, $s.f, $s.l, $s.n, $s.q, $s.k) (@($r).Count -eq 1 -and $r[0].qn -eq $s.q) ($r | ConvertTo-Json -Compress)
  }

  $fc = @{}
  foreach ($n in @('FFlag', 'GCount', 'kTwo', 'kOne')) { $fc[$n] = @(Resolved $db $n) }

  Write-Host ''
  Write-Host '== check 2: every bound write site is reported with mode = write (D31) ==' -ForegroundColor Cyan
  foreach ($k in $writes) {
    $s = $Sites[$k]
    $at = RowsAt $fc[$s.n] $s.f $s.l
    Check ("{0}: {1} lists {2}:{3} (caller {4})" -f $k, $s.n, $s.f, $s.l, $s.caller) ($at.Count -ge 1 -and $at[0].caller_qname -eq $s.caller -and $at[0].target_qname -eq $s.q) ($fc[$s.n] | ConvertTo-Json -Compress)
    Check ("{0}: mode = write" -f $k) ($at.Count -ge 1 -and @($at | Where-Object { $_.mode -ne 'write' }).Count -eq 0) ($at | ConvertTo-Json -Compress)
  }
  foreach ($n in @('FFlag', 'GCount')) {
    $wSites = @($writes | Where-Object { $Sites[$_].n -eq $n } | ForEach-Object { '{0}:{1}' -f $Sites[$_].f, $Sites[$_].l })
    $stray = @($fc[$n] | Where-Object { $_.mode -eq 'write' -and ($wSites -notcontains ('{0}:{1}' -f $_.file, $_.line)) })
    Check ("{0}: no mode=write row outside the fixture's write sites" -f $n) ($stray.Count -eq 0) ($stray | ConvertTo-Json -Compress)
  }

  Write-Host ''
  Write-Host '== check 3: POSITIVE CONTROL -- bound FFlag reads still report mode = read ==' -ForegroundColor Cyan
  foreach ($k in @('R1', 'R2')) {
    $s = $Sites[$k]
    $at = RowsAt $fc[$s.n] $s.f $s.l
    Check ("{0}: FFlag lists {1}:{2} (caller {3}) with mode = read" -f $k, $s.f, $s.l, $s.caller) ($at.Count -eq 1 -and $at[0].caller_qname -eq $s.caller -and $at[0].mode -eq 'read') ($fc[$s.n] | ConvertTo-Json -Compress)
  }

  Write-Host ''
  Write-Host '== check 4: no site listed twice (the DOTTED write W2 is the double-row trap) ==' -ForegroundColor Cyan
  $w2Rows = RowsAt $fc['FFlag'] $Sites.W2.f $Sites.W2.l
  Check 'fixture health: W2 owns a member_accesses row (so the member arm lists it and the trap is armed)' `
    ((@(Sql $db ("SELECT COUNT(*) AS n FROM member_accesses ma JOIN refs r ON r.id = ma.ref_id JOIN files f ON f.id = r.file_id " +
                 "WHERE f.path LIKE '%\{0}' AND r.start_line = {1} AND ma.mode = 'write'" -f $Sites.W2.f, $Sites.W2.l)) | ForEach-Object { [int]$_.n }) -eq 1) ''
  Check 'W2 is listed exactly ONCE' ($w2Rows.Count -eq 1) ($w2Rows | ConvertTo-Json -Compress)
  foreach ($n in @('FFlag', 'GCount', 'kTwo', 'kOne')) {
    $keys = @($fc[$n] | ForEach-Object { '{0}:{1}' -f $_.file, $_.line })
    $dups = @($keys | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
    Check ("{0}: every (file, line) appears once ({1} rows)" -f $n, $keys.Count) ($keys.Count -gt 0 -and $dups.Count -eq 0) ("dups=" + ($dups -join ','))
  }

  Write-Host ''
  Write-Host '== check 5: R7 CONTROL -- enum values still report mode = read ==' -ForegroundColor Cyan
  foreach ($k in @('E1', 'E2')) {
    $s = $Sites[$k]
    $at = RowsAt $fc[$s.n] $s.f $s.l
    Check ("{0}: {1} lists {2}:{3} with mode = read" -f $k, $s.n, $s.f, $s.l) ($at.Count -eq 1 -and $at[0].target_qname -eq $s.q -and $at[0].mode -eq 'read') ($fc[$s.n] | ConvertTo-Json -Compress)
  }

  Write-Host ''
  Write-Host '== check 6: every row mode is read or write (no raw ref kind leaks) ==' -ForegroundColor Cyan
  $all = @($fc.Values | ForEach-Object { $_ })
  $bad = @($all | Where-Object { $_.mode -ne 'read' -and $_.mode -ne 'write' })
  Check ("all {0} rows carry mode read|write" -f $all.Count) ($all.Count -gt 0 -and $bad.Count -eq 0) ($bad | ConvertTo-Json -Compress)
}
finally {
  if (Test-Path $scratch) { Remove-Item -Recurse -Force $scratch -ErrorAction SilentlyContinue }
}

Write-Host ''
if ($script:fail) { Write-Host 'FIND-CALLERS-BOUND-WRITES: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'FIND-CALLERS-BOUND-WRITES: PASS' -ForegroundColor Green
exit 0
