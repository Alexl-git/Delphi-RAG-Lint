<#
  run_alias_rhs_refs.ps1 -- a type alias's TARGET must emit type_use refs.

  DEFECT (W5-ext, 2026-10-23; found by the W2-3b lint-FP lane): `TTokList =
  TList<TTok>` emitted NO ref for TList or TTok. TryWalkAlias claimed the
  declType, emitted the skTypeAlias symbol and Exit'ed without visiting the
  target typeref, so the only use of System.Generics.Collections in the unit
  was invisible and lint-all reported `unused-unit-in-uses` on a used unit.
  The plain form (`TAliased = TBase`) and the strong form (`= type TBase`)
  had the same hole: the target type never got a reference.

  POSITIVE CONTROL: a FIELD typed `TList<TTok>` emits type_use TList + TTok
  today (declField walks its children). Without it, a guard that only asserts
  "the alias rows exist" would also pass against an extractor that emitted a
  type_use for everything.

  OVER-CAPTURE GUARD: each target name appears EXACTLY once on its alias line
  (no double emission), and the alias NAME itself gets no type_use.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-alias-rhs-$PID"
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
Write-Ascii (Join-Path $work 'ua.pas') @'
unit ua;

interface

uses
  System.Generics.Collections;

type
  TTok = record
    Kind: Integer;
  end;
  TBase = class
  end;
  TBase2 = class
  end;
  TTokList = TList<TTok>;
  TAliased = TBase;
  TStrong = type TBase2;
  THolder = class
    FList: TList<TTok>;
  end;

implementation

end.
'@
$db = Join-Path $WorkDir 'alias.sqlite'
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
function TypeUses([int]$Line, [string]$Name) {
  $rows = Q "select name_text from refs where kind='type_use' and start_line=$Line and name_text='$Name'"
  return $rows.Count
}

Write-Host 'Positive control: a FIELD typed TList<TTok> (line 20)' -ForegroundColor Cyan
Check 'control: field emits type_use TList' ((TypeUses 20 'TList') -eq 1)
Check 'control: field emits type_use TTok'  ((TypeUses 20 'TTok') -eq 1)

Write-Host 'Generic alias TTokList = TList<TTok> (line 16)' -ForegroundColor Cyan
$n = TypeUses 16 'TList'; Check 'alias rhs emits type_use TList exactly once' ($n -eq 1) "got $n"
$n = TypeUses 16 'TTok';  Check 'alias rhs emits type_use TTok exactly once'  ($n -eq 1) "got $n"
$n = TypeUses 16 'TTokList'; Check 'alias NAME gets no type_use' ($n -eq 0) "got $n"

Write-Host 'Plain alias TAliased = TBase (line 17)' -ForegroundColor Cyan
$n = TypeUses 17 'TBase'; Check 'plain alias emits type_use TBase exactly once' ($n -eq 1) "got $n"

Write-Host 'Strong alias TStrong = type TBase2 (line 18)' -ForegroundColor Cyan
$n = TypeUses 18 'TBase2'; Check 'strong alias emits type_use TBase2 exactly once' ($n -eq 1) "got $n"

$sym = Q "select kind from symbols where name in ('TTokList','TAliased','TStrong')"
Check 'the three alias symbols are still emitted' ($sym.Count -eq 3) "got $($sym.Count)"

if ($script:Failed) { Write-Host 'run_alias_rhs_refs: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_alias_rhs_refs: PASS' -ForegroundColor Green
exit 0
} catch {
  Write-Host "FATAL: $_" -ForegroundColor Red
  exit 2
}
