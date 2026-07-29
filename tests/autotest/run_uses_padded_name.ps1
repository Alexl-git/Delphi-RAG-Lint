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

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-uses-padded).
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

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
