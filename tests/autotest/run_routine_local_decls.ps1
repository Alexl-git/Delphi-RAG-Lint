<#
  run_routine_local_decls.ps1 -- a routine's own `type` and `const` sections
  must emit symbols and refs.

  DEFECT (N-04, docs\INBOX-routine-local-enum-values-not-indexed.md): the
  defProc arm of Walk visited the body, the declVars (EmitRoutineLocals) and
  nested routines -- never the declTypes / declConsts siblings. So
  `type TInlineKind = (ikA, ...)` inside a routine produced no enum, no
  enum_value, `query --name ikA` answered 0 matches, and every typeref or
  const expression inside those sections lost its ref (a local alias to an
  imported type left the unit looking unused).

  POSITIVE CONTROL: the unit-level enum TUnitKind and its value ukA are indexed
  today and the body read of ukA binds to it.

  SCOPE GUARDS: names qualify under the routine (ul.Run.TLocalKind.lkA); the
  nested routine's own const is parented to the nested routine
  (ul.Run.Inner.LOCAL_MAX), not to Run; and a read of the unit-level ukB in a
  DIFFERENT routine still binds to the unit-level value although Run declares
  a local enum value of the same name (a routine-local declaration must not
  make the unit-level one ambiguous elsewhere).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-routine-local-$PID"
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
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$work = Join-Path $WorkDir 'fixture'
New-Item -ItemType Directory -Force $work | Out-Null
function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
# Line numbers below are asserted -- keep the fixture's layout stable.
Write-Ascii (Join-Path $work 'ul.pas') @'
unit ul;

interface

type
  TBaseThing = class
  end;
  TUnitKind = (ukA, ukB);

procedure Run;
procedure Other;

implementation

procedure Run;
type
  TLocalKind = (lkA, lkB, ukB);
  TLocalRec = record
    K: TLocalKind;
  end;
  TLocalAlias = TBaseThing;
const
  LOCAL_MAX = 3;
  LOCAL_K: TLocalKind = lkB;
var
  R: TLocalRec;
  N: Integer;
  U: TUnitKind;

  procedure Inner;
  const
    LOCAL_MAX = 9;
  begin
    N := LOCAL_MAX;
  end;

begin
  R.K := lkA;
  U := ukA;
  N := LOCAL_MAX;
  if R.K = LOCAL_K then N := 0;
  Inner;
  if LOCAL_K = ukB then N := 1;
end;

procedure Other;
var
  V: TUnitKind;
begin
  V := ukB;
  V := ul.ukB;
end;

end.
'@
$db = Join-Path $WorkDir 'local.sqlite'
$io = & $Exe index $work --db $db --library-db none 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

# sql --json rows are POSITIONAL arrays: map them onto columns[].name.
function Q([string]$Sql) {
  $raw = & $Exe sql --db $db --json --query $Sql 2>$null | Out-String
  $j = $raw | ConvertFrom-Json
  $names = @($j.columns | ForEach-Object { $_.name })
  $out = @()
  foreach ($r in @($j.rows)) {
    $h = @{}
    for ($i = 0; $i -lt $names.Count; $i++) { $h[$names[$i]] = $r[$i] }
    $out += [pscustomobject]$h
  }
  return ,$out
}
function SymId([string]$QName, [string]$Kind) {
  $rows = Q "select id from symbols where qualified_name='$QName' and kind='$Kind'"
  if ($rows.Count -ne 1) { return 0 }
  return [int64]$rows[0].id
}
function RefSym([int]$Line, [string]$Name, [string]$Kind) {
  $rows = Q "select coalesce(symbol_id,0) sid from refs where start_line=$Line and name_text='$Name' and kind='$Kind'"
  if ($rows.Count -ne 1) { return -1 }
  return [int64]$rows[0].sid
}

