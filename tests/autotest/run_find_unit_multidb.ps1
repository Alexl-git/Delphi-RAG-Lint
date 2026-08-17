<#
  run_find_unit_multidb.ps1 -- find-unit reads EVERY --db, and never invents a
  second uses clause.

  TWO BUGS, both measured on real projects before the fix.

  1. ORDER-DEPENDENT ANSWER. DoFindUnit read AArgs.DbPath -- the LAST --db --
     and opened one store, while ParseArgs accepted every earlier --db and
     appended it to DbPaths. The order the standing "authoritative set =
     platform library + project DB" rule asks for was the broken one:
       --db <library> --db <project>  -> Could not resolve a unit declaring "TEdit"
       --db <project> --db <library>  -> uses Vcl.StdCtrls
     "Could not resolve" is indistinguishable from "no such symbol", so it
     answered confidently and wrongly for every RTL/VCL type.

  2. --apply COULD WRITE CODE THAT DOES NOT COMPILE. Build emitted a fresh
     `uses <Unit>;` block whenever the file's uses set came back empty --
     conflating "the file declares no uses clause" with "this store does not
     index the file". Against a library-only --db it proposed
     `insert after line 2176: uses Vcl.StdCtrls;` into a unit whose
     implementation uses clause is at 2180-2200, i.e. a SECOND clause in the
     same section.

  WHY THE ASSERTIONS BELOW ARE SHAPED THIS WAY.

  * THE POSITIVE CONTROL IS "already in the uses clause", and it is chosen
    because NO SINGLE-STORE IMPLEMENTATION CAN PASS IT. Answering it needs the
    LIBRARY store (to learn that THelper is declared by LibHelper) AND the
    PROJECT store (to learn that ProjApp already uses LibHelper) in the same
    call. A test that only checked "TWidget resolves" would pass with the
    already-imported set still empty -- which is exactly the state the bug left
    it in, so such a test proves nothing about the fix.

  * THE FRESH-BLOCK CASE IS ALSO ASSERTED, as the de-vacuator for fix 2. The fix
    is a refusal, and a refusal can always be over-applied: `Exit` on every
    empty uses set would kill the feature outright and still turn the refusal
    check green. So a file that GENUINELY has no uses clause, indexed in the
    project DB, must STILL get its fresh block.

  Usage: pwsh -File tests/autotest/run_find_unit_multidb.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-find-unit-multidb"
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
function NewDir([string]$Name) {
  $p = Join-Path $WorkDir $Name
  New-Item -ItemType Directory $p | Out-Null
  return $p
}

# --- The LIBRARY side. Two units, neither of which knows any project file. ---------
$libSrc = NewDir 'libsrc'
Write-Ascii (Join-Path $libSrc 'LibWidget.pas') @'
unit LibWidget;

interface

type
  TWidget = class(TObject)
  public
    procedure Draw;
  end;

implementation

procedure TWidget.Draw;
begin
end;

end.
'@
Write-Ascii (Join-Path $libSrc 'LibHelper.pas') @'
unit LibHelper;

interface

type
  THelper = class(TObject)
  public
    procedure Help;
  end;

implementation

procedure THelper.Help;
begin
end;

end.
'@

# --- The PROJECT side. --------------------------------------------------------------
$projSrc = NewDir 'projsrc'
# ProjApp ALREADY uses LibHelper -- that is the whole point of the positive
# control below. It does NOT use LibWidget, so TWidget is a genuine insertion.
Write-Ascii (Join-Path $projSrc 'ProjApp.pas') @'
unit ProjApp;

interface

type
  TProjThing = class(TObject)
  public
    procedure Run;
  end;

implementation

uses
  LibHelper
  , System.SysUtils
  ;

procedure TProjThing.Run;
begin
end;

end.
'@
# A unit with NO uses clause anywhere -- the de-vacuator for the refusal.
Write-Ascii (Join-Path $projSrc 'ProjBare.pas') @'
unit ProjBare;

interface

type
  TBareThing = class(TObject)
  public
    procedure Go;
  end;

implementation

procedure TBareThing.Go;
begin
end;

end.
'@

# The `library-` filename prefix is how the engine tells a library index from a
# project one; keep it.
$libDb  = Join-Path $WorkDir 'library-Test.sqlite'
$projDb = Join-Path $WorkDir 'proj.sqlite'

