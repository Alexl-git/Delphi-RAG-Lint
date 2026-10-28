<#
  run_library_resolve_marker.ps1 -- library-first resolve, lane lf-marker (plan 2026-10-28, s.2.3-2.5).

  A section that opts in with "libraryResolve": true while the platform library is NOT ready is
  resolved without it: the project DB is MARKED (schema_meta.library_resolve_state, JSON,
  state=pending), the user is told the result is incomplete, and the next WRITER run re-resolves
  once the library is ready (state=bound, external_stores set, refs.external_target filled).

  Asserted (hermetic engine copy with its own drag-lint.json; fixture tests\callresolve\fixtures\xtyped):
    a. library missing -> `index --project` prints "library: PENDING", marker state=pending, external_target = 0
    b. still missing, nothing changed -> pending kept, last_check_unix not older, since_unix unchanged
    c. READERS (info --json, sql --json, find-callers) print / carry the notice and do NOT write the DB
       (size + mtime unchanged); info verdict = library-resolve-owed
    d. library made ready, plain `index --project` (no file changed) -> the pass RUNS, "library: bound",
       marker state=bound, external_stores present, external_target > 0       (positive control)
    e. bound -> readers are quiet (no notice, no index_notes, verdict current)
    f. a second plain run is a no-op for the pass ("stage: calls -- skipped") and keeps since_unix
    g. a section WITHOUT the key never gets a marker (control for the opt-in)
  Run from a NEUTRAL CWD (C:\TEMP). Touches no shared index.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