Write-Host 'Positive control: unit-level enum' -ForegroundColor Cyan
$ukA = SymId 'ul.TUnitKind.ukA' 'enum_value'
Check 'control: ul.TUnitKind.ukA indexed' ($ukA -gt 0)
$n = RefSym 39 'ukA' 'read'; Check 'control: body read of ukA binds' ($n -eq $ukA -and $ukA -gt 0) "sid=$n want=$ukA"

Write-Host 'Routine-local type section' -ForegroundColor Cyan
Check 'enum ul.Run.TLocalKind'            ((SymId 'ul.Run.TLocalKind' 'enum') -gt 0)
$lkA = SymId 'ul.Run.TLocalKind.lkA' 'enum_value'
Check 'enum_value ul.Run.TLocalKind.lkA'  ($lkA -gt 0)
$n = RefSym 38 'lkA' 'read'; Check 'body read of lkA binds to the local value' ($n -eq $lkA -and $lkA -gt 0) "sid=$n want=$lkA"
Check 'enum_value ul.Run.TLocalKind.lkB'  ((SymId 'ul.Run.TLocalKind.lkB' 'enum_value') -gt 0)
Check 'record ul.Run.TLocalRec'           ((SymId 'ul.Run.TLocalRec' 'record') -gt 0)
Check 'field ul.Run.TLocalRec.K'          ((SymId 'ul.Run.TLocalRec.K' 'field') -gt 0)
Check 'type ul.Run.TLocalAlias'           ((SymId 'ul.Run.TLocalAlias' 'type') -gt 0)
$n = (Q "select id from refs where kind='type_use' and start_line=19 and name_text='TLocalKind'").Count
Check 'local record field type emits type_use TLocalKind' ($n -eq 1) "got $n"
$n = (Q "select id from refs where kind='type_use' and start_line=21 and name_text='TBaseThing'").Count
Check 'local alias target emits type_use TBaseThing' ($n -eq 1) "got $n"

Write-Host 'Routine-local const section' -ForegroundColor Cyan
Check 'const ul.Run.LOCAL_MAX'            ((SymId 'ul.Run.LOCAL_MAX' 'const') -gt 0)
Check 'const ul.Run.LOCAL_K'              ((SymId 'ul.Run.LOCAL_K' 'const') -gt 0)
$n = (Q "select id from refs where kind='type_use' and start_line=24 and name_text='TLocalKind'").Count
Check 'typed local const emits type_use TLocalKind' ($n -eq 1) "got $n"
Check 'nested routine const is ul.Run.Inner.LOCAL_MAX' ((SymId 'ul.Run.Inner.LOCAL_MAX' 'const') -gt 0)
$n = (Q "select id from symbols where name='LOCAL_MAX'").Count
Check 'exactly two LOCAL_MAX symbols (outer + nested)' ($n -eq 2) "got $n"

Write-Host 'Scope: the local ukB must not steal or blur the unit-level ukB' -ForegroundColor Cyan
$ukB = SymId 'ul.TUnitKind.ukB' 'enum_value'
$n = RefSym 50 'ukB' 'read'
Check 'read of ukB in Other binds to ul.TUnitKind.ukB' ($n -eq $ukB -and $ukB -gt 0) "sid=$n want=$ukB"
$rows = Q "select coalesce(symbol_id,0) sid from refs where start_line=51 and name_text='ukB'"
Check 'qualified ul.ukB in Other binds to the unit-level value' ($rows.Count -ge 1 -and [int64]$rows[0].sid -eq $ukB) "rows=$($rows.Count) sid=$($rows[0].sid)"
$lukB = SymId 'ul.Run.TLocalKind.ukB' 'enum_value'
$n = RefSym 43 'ukB' 'read'
Check 'read of ukB inside Run binds to the NEARER local value' ($n -eq $lukB -and $lukB -gt 0) "sid=$n want=$lukB"

if ($script:Failed) { Write-Host 'run_routine_local_decls: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_routine_local_decls: PASS' -ForegroundColor Green
exit 0
} catch {
  Write-Host "FATAL: $_" -ForegroundColor Red
  exit 2
}
