<#
  run_doc_multidb_overload_tag.ps1 -- a caller found in an EXTRA store gets its
  overload tag computed from THAT store, not from the primary one.

  THE BUG. TDocFactsBuilder.Build's nested ToFactRef closed over AStore -- the
  PRIMARY store -- and passed it to OverloadArityTag together with
  ARC.EnclosingSymbolId. For rows produced by the EXTRA-STORE fan-out, that id
  belongs to the extra store. Symbol ids are numbered PER DATABASE, so the
  primary store either has no symbol at that number or has an unrelated one, and
  the rendered caller silently gained or lost an overload suffix ('/2') computed
  from a routine that has nothing to do with it.

  Silent by construction: nothing fails, no row is missing, only the suffix is
  wrong. It was found in 2026-08-16 while measuring OverloadArityTag, not by any
  test -- which is what this file is for.

  WHY THE ASSERTION IS "THE TAG IS PRESENT" RATHER THAN A FORCED ID COLLISION.
  Engineering two databases into numbering the same id for two chosen symbols is
  brittle and would silently stop testing anything the first time the indexer's
  insertion order changed. Instead the fixture makes the EXTRA store's caller a
  genuine OVERLOAD SET member, so the CORRECT answer carries a tag -- and the
  primary store (which holds only uLib) cannot produce that tag for that id by
  any route. Fixed -> tag present. Broken -> tag absent.

  THE DE-VACUATOR is the second target: a caller that is NOT overloaded must
  render with NO tag. Without it, an assertion that merely finds '/1' somewhere
  would also pass if the engine started tagging everything.

  Layout mirrors run_doc_multidb.ps1: `document --unit` takes its PRIMARY store
  from the FIRST --db, every later --db being an extra store, so the target
  unit's own db is passed first. (Owner ruling 2026-08-25 flipped this from
  last-wins; see that suite's header.)
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-doc-multidb-overload"
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
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# --- The library under documentation. TWO targets, so one can be the control. ----
$libDir = Join-Path $WorkDir 'lib'
New-Item -ItemType Directory $libDir | Out-Null
Set-Content (Join-Path $libDir 'uLib.pas') -Encoding ascii -NoNewline -Value @'
unit uLib;

interface

function Compute(const A: Integer): Integer;
function Tally(const A: Integer): Integer;

implementation

function Compute(const A: Integer): Integer;
begin
  Result := A * 2;
end;

function Tally(const A: Integer): Integer;
begin
  Result := A + 1;
end;

end.
'@

# --- The caller side, indexed into a SEPARATE db (the extra store). --------------
# Run is a genuine OVERLOAD SET; Solo is not. Compute is called from an overload
# member, Tally from the plain one.
$appDir = Join-Path $WorkDir 'app'
New-Item -ItemType Directory $appDir | Out-Null
Set-Content (Join-Path $appDir 'uApp.pas') -Encoding ascii -NoNewline -Value @'
unit uApp;

interface

uses uLib;

procedure Run(A: Integer); overload;
procedure Run(const A: string); overload;
procedure Solo;

implementation

procedure Run(A: Integer);
begin
  Compute(21);
end;

procedure Run(const A: string);
begin
end;

procedure Solo;
begin
  Tally(7);
end;

end.
'@

$appDb = Join-Path $WorkDir 'app.sqlite'
& $Exe index $appDir --db $appDb --quiet | Out-Null
Check 'app (extra store) db built' (Test-Path $appDb)

# The target unit's own db, passed LAST so it is the primary store.
$applyDir = Join-Path $WorkDir 'apply'
New-Item -ItemType Directory $applyDir | Out-Null
$applyFile = Join-Path $applyDir 'uLib.pas'
Copy-Item (Join-Path $libDir 'uLib.pas') $applyFile -Force
$primDb = Join-Path $WorkDir 'prim.sqlite'
& $Exe index $applyDir --db $primDb --quiet | Out-Null
Check 'primary db built' (Test-Path $primDb)

& $Exe document --unit $applyFile --db $primDb --db $appDb --apply --no-backup --quiet | Out-Null
Check 'document --apply exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

$src = [IO.File]::ReadAllText($applyFile)

# --- Preconditions: the extra-store bucket fired at all. ------------------------
Write-Host ''
Write-Host 'preconditions -- the cross-DB caller bucket is what is being tested' -ForegroundColor Cyan
Check 'precondition: a Called from: line exists' ($src -match 'Called from:') $src
Check 'precondition: the EXTRA store surfaced uApp as a caller' `
  ($src -match 'Called from:[^\r\n]*uApp') `
  "without this the whole suite is vacuous -- the extra-store fan-out never ran"

# --- THE ASSERT. ----------------------------------------------------------------
Write-Host ''
Write-Host 'the overload tag must come from the EXTRA store' -ForegroundColor Cyan
Check 'ASSERT: the overloaded caller renders uApp.Run WITH its arity tag' `
  ($src -match 'uApp\.Run/\d') `
  "the primary db holds only uLib, so it cannot produce this tag for uApp.Run's id by any route -- $src"

# --- THE DE-VACUATOR. -----------------------------------------------------------
Write-Host ''
Write-Host 'de-vacuator -- a NON-overloaded caller must carry no tag' -ForegroundColor Cyan
Check 'ASSERT: uApp.Solo renders WITHOUT a tag' `
  (($src -match 'uApp\.Solo') -and ($src -notmatch 'uApp\.Solo/')) `
  "if this fails the engine tags everything and the assert above proves nothing -- $src"

Write-Host ''
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
