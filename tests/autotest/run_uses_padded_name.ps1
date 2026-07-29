<#
  run_uses_padded_name.ps1 -- register K43.

  WHAT THIS GUARDS

  `WalkUsesClause` (src/parser/DRagLint.Parser.Delphi13.pas) stored a used
  unit's name as `Trim(NodeText(ModNode, ...))`. A `moduleName` node spans the
  whole dotted name, and `Trim` only removes LEADING and TRAILING whitespace --
  so this repo's own alignment house style,

      uses
        Alpha  .Config,
        Beta.Config;

  stored the literal string `'Alpha  .Config'`, interior padding and all.

  That is not cosmetic. `ResolveUnitUseTargets`'s pass 1
  (src/storage/DRagLint.Storage.SQLite.pas:3716) keys on
  `LOWER(unit_name) = :un`, which a padded value can NEVER satisfy, so the edge
  is left unresolved (`target_file_id IS NULL`). Pass 2 keys on
  `unit_name_norm`, which is the dotted TAIL and is unaffected by the padding --
  which is why the defect stayed mostly invisible: whenever the tail is unique,
  pass 2 quietly rescues the row and the answer looks right.

  Measured at the time of the fix, `unit_uses` rows whose `unit_name` contains
  whitespace: 147 of 1836 in the self index (137 still unresolved), 286 of 14223
  in ORM3 (285 unresolved), 0 in library-Win64 and 0 in M2022 -- zero in the
  third-party indexes, because the padding is OUR house style.

  THE FIXTURE IS BUILT SO PASS 2 CANNOT MASK THE DEFECT

  Two units, `Alpha.Config` and `Beta.Config`, deliberately SHARE the tail
  `config`. That makes the tail ambiguous, so `ResolveUnitUseTargets` refuses it
  in pass 2 (`if TailAmbig.ContainsKey(...) then Continue`) and pass 1 is the
  only route to a resolved edge. `Consumer` then uses one of them PADDED and the
  other PLAIN, so a single index run yields the contrast directly:

    pre-fix   unit_name='Alpha  .Config'  target_file_id=NULL   <- padded, lost
              unit_name='Beta.Config'     target_file_id=2      <- plain, fine

  The plain row is the control: it proves the resolver, the fixture and the
  ambiguous tail all work, so a failure of the padded row can only be the stored
  name. Without it, a broken resolver would look identical to this defect.

  THE SECOND SITE THAT READS THE SAME NODE (`Gamma`, fix round 1)

  `WalkUnit` reads the very same `moduleName` node for a unit's OWN declaration
  and had the very same `Trim`. That value is worse to get wrong than a uses
  edge: it becomes the `unit` symbol's `name` AND the `qualified_name` prefix of
  every symbol the unit declares, so ONE padded `unit` line mis-keys a whole
  unit's rows. `Gamma.Config.pas` declares itself `unit Gamma  .Config;` and is
  asserted on both stored columns. It is deliberately NOT used by `Consumer`, so
  it cannot disturb the two `unit_uses` rows above; measured latent when fixed
  (0 of 7098 `unit` symbols across the self / ORM3 / library-Win64 / M2022
  indexes carried embedded whitespace), which is exactly why it needs a fixture
  rather than a live query to stay fixed.

  CWD: this runner does NOT Push-Location, unlike the `tests\autodoc\*` runners
  whose headers say "run from a NEUTRAL CWD" and then actually do it. It does
  not need to -- every path it hands the exe (`$work`, `--db`) is absolute, and
  the battery supplies the repo root as CWD deliberately (see
  tests\run_battery.ps1). `$env:TEMP\drag-lint-uses-padded` is where the FIXTURE
  lives, not a working directory.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-uses-padded"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$work = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $work | Out-Null

Write-Ascii (Join-Path $work 'Alpha.Config.pas') @'
unit Alpha.Config;
interface
function AlphaCfg: Integer;
implementation
function AlphaCfg: Integer;
begin
  Result := 1;
end;
end.
'@
Write-Ascii (Join-Path $work 'Beta.Config.pas') @'
unit Beta.Config;
interface
function BetaCfg: Integer;
implementation
function BetaCfg: Integer;
begin
  Result := 2;
