<#
  run_profile_calls_identity.ps1 -- 152 PF2: the calls-stage profile (DRAGLINT_PROFILE_CALLS=1)
  covers EVERY section of TCallResolver's CALL_PROF_NAMES (13 streams + 11 routines), and the
  switch never changes a stored row.

  CASES
    S1 self-test : the profile-table parser FAILS on (a) an empty table, (b) a section with
       0 entries, (c) an unknown section name, (d) a missing section, and PASSES on a full
       synthetic table (POSITIVE CONTROL of the checker itself: a checker that cannot fail
       is a defect)
    T1 table     : the ON run's `resolve: calls      profile:` table parses, has exactly one
       row per known section, every row has > 0 entries (RED on the 151 fixture of
       run_resolve_calls_profile.ps1: TypeOfSelectorChain, DecideInlineInitType and
       InlineInitMemberType never run there, so ProfileLines omits them)
    T2 off       : the OFF run prints no `profile:` line
    I1-control   : the I1 comparison over a dump missing one call_edges row reports a difference
    I1 identity  : call_edges, member_accesses, refs (id, symbol_id, receiver_text,
       external_target), ref_types, ref_receivers -- full sorted rows via `sql --output`,
       never `sql --json` (positional, capped at 200 rows) -- byte-identical ON vs OFF,
       and the dump is non-empty
  Parse-only mode: -ProfileLog <log> checks an existing resolve log (T1 rules) and prints the
  sections sorted by seconds (used by the 152 PF2 CLIENT profile run); -MinSeconds lists only
  the sections at or over that many seconds.
  Usage: pwsh -File tests\autotest\run_profile_calls_identity.ps1 [-Exe <drag-lint.exe>]
         pwsh -File tests\autotest\run_profile_calls_identity.ps1 -ProfileLog <log> [-MinSeconds 1]
