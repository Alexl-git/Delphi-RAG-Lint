<#
  run_doc_honours_exclude_paths.ps1 -- exclude_paths must stop the WRITER, not
  only the reporter.

  THE DEFECT THIS PINS:
    Ownership is TWO settings and only one reached the doc writer.
      * drag-lint-project.json  "ownRoots"    -- mine vs third-party, with
        --lint-third-party / --document-third-party as the escape hatch.
      * drag-lint-lint.json     "exclude_paths" -- never touch these at all.
    TOwnRoots was propagated to the documenter; IsPathExcluded was not, and it
    had exactly ONE call site in the whole engine -- inside lint-all's file loop,
    on the line directly above the Own.IsOurs check.

    That matters most for a repo whose ownRoots is the REPO ROOT on purpose,
    which is drag-lint's own case: its .dproj sits in src\cli, so defaulting to
    the project folder would classify the rest of the repo as third-party, and
    the vendored-code exclusion therefore lives ENTIRELY in exclude_paths. On
    2026-08-14 an autodoc pass over drag-lint's own source left 2,300 generated
    lines in third_party\delphi-tree-sitter -- vendored upstream tree-sitter
    bindings the repo explicitly declines to restyle, because renaming C binding
    names like ts_query_cursor_new would make every future upstream sync a
    conflict.

  Where the check now lives, and why it is asserted per entry point below:
    In TDocBatch.DocumentUnit -- the one place ALL THREE entry points funnel
    through. `document --project` and `document-all` arrive via
    AggregateOverFiles; `document --unit` calls straight in and touches neither
    AggregateOverFiles nor FilterToOwnRoots. Putting it beside ownRoots (the
    intuitive home) would have missed --unit and would have been defeated by
    --document-third-party. The predecessor note for this defect closed with
    "the ownership fix was applied per COMMAND" -- so all three commands are
    checked here, plus the escape hatch.

  Fixture: a project whose ownRoots is the PARENT of the project folder (the
  drag-lint shape), with a vendored subtree inside it that only exclude_paths
  keeps out. If exclude_paths were ignored, ownRoots would happily admit it.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-doc-exclude-paths"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Text) {
  $norm = ($Text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }

# repo\
#   drag-lint-lint.json          exclude_paths: *\third_party\*
#   app\  App.dpr, uApp.pas, _D-RAG\drag-lint-project.json (ownRoots: ..)
#   third_party\ uVendor.pas     <- in the closure, inside ownRoots, EXCLUDED
$repo   = Join-Path $WorkDir 'repo'
$app    = Join-Path $repo 'app'
$vendor = Join-Path $repo 'third_party'
$drag   = Join-Path $app '_D-RAG'
foreach ($d in @($repo, $app, $vendor, $drag)) { New-Item -ItemType Directory $d -Force | Out-Null }

Write-Ascii (Join-Path $vendor 'uVendor.pas') @'
unit uVendor;
interface
function ts_query_cursor_new(const AName: string): Integer;
implementation
function ts_query_cursor_new(const AName: string): Integer;
begin
  Result := Length(AName);
end;
end.
'@
Write-Ascii (Join-Path $app 'uApp.pas') @'
unit uApp;
interface
uses uVendor;
function AppDo(const AName: string): Integer;
implementation
function AppDo(const AName: string): Integer;
begin
  Result := ts_query_cursor_new(AName);
end;
end.
'@
Write-Ascii (Join-Path $app 'App.dpr') @'
program App;
uses
  uApp in 'uApp.pas',
  uVendor in '..\third_party\uVendor.pas';
begin
  Writeln(AppDo('x'));
end.
'@
# ownRoots = the REPO root, i.e. the parent of the project folder. This is the
# drag-lint shape, and it is what makes exclude_paths load-bearing: ownRoots
# ADMITS third_party\, so nothing but exclude_paths keeps the writer out.
Write-Ascii (Join-Path $drag 'drag-lint-project.json') '{ "ownRoots": [".."] }'
$cfg = Join-Path $repo 'drag-lint-lint.json'
Write-Ascii $cfg '{ "exclude_paths": ["*\\third_party\\*"] }'