function Write-Ascii([string]$Path,[string]$Body){ [IO.File]::WriteAllText($Path, ($Body -replace "`r?`n","`r`n"), [Text.Encoding]::ASCII) }
$exeSrc = (Resolve-Path $Exe).Path; $exeSrcDir = Split-Path -Parent $exeSrc
$fixDir = (Resolve-Path (Join-Path $PSScriptRoot '..\callresolve\fixtures\xtyped')).Path
$root = Join-Path C:\TEMP "draglint_libmarker_$PID"
try {
  if (Test-Path $root) { [IO.Directory]::Delete($root, $true) }
  $eng = Join-Path $root 'eng'; $out = Join-Path $root 'out'; $lib = Join-Path $root 'lib'; $app = Join-Path $root 'app'
  New-Item -ItemType Directory -Path $eng,$out,$lib,$app | Out-Null
  Copy-Item $exeSrc (Join-Path $eng 'drag-lint.exe') -Force
  Get-ChildItem $exeSrcDir -Filter '*.dll' | ForEach-Object { Copy-Item $_.FullName (Join-Path $eng $_.Name) -Force }
  if (Test-Path (Join-Path $exeSrcDir 'rules')) { Copy-Item (Join-Path $exeSrcDir 'rules') (Join-Path $eng 'rules') -Recurse -Force }
  $exe = Join-Path $eng 'drag-lint.exe'
  Copy-Item (Join-Path $fixDir 'xt_lib.pas') $lib -Force
  Copy-Item (Join-Path $fixDir 'xt_app.pas'),(Join-Path $fixDir 'xt_app2.pas') $app -Force
  Write-Ascii (Join-Path $app 'App.dpr') "program App;`n`nuses`n  xt_app in 'xt_app.pas',`n  xt_app2 in 'xt_app2.pas';`n`nbegin`nend.`n"
  Write-Ascii (Join-Path $app 'Plain.dpr') "program Plain;`n`nuses`n  xt_app in 'xt_app.pas',`n  xt_app2 in 'xt_app2.pas';`n`nbegin`nend.`n"

  $o = $out.Replace('\','/')
  $manifest = @"
{
  "settings": { "defaultPlatform": "Win64", "maxJobs": 1 },
  "indexes": { "outDir": "$o", "sections": [
    { "name": "Library", "db": "library-{platform}.sqlite", "source": "registry-libraries", "platforms": ["Win64"] },
    { "name": "ProjOn", "db": "projon.sqlite", "include": ["$($app.Replace('\','/'))/App.dpr"], "libraryResolve": true },
    { "name": "ProjOff", "db": "projoff.sqlite", "include": ["$($app.Replace('\','/'))/Plain.dpr"] }
  ] }
}
"@
  Write-Ascii (Join-Path $eng 'drag-lint.json') $manifest

  function Q([string]$Db,[string]$Query) {
    $raw = (& $exe sql --db $Db --json --limit 5000 --query $Query 2>$null) -join "`n"
    $b = $raw.IndexOf('{'); if ($b -lt 0) { return ,@() }
    return ,@(($raw.Substring($b) | ConvertFrom-Json).rows)
  }
  function Meta([string]$Db,[string]$Key) {
    $r = Q $Db "select value from schema_meta where key = '$Key'"
    if ($r.Count -eq 0) { return '' } else { return [string]$r[0][0] }
  }
  function Stamp([string]$Path) { $i = Get-Item -LiteralPath $Path; return "$($i.Length)|$($i.LastWriteTimeUtc.Ticks)" }
  $extCount = 'select count(*) from refs where external_target is not null and external_target <> ''''  '
  $projOn = Join-Path $out 'projon.sqlite'; $libDb = Join-Path $out 'library-Win64.sqlite'
  Push-Location C:\TEMP
  try {
    # a. library missing -> pending
    $txt = (& $exe index --project (Join-Path $app 'App.dpr') 2>&1 | Out-String)
    Check 'a: project DB built' (Test-Path $projOn) $txt
    Check 'a: the user is told the result is incomplete (library: PENDING)' ($txt -match 'library: PENDING') $txt
    $m1 = Meta $projOn 'library_resolve_state'
    $j1 = if ($m1) { $m1 | ConvertFrom-Json } else { $null }
    Check 'a: marker state=pending' ($j1 -and $j1.state -eq 'pending') $m1
    Check 'a: marker names a reason' ($j1 -and $j1.reason -match 'missing') $m1
    Check 'a: external_target = 0 (edges are project-local)' ((Q $projOn $extCount)[0][0] -eq 0)
    Check 'g: no key -> no marker (ProjOff control)' ($(& $exe index --project (Join-Path $app 'Plain.dpr') 2>&1 | Out-Null; (Meta (Join-Path $out 'projoff.sqlite') 'library_resolve_state') -eq ''))
    Start-Sleep -Seconds 2

    # b. still missing, nothing changed -> pending kept, last_check moves, since stays
    $txt = (& $exe index --project (Join-Path $app 'App.dpr') 2>&1 | Out-String)
    $j2 = (Meta $projOn 'library_resolve_state') | ConvertFrom-Json
    Check 'b: still pending after a no-change run' ($j2.state -eq 'pending')
    Check 'b: since_unix unchanged' ($j2.since_unix -eq $j1.since_unix) "$($j1.since_unix) vs $($j2.since_unix)"
    Check 'b: last_check_unix moved' ($j2.last_check_unix -gt $j1.last_check_unix) "$($j1.last_check_unix) -> $($j2.last_check_unix)"
    Check 'b: notice printed again' ($txt -match 'library: PENDING') $txt

    # c. readers: notice, JSON field, and NO write
    $before = Stamp $projOn
    $info = (& $exe info --json --db $projOn 2>&1) -join "`n"
    $ij = ($info.Substring($info.IndexOf('{')) | ConvertFrom-Json).indexes[0]
    Check 'c: info verdict = library-resolve-owed' ($ij.verdict -eq 'library-resolve-owed') $ij.verdict
    Check 'c: info remedy names --resolve-only' ($ij.remedy -match '--resolve-only') $ij.remedy
    Check 'c: info carries library_resolve.state = pending' ($ij.library_resolve.state -eq 'pending')
    $fc = (& $exe query find-callers --name Go --db $projOn 2>&1 | Out-String)
    Check 'c: find-callers prints the library-pending NOTE (INCOMPLETE)' (($fc -match 'library-bound edges pending') -and ($fc -match 'INCOMPLETE')) $fc
    $sq = (& $exe sql --db $projOn --json --query 'select 1' 2>$null) -join "`n"
    $sj = $sq.Substring($sq.IndexOf('{')) | ConvertFrom-Json
    Check 'c: sql --json carries index_notes[0].kind = library-pending' (@($sj.index_notes).Count -ge 1 -and $sj.index_notes[0].kind -eq 'library-pending') $sq
    Check 'c: readers wrote nothing (size + mtime unchanged)' ((Stamp $projOn) -eq $before)

    # d. library becomes ready; a plain writer run re-resolves with no file changed
    & $exe index $lib --db $libDb 2>&1 | Out-Null
    Check 'd: library index built' (Test-Path $libDb)
    $txt = (& $exe index --project (Join-Path $app 'App.dpr') 2>&1 | Out-String)
    Check 'd: the calls pass RAN although no file changed' ($txt -notmatch 'stage: calls -- skipped') $txt
    Check 'd: "library: bound" reported' ($txt -match 'library: bound') $txt
    $j3 = (Meta $projOn 'library_resolve_state') | ConvertFrom-Json
    Check 'd: marker state=bound' ($j3.state -eq 'bound')
    Check 'd: external_stores recorded' ((Meta $projOn 'external_stores') -match 'library-Win64')
    Check 'd: POSITIVE CONTROL external_target > 0' ((Q $projOn $extCount)[0][0] -gt 0)

    # e. bound -> readers quiet
    $info = (& $exe info --json --db $projOn 2>&1) -join "`n"
    $ij = ($info.Substring($info.IndexOf('{')) | ConvertFrom-Json).indexes[0]
    Check 'e: info verdict = current' ($ij.verdict -eq 'current') $ij.verdict
    $fc = (& $exe query find-callers --name Go --db $projOn 2>&1 | Out-String)
    Check 'e: find-callers prints no pending NOTE' ($fc -notmatch 'library-bound edges pending') $fc
    $sq = (& $exe sql --db $projOn --json --query 'select 1' 2>$null) -join "`n"
    $sj = $sq.Substring($sq.IndexOf('{')) | ConvertFrom-Json
    Check 'e: sql --json has no index_notes' ($null -eq $sj.PSObject.Properties['index_notes'])

    # f. a second plain run is a no-op for the pass and keeps since_unix
    $txt = (& $exe index --project (Join-Path $app 'App.dpr') 2>&1 | Out-String)
    Check 'f: second run skips the calls pass' ($txt -match 'stage: calls -- skipped') $txt
    $j4 = (Meta $projOn 'library_resolve_state') | ConvertFrom-Json
    Check 'f: marker still bound, since_unix kept' (($j4.state -eq 'bound') -and ($j4.since_unix -eq $j3.since_unix))
  } finally { Pop-Location }
} finally {
  if (Test-Path -LiteralPath $root) { [IO.Directory]::Delete($root, $true) }
}
if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
