<#
  run_object_leak_split_chain.ps1 -- FP2b: object-leak must NOT fire on a
  project-local class whose ancestry CROSSES INTO the library index and which is
  constructed with a non-nil owner.

  THE SHAPE. `TMyForm = class(TForm)` is declared in a project unit; TForm lives
  in Vcl.Forms, which no project index carries. So:

    - the PROJECT store's ancestor walk stops at TForm, a name-only unresolved
      leaf, and never reaches TComponent  -> IsDescendantOf says False;
    - the LIBRARY store has never heard of TMyForm at all                -> False.

  Both stores answered honestly about their own index, and between them they
  said "not a component" about a form. ConstructorTransfersOwnership therefore
  never fired and `f := TMyForm.Create(AOwner)` was reported as a leak. 3 of the
  5 object-leak findings on this repo were that exact shape.

  The fix is THE ANCESTRY BRIDGE (the same move Harvest makes in AstChecks --
  search that file for the phrase): ask the project store which ancestor names
  it could NOT resolve, then continue the climb by name in the library store.

  WHY THIS IS A SEPARATE RUNNER FROM run_object_leak_owned.ps1, and it is not a
  style choice. That guard drives `check-ast`, and check-ast passes nil as the
  library store (DRagLint.CLI.pas, DoCheckAst -- it says so in a comment: "No
  library store on this path"). A split-chain case added there could never
  exercise the bridge; it would assert against a store configuration in which
  the bridge is switched off by construction, and would have passed both before
  and after the fix. The bridge is reachable from `lint` and `lint-all` only, so
  this runner uses `lint --library-db`.

  Fixture: TWO units in TWO folders, indexed into TWO databases, because one
  database would resolve the ancestor edge and destroy the very split the test
  is about.
    tests\lint-project\objleak-split\lib\objleaksplitlib.pas  TComponent, TForm
    tests\lint-project\objleak-split\app\objleaksplitapp.pas  TMyForm, TPlainThing

  Cases:
    - MakeOwnedSplitForm  : TMyForm.Create(AOwner)  -> must NOT be flagged (the FP)
    - LeakNilOwnedSplitForm: TMyForm.Create(nil)    -> MUST still be flagged
    - LeakPlainThing      : TPlainThing.Create      -> MUST still be flagged

  The two controls are what stop this passing for the wrong reason. An assertion
  that only checks "the FP is gone" also passes with object-leak switched off,
  with the fixture failing to index, and with the bridge suppressing everything
  it touches. Every assertion below is scoped to rule == 'object-leak' AND to a
  specific line, so "nothing fired at all" cannot read as success.

  RED-CHECK: against a build with the DescendsViaSplitChain call reverted, case 1
  FAILS and cases 2 and 3 still PASS.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe"
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

# tree-sitter Win64 DLLs must sit beside the exe (mirrors _manifest_common.ps1).
$dllSrc = "$PSScriptRoot\..\..\third_party\dll-win64"
if (Test-Path $dllSrc) {
  Get-ChildItem "$dllSrc\*.dll" | ForEach-Object {
    $dst = Join-Path (Split-Path $Exe) $_.Name
    if (-not (Test-Path $dst)) { Copy-Item $_.FullName $dst }
  }
}

$root   = (Resolve-Path (Join-Path $PSScriptRoot '..\lint-project\objleak-split')).Path
$libDir = Join-Path $root 'lib'
$appDir = Join-Path $root 'app'
$pas    = Join-Path $appDir 'objleaksplitapp.pas'

$libDb = Join-Path $env:TEMP 'objleak_split_lib.sqlite'
$appDb = Join-Path $env:TEMP 'objleak_split_app.sqlite'
foreach ($d in @($libDb, $appDb)) { if (Test-Path $d) { Remove-Item $d -Force } }

& $Exe index $libDir --db $libDb 2>&1 | Out-Null
Check 'library index exits 0' ($LASTEXITCODE -eq 0)
& $Exe index $appDir --db $appDb 2>&1 | Out-Null
Check 'project index exits 0' ($LASTEXITCODE -eq 0)
Check 'both dbs built' ((Test-Path $libDb) -and (Test-Path $appDb))

# The split itself is a PRECONDITION, not an incidental. If a future indexing
# change resolved TForm inside the project db, the ancestry would no longer be
# split and every assertion below would pass without the bridge ever running --
# the fixture would have stopped reproducing the defect while staying green.
$anc = & $Exe query --name TMyForm --db $appDb --json 2>$null
$ancTxt = ($anc -join "`n")
Check 'precondition: fixture indexed TMyForm in the project db' ($ancTxt -match 'TMyForm')

$raw = & $Exe lint $pas --db $appDb --library-db $libDb --rule object-leak --json 2>$null
$txt = ($raw -join "`n"); $b = $txt.IndexOf('[')
$findings = @()
if ($b -ge 0) { try { $findings = @(($txt.Substring($b) | ConvertFrom-Json)) } catch { $findings = @() } }

$leaks = @($findings | Where-Object { $_.rule -eq 'object-leak' })
Write-Host ("object-leak findings ({0}):" -f $leaks.Count)
$leaks | ForEach-Object { Write-Host ("  object-leak:{0} [{1}] {2}" -f $_.start_line, $_.severity, $_.message) }

# Line numbers are asserted against the fixture, which is frozen alongside this
# guard. Read them back so a fixture edit fails loudly here instead of silently
# aiming an assertion at a blank line.
$src = Get-Content $pas
function LineOf([string]$needle) {
  for ($i = 0; $i -lt $src.Count; $i++) { if ($src[$i] -match [regex]::Escape($needle)) { return $i + 1 } }
  return -1
}
$ownedLine = LineOf 'f := TMyForm.Create(AOwner);'
$nilLine   = LineOf 'f := TMyForm.Create(nil);'
$plainLine = LineOf 'p := TPlainThing.Create;'
Check 'fixture lines located' (($ownedLine -gt 0) -and ($nilLine -gt 0) -and ($plainLine -gt 0)) `
  ("owned=$ownedLine nil=$nilLine plain=$plainLine")

$ownedFlagged = @($leaks | Where-Object { $_.start_line -eq $ownedLine }).Count -gt 0
$nilFlagged   = @($leaks | Where-Object { $_.start_line -eq $nilLine   }).Count -gt 0
$plainFlagged = @($leaks | Where-Object { $_.start_line -eq $plainLine }).Count -gt 0

Check "split-chain owner-parented TMyForm.Create(AOwner) NOT flagged (line $ownedLine)" (-not $ownedFlagged)
Check "control: TMyForm.Create(nil) IS still flagged (line $nilLine)"                    $nilFlagged
Check "control: TPlainThing.Create IS still flagged (line $plainLine)"                   $plainFlagged

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