#>
[CmdletBinding()]
param(
  [string]$Exe        = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir    = "$env:TEMP\draglint_profile_calls_identity_$PID",
  [string]$ProfileLog = '',
  [double]$MinSeconds = 0
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function W($p, $t) { [IO.File]::WriteAllText($p, (($t -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII) }

# CALL_PROF_NAMES in src\index\DRagLint.Index.CallResolver.pas, declaration order.
$KnownSections = @('stream main', 'stream enum-values', 'stream parenless', 'stream member-reads',
  'stream value-reads', 'stream type-uses', 'stream exception-types', 'stream enum-casts',
  'stream type-reads', 'stream writes', 'stream arg-uses', 'stream ref-types', 'stream ref-receivers',
  'TypeReceiverCore', 'TypeOfSelectorChain', 'BindExternally', 'BindExternally.DeclUses',
  'ResolveTypeNameToSymbol', 'LookupTypeName', 'LocalInScopeAt', 'LinesOf', 'FileUsesUnits',
  'DecideInlineInitType', 'InlineInitMemberType')

# Parses the profile lines of a log. Returns @{ Rows = list of [name, seconds, entries]; Errors = list }.
# An unknown section name, a duplicate, a 0-entry row, a missing section or an empty table is an error.
function Read-ProfileTable([string[]]$Lines) {
  $rows = [Collections.Generic.List[object]]::new()
  $errs = [Collections.Generic.List[string]]::new()
  foreach ($l in $Lines) {
    if ($l -notmatch 'resolve: calls\s+profile: ') { continue }
    if ($l -notmatch 'profile: (\S+(?: \S+)?)\s+([\d.]+) s\s+(\d+) entries\s*$') { $errs.Add("unparsed line: $l"); continue }
    $name = $Matches[1]; $sec = [double]$Matches[2]; $n = [int64]$Matches[3]
    if ($KnownSections -cnotcontains $name) { $errs.Add("unknown section: $name") }
    elseif (@($rows | Where-Object { $_[0] -ceq $name }).Count -gt 0) { $errs.Add("duplicate section: $name") }
    if ($n -le 0) { $errs.Add("0 entries: $name") }
    $rows.Add(@($name, $sec, $n))
  }
  if ($rows.Count -eq 0) { $errs.Add('empty table') }
  else {
    foreach ($k in $KnownSections) {
      if (@($rows | Where-Object { $_[0] -ceq $k }).Count -eq 0) { $errs.Add("missing section: $k") }
    }
  }
  return @{ Rows = $rows; Errors = $errs }
}
function Fmt-Row($name, $sec, $n) { 'resolve: calls      profile: {0,-26} {1,8:F2} s {2,10} entries' -f $name, $sec, $n }

# ---- S1: the checker can fail ---------------------------------------------------------------
$full = @($KnownSections | ForEach-Object { Fmt-Row $_ 0.01 3 })
$r = Read-ProfileTable $full
Check 'S1-full' ($r.Errors.Count -eq 0 -and $r.Rows.Count -eq $KnownSections.Count) "(rows $($r.Rows.Count), errors $($r.Errors.Count))"
$r = Read-ProfileTable @('stage: calls -- done in 0.1s')
Check 'S1-empty' ($r.Errors -contains 'empty table') "($($r.Errors -join '; '))"
$r = Read-ProfileTable (@($full | Select-Object -Skip 1) + (Fmt-Row 'stream main' 0.01 0))
Check 'S1-zero' ($r.Errors -contains '0 entries: stream main') "($($r.Errors -join '; '))"
$r = Read-ProfileTable ($full + (Fmt-Row 'NoSuchSection' 0.01 3))
Check 'S1-unknown' ($r.Errors -contains 'unknown section: NoSuchSection') "($($r.Errors -join '; '))"
$r = Read-ProfileTable @($full | Where-Object { $_ -notmatch 'LinesOf' })
Check 'S1-missing' ($r.Errors -contains 'missing section: LinesOf') "($($r.Errors -join '; '))"

# ---- parse-only mode -------------------------------------------------------------------------
if ($ProfileLog -ne '') {
  if (-not (Test-Path $ProfileLog)) { Write-Host "FATAL: log not found: $ProfileLog" -ForegroundColor Red; exit 2 }
  $r = Read-ProfileTable ([IO.File]::ReadAllLines($ProfileLog))
  Check 'T1' ($r.Errors.Count -eq 0) "(rows $($r.Rows.Count) of $($KnownSections.Count); $($r.Errors -join '; '))"
  $r.Rows | Sort-Object { $_[1] } -Descending | Where-Object { $_[1] -ge $MinSeconds } |
    ForEach-Object { '    {0,-26} {1,8:F2} s {2,10} entries' -f $_[0], $_[1], $_[2] } | Write-Host
  if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
  Write-Host 'RESULT: PASS' -ForegroundColor Green
  exit 0
}

# ---- fixture run -----------------------------------------------------------------------------
try {
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
  private
    FItems: TList;
    function GetItem(AIndex: Integer): TBox;
  public
    FCount: Integer;
    FList: TStringList;
    function Child: TBox;
    property Items[AIndex: Integer]: TBox read GetItem; default;
  end;

procedure SetIt(var A: Integer);
procedure GetIt(out A: Integer);
procedure ByVal(A: Integer);
function MakeBox: TBox;

implementation

function TBox.GetItem(AIndex: Integer): TBox;
begin
  Result := TBox(FItems[AIndex]);
end;

function TBox.Child: TBox;
begin
  Result := Self;
end;

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

function MakeBox: TBox;
begin
  Result := TBox.Create;
end;

end.
'@
W (Join-Path $WorkDir 'uUser.pas') @'
unit uUser;

interface

procedure Run;
procedure RunInline;

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
  B.Items[0].Child.FList.Add('y');
  B[1].FList.Clear;
  B.Free;
end;

procedure RunInline;
begin
  var B := MakeBox;
  var L := B.FList;
  var C := B.Child;
  L.Add('z');
  C.FList.Add('w');
  for var S in L do
    ByVal(Length(S));
  var D := TBox.Create;
  D.FList.Add(v);
  D.Free;
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
  RunInline;
end.
'@

$proj = Join-Path $WorkDir 'ProfApp.dpr'
$db = Join-Path $WorkDir 'p.sqlite'
$env:DRAGLINT_PROFILE_CALLS = $null
& $Exe index --project $proj --db $db *> (Join-Path $WorkDir 'index.log')
if ($LASTEXITCODE -ne 0) { Write-Host "FATAL: index exit $LASTEXITCODE" -ForegroundColor Red; exit 2 }

function Invoke-ResolveArm([string]$Tag, [bool]$On) {
  $d = Join-Path $WorkDir "$Tag.sqlite"
  [IO.File]::Copy($db, $d, $true)
  $env:DRAGLINT_PROFILE_CALLS = if ($On) { '1' } else { $null }
  & $Exe index --project $proj --db $d --resolve-only *> (Join-Path $WorkDir "$Tag.log")
  $ec = $LASTEXITCODE
  $env:DRAGLINT_PROFILE_CALLS = $null
  if ($ec -ne 0) { Write-Host "FATAL: resolve-only ($Tag) exit $ec" -ForegroundColor Red; exit 2 }
  return $d
}
$dbOn  = Invoke-ResolveArm 'on'  $true
$dbOff = Invoke-ResolveArm 'off' $false
$logOn  = [IO.File]::ReadAllLines((Join-Path $WorkDir 'on.log'))
$logOff = [IO.File]::ReadAllLines((Join-Path $WorkDir 'off.log'))

$r = Read-ProfileTable $logOn
Check 'T1' ($r.Errors.Count -eq 0) "(rows $($r.Rows.Count) of $($KnownSections.Count); $($r.Errors -join '; '))"
$offProf = @($logOff | Where-Object { $_ -match 'profile:' })
Check 'T2' ($offProf.Count -eq 0) "(profile lines with the switch off: $($offProf.Count))"

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
# I1 positive control: the same comparison over a dump missing its first call_edges row must differ
$pc = Join-Path $WorkDir 'on.call_edges.skip1.txt'
& $Exe sql --db $dbOn --query 'SELECT ref_id, target_symbol_id, confidence, receiver_type_symbol_id FROM call_edges ORDER BY ref_id LIMIT -1 OFFSET 1' --limit 100000000 --output $pc *> $null
$rp = @([IO.File]::ReadAllLines($pc) | Where-Object { $_ -notmatch '^\d+ row\(s\) in ' })
$rf = @([IO.File]::ReadAllLines((Join-Path $WorkDir 'on.call_edges.txt')) | Where-Object { $_ -notmatch '^\d+ row\(s\) in ' })
Check 'I1-control' (($rp -join "`n") -ne ($rf -join "`n")) "(full $($rf.Count) lines vs skip-1 $($rp.Count) lines)"
Check 'I1' (($diff.Count -eq 0) -and ($rowsTotal -gt 10)) "(tables differing: $($diff -join ',') ; dumped lines $rowsTotal)"

if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
} finally {
  $env:DRAGLINT_PROFILE_CALLS = $null
}
