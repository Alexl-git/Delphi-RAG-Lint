<#
  run_duplicate_global_decl_library_tier.ps1 -- the LIBRARY tier of
  duplicate-global-decl (owner-designed 2026-09-16,
  docs\INBOX-2026-09-16-duplicate-global-decl-library-tier.md).

  THE ALGORITHM, in the owner's words: "Say you have a global AGlob. Do an
  indexed Library search for AGlob. If it returns a list of units and one of
  those is USED in the linted unit, you have a masking declaration."

  WHAT THIS PINS (the note's own list):
    * a project name that ALSO exists in the library, in a unit the file USES
      -> reported, severity warning, no autofix;
    * the same name where the library unit is NOT used by that file -> SILENT.
      This is the assertion that proves the uses-filter exists at all; without
      it the rule is the flooding version wearing the right name;
    * the 3-declaration case (2+ project units AND the library) -> reported
      with the stronger message;
    * a project-only duplicate -> still reported exactly as today (regression
      control on the existing tier), with NO library wording;
    * an IMPLEMENTATION-section uses counts as "used" -- an unqualified name in
      the implementation resolves through it too;
    * unit-scope suffix: `uses SysUtils` masks against library unit
      `System.SysUtils`.

  Two fixture trees, indexed into two DBs: lib\ -> library-fixture.sqlite (the
  `library-` prefix is what lint-all keys the library slot on) and proj\ ->
  proj.sqlite.

  POSITIVE CONTROL: against the pre-tier engine every library-tier assertion
  is red and every regression-control assertion is green.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-dupglobal-libtier"
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
function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

$lib  = Join-Path $WorkDir 'lib';  New-Item -ItemType Directory $lib  | Out-Null
$proj = Join-Path $WorkDir 'proj'; New-Item -ItemType Directory $proj | Out-Null

# ---- the "library" ---------------------------------------------------------
Write-Ascii (Join-Path $lib 'LibUnitA.pas') @'
unit LibUnitA;

interface

const
  CMaxThings = 10;

type
  TWidget = class
  end;

procedure Frob;

implementation

procedure Frob;
begin
end;

end.
'@
Write-Ascii (Join-Path $lib 'LibUnitB.pas') @'
unit LibUnitB;

interface

var
  GLibOnly: Integer;

implementation

end.
'@
Write-Ascii (Join-Path $lib 'Scope.Suffixed.pas') @'
unit Scope.Suffixed;

interface

const
  CScoped = 1;

implementation

end.
'@

# ---- the "project" ---------------------------------------------------------
# UsesA: masks CMaxThings, and USES LibUnitA in the interface -> REPORTED.
Write-Ascii (Join-Path $proj 'UsesA.pas') @'
unit UsesA;

interface

uses
  LibUnitA;

const
  CMaxThings = 20;

implementation

end.
'@
# NoUse: re-declares TWidget but never uses LibUnitA -> SILENT (the uses-filter).
Write-Ascii (Join-Path $proj 'NoUse.pas') @'
unit NoUse;

interface

type
  TWidget = class
  end;

implementation

end.
'@
# Three1 + Three2: Frob in two project units AND in the library; Three1 uses it
# -> the stronger 3-declaration message. (The project tier ALSO reports Frob as
# a project duplicate, exactly as today.)
Write-Ascii (Join-Path $proj 'Three1.pas') @'
unit Three1;

interface

uses
  LibUnitA;

procedure Frob;

implementation

procedure Frob;
begin
end;

end.
'@
Write-Ascii (Join-Path $proj 'Three2.pas') @'
unit Three2;

interface

procedure Frob;

implementation

procedure Frob;
begin
end;

end.
'@
# Dup1 + Dup2: a project-only duplicate, no library involvement -> regression
# control on the existing tier.
Write-Ascii (Join-Path $proj 'Dup1.pas') @'
unit Dup1;

interface

const
  CProjOnly = 1;

implementation

end.
'@
Write-Ascii (Join-Path $proj 'Dup2.pas') @'
unit Dup2;

interface

const
  CProjOnly = 1;

implementation

end.
'@
# ImplUse: uses LibUnitB in the IMPLEMENTATION section only -> still REPORTED.
Write-Ascii (Join-Path $proj 'ImplUse.pas') @'
unit ImplUse;

interface

var
  GLibOnly: Integer;

implementation

uses
  LibUnitB;

end.
'@
# Scoped: `uses Suffixed` against library unit `Scope.Suffixed` -> REPORTED.
Write-Ascii (Join-Path $proj 'Scoped.pas') @'
unit Scoped;

interface

uses
  Suffixed;

const
  CScoped = 2;

implementation

end.
'@

$libDb  = Join-Path $WorkDir 'library-fixture.sqlite'
$projDb = Join-Path $WorkDir 'proj.sqlite'
Write-Host 'Indexing library and project fixtures' -ForegroundColor Cyan
& $Exe index $lib  --db $libDb  *> $null; Check 'library index exits 0' ($LASTEXITCODE -eq 0)
& $Exe index $proj --db $projDb *> $null; Check 'project index exits 0' ($LASTEXITCODE -eq 0)

Push-Location $proj
try {
  $raw = (& $Exe lint-all --db $projDb --db $libDb --quiet --json 2>$null) -join "`n"
  $exit = $LASTEXITCODE
} finally { Pop-Location }
$doc = $null
try { $doc = $raw | ConvertFrom-Json } catch { }
Check 'lint-all --json parses' ($null -ne $doc) "exit=$exit raw=$($raw.Substring(0,[Math]::Min(600,$raw.Length)))"
if ($null -eq $doc) { Write-Host 'run_duplicate_global_decl_library_tier: FAIL' -ForegroundColor Red; exit 1 }

# lint-all --json: findings may sit at the root or under .findings; take either.
$all = @()
if ($doc.PSObject.Properties['findings']) { $all = @($doc.findings) } else { $all = @($doc) }
$dup = @($all | Where-Object { $_.rule -eq 'duplicate-global-decl' -or $_.rule_id -eq 'duplicate-global-decl' -or $_.ruleId -eq 'duplicate-global-decl' })
Write-Host ("  duplicate-global-decl findings: {0}" -f $dup.Count) -ForegroundColor DarkGray
foreach ($d in $dup) { Write-Host ("    {0}:{1}  {2}" -f (Split-Path -Leaf $d.file_path), $d.start_line, $d.message.Substring(0,[Math]::Min(140,$d.message.Length))) -ForegroundColor DarkGray }

function Msgs([string]$name) { @($dup | Where-Object { $_.message -match "^$name\b" } | ForEach-Object { $_.message }) }

Write-Host ''
Write-Host '=== library tier ===' -ForegroundColor Cyan
$m = Msgs 'CMaxThings'
Check 'CMaxThings (UsesA uses LibUnitA): REPORTED' ($m.Count -eq 1) "n=$($m.Count)"
Check '  ... names library unit LibUnitA and the masking site' ($m -join ' ' -cmatch 'library unit LibUnitA' -and ($m -join ' ') -cmatch 'UsesA\.pas:\d+ uses LibUnitA') "msg=$m"
Check '  ... severity warning' (@($dup | Where-Object { $_.message -match '^CMaxThings' -and $_.severity -eq 'warning' }).Count -eq 1) ''
Check '  ... anchored in UsesA.pas' (@($dup | Where-Object { $_.message -match '^CMaxThings' -and $_.file_path -match 'UsesA\.pas$' }).Count -eq 1) ''
$m = Msgs 'TWidget'
Check 'TWidget (NoUse does NOT use LibUnitA): SILENT -- the uses-filter' ($m.Count -eq 0) "msg=$m"
$m = Msgs 'GLibOnly'
Check 'GLibOnly (ImplUse uses LibUnitB in IMPLEMENTATION): REPORTED' ($m.Count -eq 1) "n=$($m.Count) msg=$m"
$m = Msgs 'CScoped'
Check 'CScoped (uses Suffixed vs library Scope.Suffixed): REPORTED by unit-scope suffix' ($m.Count -eq 1) "n=$($m.Count) msg=$m"
$m = Msgs 'Frob'
$three = @($m | Where-Object { $_ -cmatch 'project units AND in library unit LibUnitA' })
Check 'Frob (Three1+Three2+library): the stronger 3-declaration message' ($three.Count -eq 1) "msgs=$m"
Check '  ... it counts 2 project units' ($three -join ' ' -match 'in 2 project units') "msg=$three"
$projTier = @($m | Where-Object { $_ -match 'declared at interface level in 2 units' })
Check 'Frob: the project tier STILL reports the project duplicate (unchanged)' ($projTier.Count -eq 1) "msgs=$m"

Write-Host ''
Write-Host '=== regression control: the project tier is untouched ===' -ForegroundColor Cyan
$m = Msgs 'CProjOnly'
Check 'CProjOnly (Dup1+Dup2, not in library): reported exactly as today' ($m.Count -eq 1) "n=$($m.Count)"
Check '  ... with NO library wording' (-not (($m -join ' ') -match 'library')) "msg=$m"
Check 'no finding mentions a library unit the file does not use' (-not (($dup | ForEach-Object { $_.message }) -join ' ' -match 'NoUse\.pas')) ''

Write-Host ''
Write-Host '=== without a library store the tier is off, the project tier is not ===' -ForegroundColor Cyan
Push-Location $proj
try { $raw2 = (& $Exe lint-all --db $projDb --quiet --json 2>$null) -join "`n" } finally { Pop-Location }
$doc2 = $null; try { $doc2 = $raw2 | ConvertFrom-Json } catch { }
Check 'project-only lint-all parses' ($null -ne $doc2) ''
if ($null -ne $doc2) {
  $all2 = if ($doc2.PSObject.Properties['findings']) { @($doc2.findings) } else { @($doc2) }
  $dup2 = @($all2 | Where-Object { ($_.rule -eq 'duplicate-global-decl' -or $_.rule_id -eq 'duplicate-global-decl' -or $_.ruleId -eq 'duplicate-global-decl') })
  # NOTE: lint-all may still resolve the MACHINE's real library index through the
  # manifest when only one --db is given, so this control asserts only that the
  # fixture-library findings (which no real RTL declares) are absent.
  Check 'no CMaxThings/GLibOnly/CScoped finding without the fixture library' (@($dup2 | Where-Object { $_.message -match '^(CMaxThings|GLibOnly|CScoped)\b' }).Count -eq 0) ''
  Check 'CProjOnly still reported' (@($dup2 | Where-Object { $_.message -match '^CProjOnly\b' }).Count -eq 1) ''
}

Write-Host ''
if ($script:Failed) { Write-Host 'run_duplicate_global_decl_library_tier: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_duplicate_global_decl_library_tier: PASS' -ForegroundColor Green
exit 0
