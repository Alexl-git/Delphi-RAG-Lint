<#
  run_uses_padded_name.ps1 -- a used unit's name is not the source text between
  its dots.

  THE BUG (ported from feat/autodoc-phase3; counts re-derived on this machine by
  tools/measure/phase1_verify.py, read-only). Both sites that read a `moduleName`
  node used `Trim`. A moduleName spans the WHOLE dotted name, so its text carries
  whatever the author wrote BETWEEN the tokens, and `Trim` removes only the ends.
  This repo aligns its own `uses` clauses, so `DRagLint.Core   .Model` was stored
  in unit_uses.unit_name verbatim -- interior padding and all.

  That is not cosmetic. ResolveUnitUseTargets' rule A is an equality against
  `LOWER(unit_name)`, which a padded value can never satisfy, so the row is left
  unresolved -- and rule B cannot rescue it, because rule B is BARE-ONLY and a
  padded dotted name still contains its dots (Storage.SQLite.pas, 'rule B is
  bare-only'). Measured before the fix: 147 of 1836 unit_uses rows in this repo's
  own index carry embedded whitespace, 137 of them unresolved; 286 of 14223 in
  ORM3, 285 unresolved; 0 in library-Win64 and 0 in M2022 -- zero in third-party
  code, because the alignment is our house style.

  TWO SITES, and the second is the expensive one. WalkUsesClause feeds
  unit_uses.unit_name (one edge per padded row). WalkUnit feeds the skUnit
  symbol's own name AND the qualified-name prefix of every symbol the unit
  declares, so one padded `unit` line would mis-key a whole unit's rows. The
  second site is LATENT -- 0 of 7098 kind='unit' symbols across
  Delphi-RAG-lint / ORM3 / library-Win64 / M2022 carry embedded whitespace,
  because we align `uses` clauses and not `unit` lines -- which is precisely why
  it needs a fixture rather than a live query.

  WHAT EACH CHECK IS FOR:
    P1/P2  de-vacuators, read from the fixture BYTES on disk: the padding really
           is there, and it really includes #11/#12. Without these the whole
           suite could pass on a fixture that lost its padding to an editor.
    A1     the stored unit_name has no whitespace   -- the requirement
    A2     ...and the row RESOLVES                  -- the consequence
    A3     CONTROL: an unpadded row in the same clause resolves too, so a red A2
           is this defect and not a broken resolver
    A4     sweep: no unit_uses row anywhere carries embedded whitespace
    B1     site 2: the skUnit symbol's own name is clean
    B2     site 2: the qualified-name PREFIX of a symbol the unit declares is
           clean -- the consequence that makes site 2 worth fixing
    B3     site 2 covers #11/#12 specifically, i.e. `C <= ' '` and not a
           four-way match on #32/#9/#13/#10

  NOT COVERED, and said so in the code too: a comment written inside the dotted
  name (`Alpha.{x}Config`) is still stored verbatim.

  Usage: pwsh -File tests/autotest/run_uses_padded_name.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-uses-padded-name"
)
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
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$work = Join-Path $WorkDir 'fixture'
New-Item -ItemType Directory $work | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

Write-Ascii (Join-Path $work 'Alpha.Config.pas') @'
unit Alpha.Config;

// The unit the PADDED `uses Alpha  .Config` names. It shares its dotted TAIL
// ('config') with Beta.Config, which costs nothing here but keeps the fixture
// honest if rule B ever stopped being bare-only: two units carrying one tail is
// ambiguous, so no tail-based pass could rescue the padded row either.

interface

implementation

end.
'@

Write-Ascii (Join-Path $work 'Beta.Config.pas') @'
unit Beta.Config;

// The CONTROL target: `uses Beta.Config` is written without padding in the same
// clause, so if A2 is red and A3 is green the defect is the padding and not the
// resolver.

interface

implementation

end.
'@

# --- Site 2. The `unit` line pads its OWN dotted name, with SPACE + #11 (VT) +
#     #12 (FF). VT and FF are Pascal whitespace and would survive a four-way
#     match on #32/#9/#13/#10, invisibly -- neither renders. Built with [char]
#     escapes so this .ps1 stays 7-bit ASCII with no stray control bytes.
$pad = ' ' + [char]11 + [char]12
Write-Ascii (Join-Path $work 'Gamma.Config.pas') @"
unit Gamma$pad.Config;

// The padding above is SPACE + #11 + #12. This value becomes the skUnit symbol's
// name AND the qualified-name prefix of TGammaCtl below.

interface

type
  TGammaCtl = class
  private
    FMarker: Integer;
  published
    property Marker: Integer read FMarker write FMarker;
  end;

implementation

end.
"@

Write-Ascii (Join-Path $work 'PadUser.pas') @'
unit PadUser;

interface

uses
  Alpha  .Config,   // PADDED, the house-style alignment that produced 147 rows here
  Beta.Config;      // the unpadded control

implementation

end.
'@