Write-Host 'Indexing fixtures' -ForegroundColor Cyan
foreach ($pair in @(@($libSrc, $libDb), @($projSrc, $projDb))) {
  $out = & $Exe index $pair[0] --db $pair[1] --quiet 2>&1
  Check ("index {0}" -f (Split-Path $pair[1] -Leaf)) ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE; $($out -join ' | ')"
}

$appFile  = Join-Path $projSrc 'ProjApp.pas'
$bareFile = Join-Path $projSrc 'ProjBare.pas'

function FindUnit([string]$Name, [string]$InFile, [string[]]$Dbs) {
  $dbArgs = @()
  foreach ($d in $Dbs) { $dbArgs += '--db'; $dbArgs += $d }
  $out = @(& $Exe find-unit --name $Name --in $InFile @dbArgs --quiet 2>&1) | ForEach-Object { "$_" }
  $script:LastExit = $LASTEXITCODE
  return ($out -join "`n")
}

# --- 1. The exact order that used to fail. -------------------------------------------
Write-Host ''
Write-Host 'library FIRST, project second -- the documented order, and the broken one' -ForegroundColor Cyan

$r = FindUnit 'TWidget' $appFile @($libDb, $projDb)
Check 'ASSERT: resolves LibWidget (used to say "Could not resolve")' `
  (($r -match 'LibWidget') -and ($script:LastExit -eq 0)) "exit=$script:LastExit; $r"
Check 'ASSERT: appends INSIDE the existing clause, not as a fresh block' `
  (($r -match 'insert at L\d+:C\d+') -and ($r -notmatch 'uses LibWidget;')) `
  "a fresh `"uses LibWidget;`" block here would be a SECOND implementation uses clause -- $r"

# --- 2. Swapped order must give the SAME answer. -------------------------------------
Write-Host ''
Write-Host 'project first, library second -- the order that always worked' -ForegroundColor Cyan

$rSwap = FindUnit 'TWidget' $appFile @($projDb, $libDb)
Check 'ASSERT: the two orders agree, so the answer is no longer order-dependent' `
  ($rSwap -eq $r) "swapped=$rSwap`n---`noriginal=$r"

# --- 3. THE POSITIVE CONTROL. No single store can answer this. -----------------------
Write-Host ''
Write-Host 'positive control -- "already in uses" needs BOTH stores at once' -ForegroundColor Cyan

$rAlready = FindUnit 'THelper' $appFile @($libDb, $projDb)
Check 'ASSERT: THelper reports its unit is ALREADY in the uses clause' `
  (($rAlready -match 'already in the uses clause') -and ($script:LastExit -eq 0)) `
  "exit=$script:LastExit; $rAlready -- the LIBRARY store knows THelper is in LibHelper, the PROJECT store knows ProjApp uses LibHelper; neither alone can say this"

# --- 4. The refusal (fix 2), and its de-vacuator. ------------------------------------
Write-Host ''
Write-Host 'a store that does not index the target file must REFUSE, not guess' -ForegroundColor Cyan

$rLibOnly = FindUnit 'TWidget' $appFile @($libDb)
Check 'ASSERT: library-only proposes NO edit rather than a second uses clause' `
  (($rLibOnly -notmatch 'uses LibWidget;') -and ($script:LastExit -eq 1)) `
  "exit=$script:LastExit; $rLibOnly -- this is the shape that wrote an uncompilable second clause under --apply"

Write-Host ''
Write-Host 'de-vacuator -- a file that GENUINELY has no uses clause still gets one' -ForegroundColor Cyan

$rBare = FindUnit 'TWidget' $bareFile @($libDb, $projDb)
Check 'ASSERT: ProjBare (no uses clause, and INDEXED) still gets a fresh block' `
  (($rBare -match 'uses LibWidget;') -and ($script:LastExit -eq 0)) `
  "exit=$script:LastExit; $rBare -- if this fails the refusal was over-applied and the feature is dead"

# --- 5. Controls. --------------------------------------------------------------------
Write-Host ''
Write-Host 'controls' -ForegroundColor Cyan

$rMissing = FindUnit 'TNoSuchTypeAnywhere' $appFile @($libDb, $projDb)
Check 'control: a genuinely absent symbol still reports "Could not resolve" / exit 1' `
  (($rMissing -match 'Could not resolve') -and ($script:LastExit -eq 1)) "exit=$script:LastExit; $rMissing"

Write-Host ''
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