$db   = Join-Path $drag 'app.sqlite'
$proj = Join-Path $app 'App.dpr'
$vfile = Join-Path $vendor 'uVendor.pas'
& $Exe index $repo --db $db 2>&1 | Out-Null

$vendorBefore = Get-Content $vfile -Raw

function Doc-Run([string[]]$ExtraArgs) {
  Push-Location $repo
  try { & $Exe @ExtraArgs --db $db --config $cfg --apply --no-backup 2>&1 | Out-String }
  finally { Pop-Location }
}

Write-Host 'PRECONDITION: the vendored unit is in the index and in the closure' -ForegroundColor Cyan
$files = & $Exe selftest files --db $db 2>&1 | Out-String
$inIndex = $files -match 'uVendor\.pas'
if (-not $inIndex) {
  # Fall back to a query -- the point is only that the vendored unit IS indexed,
  # since a test that excludes a file nobody would have touched proves nothing.
  $q = & $Exe query --name ts_query_cursor_new --db $db 2>&1 | Out-String
  $inIndex = $q -match 'ts_query_cursor_new'
}
Check 'uVendor is indexed (so excluding it is a real decision)' $inIndex
if (-not $inIndex) {
  Write-Host '  !! Every assertion below is VACUOUS: the writer could not have' -ForegroundColor Yellow
  Write-Host '  !! reached this file anyway. Fix the fixture, not the assertions.' -ForegroundColor Yellow
  $script:Failed = $true
}

Write-Host ''
Write-Host 'All three document entry points must refuse the excluded file' -ForegroundColor Cyan
$o1 = Doc-Run @('document', '--project', $proj)
Check 'document --project: vendored file byte-identical' `
  ((Get-Content $vfile -Raw) -ceq $vendorBefore)
Check 'document --project: says so, rather than dropping it silently' `
  ($o1 -match 'skipped by exclude_paths') (($o1 -split "`r?`n" | Where-Object { $_ -match 'exclude_paths' } | Select-Object -First 1))

$o2 = Doc-Run @('document', '--unit', $vfile)
Check 'document --unit: vendored file byte-identical (bypasses AggregateOverFiles)' `
  ((Get-Content $vfile -Raw) -ceq $vendorBefore)
Check 'document --unit: names the skipped file' `
  ($o2 -match 'skipped by exclude_paths') (($o2 -split "`r?`n" | Where-Object { $_ -match 'exclude_paths' } | Select-Object -First 1))

$o3 = Doc-Run @('document-all')
Check 'document-all: vendored file byte-identical' `
  ((Get-Content $vfile -Raw) -ceq $vendorBefore)

# The escape hatch opens ownRoots, NOT exclude_paths -- exactly as
# --lint-third-party does not defeat exclude_paths.
$o4 = Doc-Run @('document', '--project', $proj, '--document-third-party')
Check '--document-third-party still does NOT defeat exclude_paths' `
  ((Get-Content $vfile -Raw) -ceq $vendorBefore)

Write-Host ''
Write-Host 'CONTROL: the project own file IS still documented' -ForegroundColor Cyan
# Without this, every assertion above would also pass with the documenter
# broken, or with nothing indexed at all.
$appFile = Join-Path $app 'uApp.pas'
$appText = Get-Content $appFile -Raw
Check 'uApp.pas received engine output (the documenter is actually working)' `
  ($appText -match 'drag-lint:auto') ''
if ($appText -notmatch 'drag-lint:auto') {
  Write-Host '  !! The control failed, so the four "byte-identical" assertions' -ForegroundColor Yellow
  Write-Host '  !! above prove nothing -- they would pass with the writer dead.' -ForegroundColor Yellow
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