end;
end.
'@
# Gamma pads its OWN declaration, which is the WalkUnit site. Nothing uses it.
# The padding is SPACE + #11 (VT) + #12 (FF) on purpose (register K57): the
# strip's contract is "every whitespace byte", and Pascal's whitespace class is
# wider than the four bytes an earlier version of it matched. Both are written
# as [char] escapes so this .ps1 stays 7-bit ASCII with no stray control bytes.
# This grammar accepts them between the tokens of a dotted name -- MEASURED, and
# the premise check below re-measures it on every run: the fixture must index
# with 0 errors and emit a unit symbol, or these assertions prove nothing.
$pad = ' ' + [char]11 + [char]12 + ' '
Write-Ascii (Join-Path $work 'Gamma.Config.pas') (@'
unit Gamma@PAD@.Config;
interface
function GammaCfg: Integer;
implementation
function GammaCfg: Integer;
begin
  Result := 3;
end;
end.
'@ -replace '@PAD@', $pad)
# Alpha is PADDED the way this repo aligns; Beta is plain (the control).
Write-Ascii (Join-Path $work 'Consumer.pas') @'
unit Consumer;
interface
uses
  Alpha  .Config,
  Beta.Config;
function Both: Integer;
implementation
function Both: Integer;
begin
  Result := AlphaCfg + BetaCfg;
end;
end.
'@

$db = Join-Path $WorkDir 'padded.sqlite'
Write-Host 'Indexing fixture' -ForegroundColor Cyan
$indexOut = & $Exe index $work --db $db 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) "$($indexOut -join ' | ')"

$py = Join-Path $WorkDir 'q.py'
@'
import sqlite3, sys, json
c = sqlite3.connect(sys.argv[1])
rows = [{"unit_name": r[0], "norm": r[1], "target": r[2]}
        for r in c.execute("SELECT unit_name, unit_name_norm, target_file_id FROM unit_uses")]
print(json.dumps(rows))
'@ | Set-Content $py -Encoding ASCII
$rows = @(python $py $db | ConvertFrom-Json)

$pySym = Join-Path $WorkDir 'qsym.py'
@'
import sqlite3, sys, json
c = sqlite3.connect(sys.argv[1])
rows = [{"kind": r[0], "name": r[1], "qname": r[2]}
        for r in c.execute("SELECT kind, name, qualified_name FROM symbols ORDER BY id")]
print(json.dumps(rows))
'@ | Set-Content $pySym -Encoding ASCII
$syms = @(python $pySym $db | ConvertFrom-Json)

Check 'both uses rows are present' ($rows.Count -eq 2) "count=$($rows.Count): $($rows | ForEach-Object { $_.unit_name })"

# Premise of the fixture, asserted rather than assumed: the shared tail really
# is ambiguous, so pass 2 is genuinely out of the picture for BOTH rows.
$norms = @($rows | ForEach-Object { $_.norm } | Sort-Object -Unique)
Check 'fixture premise: both rows share ONE tail, so pass 2 cannot resolve either' `
  ($norms.Count -eq 1 -and $norms[0] -eq 'config') "norms=$($norms -join ',')"

$alpha = $rows | Where-Object { $_.unit_name -replace '\s', '' -eq 'Alpha.Config' }
$beta  = $rows | Where-Object { $_.unit_name -replace '\s', '' -eq 'Beta.Config'  }

Check 'control: the PLAIN use resolves via pass 1' `
  ($null -ne $beta -and $null -ne $beta.target) "beta=$($beta | ConvertTo-Json -Compress)"

# The defect itself, stated on the stored value.
Check 'the PADDED use is stored with NO interior whitespace' `
  ($null -ne $alpha -and $alpha.unit_name -eq 'Alpha.Config') `
  "stored=$(if ($alpha) { "'" + $alpha.unit_name + "'" } else { '<missing>' })"

# The consequence, stated separately -- a future change could strip whitespace
# at lookup time and satisfy the check above while leaving this one red.
Check 'the PADDED use RESOLVES to a target file (pass 1 can match it)' `
  ($null -ne $alpha -and $null -ne $alpha.target) `
  "alpha=$($alpha | ConvertTo-Json -Compress)"

# --- WalkUnit: the same node read for the unit's OWN declaration -------------
# Premise first: Gamma must actually have been parsed, or the two checks under
# it would pass by finding nothing.
$gammaUnit = @($syms | Where-Object { $_.kind -eq 'unit' -and ($_.name -replace '\s', '') -eq 'Gamma.Config' })
Check 'fixture premise: the padded DECLARATION parsed and emitted a unit symbol' `
  ($gammaUnit.Count -eq 1) `
  ("unit symbols=[{0}]" -f (($syms | Where-Object { $_.kind -eq 'unit' } | ForEach-Object { "'" + $_.name + "'" }) -join ' '))

Check 'the padded DECLARATION is stored with NO interior whitespace' `
  ($gammaUnit.Count -eq 1 -and $gammaUnit[0].name -eq 'Gamma.Config') `
  ("stored={0}" -f $(if ($gammaUnit.Count) { "'" + $gammaUnit[0].name + "'" } else { '<missing>' }))

# The consequence, stated separately: the declaration's text is the prefix of
# every symbol the unit declares, so a padded name mis-keys them all.
$gammaFn = @($syms | Where-Object { $_.name -eq 'GammaCfg' })
Check 'every symbol in that unit is qualified with the UNPADDED name' `
  ($gammaFn.Count -eq 1 -and $gammaFn[0].qname -eq 'Gamma.Config.GammaCfg') `
  ("qualified_name={0}" -f $(if ($gammaFn.Count) { "'" + $gammaFn[0].qname + "'" } else { '<missing>' }))

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
