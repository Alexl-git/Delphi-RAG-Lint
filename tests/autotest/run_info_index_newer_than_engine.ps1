<#
  run_info_index_newer_than_engine.ps1 -- `info --db` never tells the user to
  re-resolve or re-parse an index that is NEWER than the running engine.

  THE DEFECT (C2, 2026-09-23). `info --db` computed its verdict by INEQUALITY:
  `resolver_fingerprint <> this engine's` -> resolve-owed, extractor limb
  <> this engine's -> reparse-owed. So an index resolved at 1.7.0-alpha,
  inspected by an engine at 1.6.0-alpha, was reported resolve-owed with the
  remedy `index ... --resolve-only` -- the exact downgrade ENG-2 made `index`
  REFUSE (RefuseIfEngineOlderThanDb). The advice named a command that fails.

  THE CONTRACT PINNED HERE
    * a resolver stamp NEWER than the engine -> verdict `index-newer`,
      resolver_newer=true, resolver_stale=false, and a remedy that says to use
      a newer engine (and does not advise --resolve-only);
    * the same on the extractor axis -> `index-newer`, indexer_newer=true,
      indexer_stale=false, no re-parse advice;
    * POSITIVE CONTROLS: an OLDER stamp on each axis is still resolve-owed /
      reparse-owed, and an untouched index is current. Without them a verdict
      that became `index-newer` for every mismatch would pass.

  Versions are compared with CompareDottedVersions, the comparison the refusal
  itself uses, so `99.0.0` is newer and `0.0.1` older whatever this engine is.

  Needs python (sqlite3): planting a fingerprint is a write the engine offers
  no verb for -- the same dependency run_about_freshness_states.ps1 has.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_info_index_newer"
)
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $tag = if ($Ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("[{0}] {1}{2}" -f $tag, $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
  if (-not $Ok) { $script:fail = $true }
}
function W($p, $s) {
  [IO.File]::WriteAllText($p, (($s -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe"; exit 2 }
$exePath = (Resolve-Path $Exe).Path
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
  Write-Host 'SKIP: python not on PATH -- planting a fingerprint needs sqlite3'
  exit 0
}
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Force -Path (Join-Path $WorkDir '_D-RAG') | Out-Null
W (Join-Path $WorkDir 'uA.pas') @"
unit uA;
interface
procedure Go;
implementation
procedure Go;
begin
end;
end.
"@
W (Join-Path $WorkDir 'App.dpr') @"
program App;
uses
  uA in 'uA.pas';
begin
end.
"@
$db = Join-Path $WorkDir '_D-RAG\App.sqlite'
$py = Join-Path $WorkDir 'exec.py'
[IO.File]::WriteAllText($py,
  "import sqlite3,sys`nc=sqlite3.connect(sys.argv[1])`nc.execute(sys.argv[2])`nc.commit();c.close()`n",
  [Text.Encoding]::ASCII)

function Reindex { & $exePath index --project (Join-Path $WorkDir 'App.dpr') --db $db 2>&1 | Out-Null }
function IndexRow {
  $j = (& $exePath info --json --db $db 2>$null) -join "`n"
  $i = $j.IndexOf('{')
  if ($i -lt 0) { return $null }
  try { return ($j.Substring($i) | ConvertFrom-Json).indexes[0] } catch { return $null }
}
function Plant([string]$Key, [string]$Value) {
  & python $py $db "UPDATE schema_meta SET value='$Value' WHERE key='$Key'" | Out-Null
  $v = (& $exePath sql --query "SELECT value FROM schema_meta WHERE key='$Key'" --db $db --json 2>$null) -join "`n"
  if ($v -notmatch [regex]::Escape($Value)) { throw "FIXTURE: planting $Key=$Value did not take" }
}

Push-Location $WorkDir
try {
  Reindex
  $ok = IndexRow
  Check 'CONTROL: an untouched index is current' (($null -ne $ok) -and ($ok.verdict -eq 'current')) "got '$($ok.verdict)'"
  $rfp = [string]$ok.resolver_fingerprint
  $ifp = [string]$ok.indexer_fingerprint
  if (($rfp -notmatch '^r=[^;]+;') -or ($ifp -notmatch '^v=[^;]+;')) { throw "FIXTURE: unexpected stamps rfp='$rfp' ifp='$ifp'" }

  # --- resolver axis: NEWER ---------------------------------------------------
  Plant 'resolver_fingerprint' ($rfp -replace '^r=[^;]+;', 'r=99.0.0-alpha;')
  $r = IndexRow
  Check 'resolver NEWER than the engine -> verdict index-newer (not resolve-owed)' `
    (($null -ne $r) -and ($r.verdict -eq 'index-newer')) "got '$($r.verdict)' remedy='$($r.remedy)'"
  Check 'resolver NEWER: resolver_newer=true, resolver_stale=false' `
    (($null -ne $r) -and ($r.resolver_newer -eq $true) -and ($r.resolver_stale -eq $false)) `
    "resolver_newer=$($r.resolver_newer) resolver_stale=$($r.resolver_stale)"
  Check 'resolver NEWER: the remedy says to use a newer engine and never advises --resolve-only' `
    (($null -ne $r) -and ($r.remedy -match '(?i)newer engine') -and ($r.remedy -notmatch 'resolve-only')) "remedy='$($r.remedy)'"

  # --- resolver axis: OLDER (positive control) --------------------------------
  Plant 'resolver_fingerprint' ($rfp -replace '^r=[^;]+;', 'r=0.0.1-alpha;')
  $r = IndexRow
  Check 'CONTROL: resolver OLDER than the engine is still resolve-owed' `
    (($null -ne $r) -and ($r.verdict -eq 'resolve-owed') -and ($r.resolver_stale -eq $true) -and ($r.remedy -match 'resolve-only')) `
    "got '$($r.verdict)' remedy='$($r.remedy)'"

  # --- extractor axis: NEWER --------------------------------------------------
  Reindex
  Plant 'indexer_fingerprint' ($ifp -replace '^v=[^;]+;', 'v=99.0.0-alpha;')
  $x = IndexRow
  Check 'extractor NEWER than the engine -> verdict index-newer (not reparse-owed)' `
    (($null -ne $x) -and ($x.verdict -eq 'index-newer')) "got '$($x.verdict)' remedy='$($x.remedy)'"
  Check 'extractor NEWER: indexer_newer=true, indexer_stale=false' `
    (($null -ne $x) -and ($x.indexer_newer -eq $true) -and ($x.indexer_stale -eq $false)) `
    "indexer_newer=$($x.indexer_newer) indexer_stale=$($x.indexer_stale)"
  Check 'extractor NEWER: the remedy says to use a newer engine and does not advise a re-parse' `
    (($null -ne $x) -and ($x.remedy -match '(?i)newer engine') -and ($x.remedy -notmatch 're-parse: hours')) "remedy='$($x.remedy)'"

  # --- extractor axis: OLDER (positive control) -------------------------------
  Plant 'indexer_fingerprint' ($ifp -replace '^v=[^;]+;', 'v=0.0.1-alpha;')
  $x = IndexRow
  Check 'CONTROL: extractor OLDER than the engine is still reparse-owed' `
    (($null -ne $x) -and ($x.verdict -eq 'reparse-owed') -and ($x.indexer_stale -eq $true)) "got '$($x.verdict)'"
}
finally {
  Pop-Location
}

if ($script:fail) { Write-Host 'FAIL  run_info_index_newer_than_engine'; exit 1 }
Write-Host 'PASS  run_info_index_newer_than_engine'
exit 0