$db = Join-Path $WorkDir 'padded.sqlite'
Write-Host 'Indexing fixture' -ForegroundColor Cyan
$indexOut = & $Exe index $work --db $db 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE; $($indexOut -join ' | ')"
Check 'index reports 0 parse errors (a padded dotted name is legal Delphi and must parse)' `
  (-not (($indexOut -join ' ') -match '[1-9]\d* errors')) "$($indexOut -join ' | ')"

# --- Probes. ----------------------------------------------------------------------
$script:PySql = Join-Path $WorkDir 'sql.py'
Write-Ascii $script:PySql @'
import sqlite3, sys
con = sqlite3.connect("file:%s?mode=ro" % sys.argv[1].replace("\\", "/"), uri=True)
print("\n".join("|".join("" if v is None else str(v) for v in r)
                for r in con.execute(sys.argv[2]).fetchall()))
con.close()
'@
function Sql([string]$Q) { return ((python $script:PySql $db $Q) -join "`n").Trim() }
# Any byte <= 0x20 anywhere in the value. GLOB, not LIKE: LIKE would need one
# pattern per byte and is case-folding; a character class is exact.
$wsGlob = "GLOB '*[' || char(32) || char(9) || char(10) || char(11) || char(12) || char(13) || ']*'"

# --- P1/P2. The fixture really carries the padding. --------------------------------
Write-Host ''
Write-Host 'de-vacuators: the fixture bytes on disk' -ForegroundColor Cyan
$userBytes  = [System.IO.File]::ReadAllBytes((Join-Path $work 'PadUser.pas'))
$userText   = [System.Text.Encoding]::ASCII.GetString($userBytes)
Check 'P1: PadUser.pas really contains "Alpha  .Config" (interior spaces)' ($userText -match 'Alpha {2}\.Config') `
  "-- if an editor collapsed the alignment the rest of this suite would pass for the wrong reason"
$gammaBytes = [System.IO.File]::ReadAllBytes((Join-Path $work 'Gamma.Config.pas'))
$hasVt = $gammaBytes -contains 11
$hasFf = $gammaBytes -contains 12
Check 'P2: Gamma.Config.pas really contains a #11 and a #12 byte' ($hasVt -and $hasFf) `
  "VT=$hasVt FF=$hasFf -- these two are what separate `C <= ' '` from a four-way whitespace match"

# --- A. Site 1: unit_uses.unit_name. ----------------------------------------------
Write-Host ''
Write-Host 'site 1 -- unit_uses.unit_name (WalkUsesClause)' -ForegroundColor Cyan
$a1 = Sql "SELECT COUNT(*) FROM unit_uses WHERE unit_name = 'Alpha.Config'"
Check "A1: the padded clause stored unit_name EXACTLY 'Alpha.Config'" ($a1 -eq '1') `
  "rows=$a1 -- stored values now: [$((Sql "SELECT GROUP_CONCAT(unit_name, ' ; ') FROM unit_uses"))]"

$a2 = Sql "SELECT COALESCE(f.path,'<UNRESOLVED>') FROM unit_uses u LEFT JOIN files f ON f.id=u.target_file_id WHERE u.unit_name='Alpha.Config'"
Check "A2: ...and the row RESOLVES to Alpha.Config.pas" ($a2 -match '(?i)[\\/]Alpha\.Config\.pas$') `
  "target=$a2 -- rule A is an equality on LOWER(unit_name), which a padded value can never satisfy, and rule B is bare-only so it cannot rescue a dotted one"

$a3 = Sql "SELECT COALESCE(f.path,'<UNRESOLVED>') FROM unit_uses u LEFT JOIN files f ON f.id=u.target_file_id WHERE u.unit_name='Beta.Config'"
Check "A3 control: the UNPADDED 'Beta.Config' in the same clause resolves too" ($a3 -match '(?i)[\\/]Beta\.Config\.pas$') `
  "target=$a3 -- if this is red the resolver is broken and A2 says nothing about padding"

$a4 = Sql "SELECT COUNT(*) FROM unit_uses WHERE unit_name $wsGlob"
Check 'A4 sweep: no unit_uses row anywhere carries embedded whitespace' ($a4 -eq '0') "rows with whitespace=$a4"

# --- B. Site 2: the skUnit symbol name and every qualified-name prefix. -----------
Write-Host ''
Write-Host 'site 2 -- the unit symbol and the qualified-name prefix (WalkUnit)' -ForegroundColor Cyan
$b1 = Sql "SELECT COUNT(*) FROM symbols WHERE kind='unit' AND name='Gamma.Config'"
Check "B1: the skUnit symbol's own name is EXACTLY 'Gamma.Config'" ($b1 -eq '1') `
  "rows=$b1 -- unit names stored: [$((Sql "SELECT GROUP_CONCAT(name, ' ; ') FROM symbols WHERE kind='unit'"))]"

$b2 = Sql "SELECT COUNT(*) FROM symbols WHERE qualified_name='Gamma.Config.TGammaCtl'"
Check "B2: a symbol the unit declares is keyed 'Gamma.Config.TGammaCtl'" ($b2 -eq '1') `
  "rows=$b2 -- qnames seen: [$((Sql "SELECT GROUP_CONCAT(qualified_name, ' ; ') FROM symbols WHERE name='TGammaCtl'"))]"

$b3 = Sql "SELECT COUNT(*) FROM symbols WHERE kind='unit' AND name $wsGlob"
Check 'B3 sweep: no kind=unit symbol name carries whitespace, #11 and #12 included' ($b3 -eq '0') "rows with whitespace=$b3"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
