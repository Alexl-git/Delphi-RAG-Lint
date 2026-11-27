<#
  run_v156_TSN.ps1 -- drag-lint 1.56 lane TS-N: EVERY kind of search covers three places (owner ruling).
  `place` on the rows of `query --name`, `query --text` and `find-unit`; the repository rows
  repo-field / repo-table / (--text) source repo; `--place <list>`; the note lines (design 1.2-1.6,
  src\query\DRagLint.Query.PlaceRows.pas). Fixture tests\fixtures\v156\CONCEPT\app (lane CON-I's),
  indexed with `index --project` into a scratch DB; the repository file is built with `repo restore`.

  N-A  query --name NAME: project row, then repo-field CUSTOMERS.NAME / SUPPLIERS.NAME, place on every row (JSON + text)
  N-B  every pre-1.56 text line still starts as before (anchored regex), the place token is appended
  N-C  --place project drops the repository rows; --place repository keeps only them; --place bogus = exit 2
  N-D  note lines on stderr: repository current, not configured, stale; library: not configured
  T-A  query --text: repository text rows (source repo, kind caption), place on project rows
  F-A  find-unit: place in the JSON edit and on the text line; --place repository resolves nothing

  Positive control of the whole script: -Exe <an engine without TS-N> (a 1.55 / pre-TS-N build): every
  check on a place, a repository row or a note FAILS.
  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = '', [string]$Work = '', [switch]$KeepScratch)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { Write-Host 'run_v156_TSN: needs pwsh 7' -ForegroundColor Red; exit 2 }
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
if ($Exe -eq '') { $Exe = Join-Path $repo 'src\cli\Win64\Debug\drag-lint.exe' }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "run_v156_TSN: no engine at $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
if ($Work -eq '') { $Work = $env:TEMP }
$work = Join-Path $Work ('dl-v156-tsn-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($work) | Out-Null

$script:fail = 0
$script:pass = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:pass++; Write-Host "  PASS  $Name" -ForegroundColor Green }
  else     { $script:fail++; Write-Host "  FAIL  $Name  $Detail" -ForegroundColor Red }
}
# One run: exit code, stdout lines, stderr text, parsed JSON ($null when not JSON).
function Run([string[]]$Argv) {
  $errFile = Join-Path $work 'stderr.txt'
  if (Test-Path -LiteralPath $errFile) { [IO.File]::Delete($errFile) }
  $out = & { $ErrorActionPreference = 'Continue'; & $Exe @Argv 2>$errFile }
  $rc = $LASTEXITCODE
  $json = $null
  if ($Argv -contains '--json') { try { $json = ($out -join "`n") | ConvertFrom-Json } catch { $json = $null } }
  $err = ''
  if (Test-Path -LiteralPath $errFile) { $err = '' + [IO.File]::ReadAllText($errFile) }
  return @{ rc = $rc; out = @($out | ForEach-Object { "$_" }); err = $err; json = $json }
}
function Copy-Tree([string]$From, [string]$To) {
  foreach ($d in @($From) + @(Get-ChildItem -LiteralPath $From -Recurse -Directory | ForEach-Object FullName)) {
    [IO.Directory]::CreateDirectory((Join-Path $To $d.Substring($From.Length).TrimStart('\'))) | Out-Null
  }
  foreach ($f in Get-ChildItem -LiteralPath $From -Recurse -File) { [IO.File]::Copy($f.FullName, (Join-Path $To $f.FullName.Substring($From.Length).TrimStart('\')), $true) }
}

Write-Host '== v156 TS-N: place on query --name / --text / find-unit ==' -ForegroundColor Cyan

$fix = Join-Path $repo 'tests\fixtures\v156\CONCEPT\app'
$app = Join-Path $work 'app'
$nor = Join-Path $work 'norepo'
Copy-Tree $fix $app
Copy-Tree $fix $nor
[IO.File]::WriteAllText((Join-Path $nor '_D-RAG\drag-lint-project.json'), "{ }`r`n", [Text.Encoding]::ASCII)
$dlrepo = Join-Path $app 'repo\App.dlrepo'
$dproj = Join-Path $app 'App.dproj'
$rr = Run @('repo', 'restore', '--in', (Join-Path $app 'repo\App.txt'), '--repo', $dlrepo)
Check 'setup: repo restore builds the repository file' (($rr.rc -eq 0) -and (Test-Path -LiteralPath $dlrepo)) "(rc $($rr.rc))"
$A = Join-Path $work 'app.sqlite'
$N = Join-Path $work 'norepo.sqlite'
$ix = Run @('index', '--project', $dproj, '--db', $A)
Check 'setup: index --project exits 0' ($ix.rc -eq 0) "(rc $($ix.rc))"
$nx = Run @('index', '--project', (Join-Path $nor 'App.dproj'), '--db', $N)
Check 'setup: the project with no repository indexes' ($nx.rc -eq 0) "(rc $($nx.rc))"

# ---- N-A query --name ---------------------------------------------------------------------
$r = Run @('query', '--name', 'NAME', '--db', $A, '--json')
$rows = @($r.json)
$repoRows = @($rows | Where-Object { $_.kind -eq 'repo-field' })
$q = @($repoRows | ForEach-Object { $_.qualified_name })
Check 'N-A1 query --name NAME: two repo-field rows CUSTOMERS.NAME, SUPPLIERS.NAME, place repository, id 0, file = the repository file' (($r.rc -eq 0) -and ($repoRows.Count -eq 2) -and ($q -contains 'CUSTOMERS.NAME') -and ($q -contains 'SUPPLIERS.NAME') -and (@($repoRows | Where-Object { ($_.place -eq 'repository') -and ($_.id -eq 0) -and ($_.file -eq $dlrepo) -and ($_.start_line -eq 0) }).Count -eq 2)) "(rc $($r.rc), repo rows $($repoRows.Count))"
$symRows = @($rows | Where-Object { $_.kind -ne 'repo-field' -and $_.kind -ne 'repo-table' })
Check 'N-A2 every symbol row has place project; at least one symbol row (the form member Name)' (($symRows.Count -ge 1) -and (@($symRows | Where-Object { $_.place -ne 'project' }).Count -eq 0)) "(symbol rows $($symRows.Count))"
$order = @($rows | ForEach-Object { $_.place })
$sortedOk = $true
for ($i = 1; $i -lt $order.Count; $i++) { $rank = @{ project = 0; repository = 1; library = 2 }; if ($rank[$order[$i]] -lt $rank[$order[$i - 1]]) { $sortedOk = $false } }
Check 'N-A3 order: project rows before repository rows' ($sortedOk -and ($order.Count -ge 3)) "($($order -join ','))"
$r = Run @('query', '--name', 'CUSTOMERS', '--db', $A, '--json')
$tab = @($r.json | Where-Object { $_.kind -eq 'repo-table' })
Check 'N-A4 query --name CUSTOMERS: one repo-table row, place repository' (($tab.Count -eq 1) -and ($tab[0].qualified_name -eq 'CUSTOMERS') -and ($tab[0].place -eq 'repository')) "(rows $(@($r.json).Count))"
$r = Run @('query', '--name', 'customers.name', '--db', $A, '--json')
Check 'N-A5 a dotted --name is TABLE.FIELD, case-insensitive: one repo-field row' ((@($r.json | Where-Object { $_.kind -eq 'repo-field' }).Count -eq 1) -and ($r.rc -eq 0)) "(rc $($r.rc))"

# ---- N-B text: every old line starts as before --------------------------------------------
$r = Run @('query', '--name', 'NAME', '--db', $A)
$lines = $r.out
$oldHead = ($lines.Count -ge 2) -and ($lines[0] -match '^kind\s+name\s+qualified_name$') -and ($lines[1] -match '^-{75}$')
$tail = $lines[-1]
$body = @($lines | Select-Object -Skip 2 | Select-Object -SkipLast 1)
$projLines = @($body | Where-Object { $_ -match ' place=project$' })
$repoLines = @($body | Where-Object { $_ -match '^repo-field\s+NAME\s+\w+\.NAME\b.* place=repository$' })
Check 'N-B1 text: the header and the rule line are as before' $oldHead "($($lines[0]))"
Check 'N-B2 text: every symbol line is `<kind> <name> <qname> ...` and ends in " place=project"; repository lines start with repo-field' (($projLines.Count -ge 1) -and ($repoLines.Count -eq 2) -and (($projLines.Count + $repoLines.Count) -eq $body.Count)) "($($projLines.Count) project, $($repoLines.Count) repo, $($body.Count) body)"
Check 'N-B3 text: the count line is as before and counts the repository rows' ($tail -match "^$($body.Count) match\(es\)$") "($tail)"
$old = @($projLines | ForEach-Object { $_ -replace ' place=project$', '' } | Where-Object { $_ -match '^\w+\s+\S+\s+\S+' })
Check 'N-B4 text: with the place token removed each project line is a pre-1.56 line (anchored regex)' ($old.Count -eq $projLines.Count)

# ---- N-C --place --------------------------------------------------------------------------
$r = Run @('query', '--name', 'NAME', '--db', $A, '--json', '--place', 'project')
Check 'N-C1 --place project: no repository row, the symbol rows stay' ((@($r.json | Where-Object { $_.place -ne 'project' }).Count -eq 0) -and (@($r.json).Count -ge 1) -and ($r.rc -eq 0)) "(rows $(@($r.json).Count))"
$r = Run @('query', '--name', 'NAME', '--db', $A, '--json', '--place', 'repository')
Check 'N-C2 --place repository: only repository rows, exit 0' ((@($r.json).Count -eq 2) -and (@($r.json | Where-Object { $_.place -ne 'repository' }).Count -eq 0) -and ($r.rc -eq 0)) "(rows $(@($r.json).Count))"
$r = Run @('query', '--name', 'NAME', '--db', $A, '--place', 'bogus')
Check 'N-C3 --place bogus: exit 2 and the usage line' (($r.rc -eq 2) -and ($r.err -match 'ERROR: --place accepts library, project, repository')) "(rc $($r.rc) err $($r.err))"
$r = Run @('query', '--name', 'NAME', '--db', $A, '--json', '--place', 'library')
Check 'N-C4 --place library with no library index: exit 1, no row' (($r.rc -eq 1) -and (@($r.json).Count -eq 0)) "(rc $($r.rc))"

# ---- N-D notes (stderr) -------------------------------------------------------------------
$r = Run @('query', '--name', 'NAME', '--db', $A, '--json')
Check 'N-D1 stderr: "repository: copy from <when> of <path>" when a repository row is printed' ($r.err -match '(?m)^repository: copy from \d{4}-\d\d-\d\d \d\d:\d\d of ') "($($r.err))"
Check 'N-D2 stderr: "library: not configured" (no library index resolved); stdout stays one JSON document' (($r.err -match '(?m)^library: not configured') -and ($null -ne $r.json))
$r = Run @('query', '--name', 'NAME', '--db', $A, '--json', '--place', 'project')
Check 'N-D3 --place project: no repository and no library note' (($r.err -notmatch 'repository:') -and ($r.err -notmatch 'library:'))
$r = Run @('query', '--name', 'NAME', '--db', $N, '--json')
Check 'N-D4 stderr: "repository: not configured" for the project with no repository; no repository row' (($r.err -match '(?m)^repository: not configured') -and (@($r.json | Where-Object { $_.place -eq 'repository' }).Count -eq 0))
$libDir = Join-Path $work 'lib'
[IO.Directory]::CreateDirectory($libDir) | Out-Null
$libDb = Join-Path $libDir 'library-Win64.sqlite'
[IO.File]::Copy($N, $libDb, $true)
$r = Run @('query', '--name', 'TfrmMain', '--db', $A, '--db', $libDb, '--json')
$lib = @($r.json | Where-Object { $_.place -eq 'library' })
Check 'N-D5 with a library index: its rows carry place library, after the project rows; no "library: not configured"' (($lib.Count -ge 1) -and ($r.err -notmatch 'library: not configured') -and ($r.json[-1].place -eq 'library')) "(rows $(@($r.json).Count), library $($lib.Count))"
$r = Run @('query', '--name', 'TfrmMain', '--db', $A, '--db', $libDb, '--json', '--place', 'project')
Check 'N-D6 --place project with a library index: no library row' ((@($r.json | Where-Object { $_.place -ne 'project' }).Count -eq 0) -and (@($r.json).Count -ge 1))
$repoFile = $dlrepo
$old = (Get-Item -LiteralPath $repoFile).LastWriteTimeUtc
(Get-Item -LiteralPath $repoFile).LastWriteTimeUtc = $old.AddMinutes(5)
$r = Run @('query', '--name', 'NAME', '--db', $A, '--json')
Check 'N-D7 stderr: a repository file touched after the copy = the stale note with the refresh command' ($r.err -match '(?m)^repository: copy from .* is stale \(.* changed since\); refresh: drag-lint index --project ') "($($r.err))"
(Get-Item -LiteralPath $repoFile).LastWriteTimeUtc = $old

# ---- T-A query --text ---------------------------------------------------------------------
$r = Run @('query', '--text', 'Customer name', '--db', $A, '--json')
$tr = @($r.json | Where-Object { $_.source -eq 'repo' })
Check 'T-A1 query --text "Customer name": a repository row (source repo, kind caption, place repository, file = repository file, line 0, enclosing CUSTOMERS.NAME)' (($r.rc -eq 0) -and ($tr.Count -ge 1) -and (@($tr | Where-Object { ($_.place -eq 'repository') -and ($_.file_path -eq $dlrepo) -and ($_.start_line -eq 0) -and ($_.enclosing -eq 'CUSTOMERS.NAME') -and ($_.kind -eq 'caption') }).Count -ge 1)) "(rc $($r.rc), repo rows $($tr.Count))"
$r = Run @('query', '--text', 'NAME', '--db', $A, '--json', '--source', 'pas')
Check 'T-A2 a .pas literal row has place project; --source pas has no repository row' ((@($r.json).Count -ge 1) -and (@($r.json | Where-Object { $_.place -ne 'project' }).Count -eq 0) -and ($r.rc -eq 0)) "(rows $(@($r.json).Count))"
$r = Run @('query', '--text', 'Customer name', '--db', $A, '--json', '--place', 'project')
Check 'T-A3 --place project drops the repository text rows' (@($r.json | Where-Object { $_.source -eq 'repo' }).Count -eq 0)
$r = Run @('query', '--text', 'Customer name', '--db', $A, '--place', 'bogus')
Check 'T-A4 --place bogus: exit 2' ($r.rc -eq 2)
$r = Run @('query', '--text', 'Customer name', '--db', $A)
$tl = @($r.out | Where-Object { $_ -match '\[repo/caption\]' })
Check 'T-A5 text line: <file>:0:0  [repo/caption]  <text> -> CUSTOMERS.NAME place=repository' (($tl.Count -ge 1) -and ($tl[0] -match '^.+:0:0  \[repo/caption\]  .* -> CUSTOMERS\.NAME place=repository$')) "($($tl -join ' | '))"
Check 'T-A6 the count line is as before' ($r.out[-1] -match '^\d+ match\(es\)$')

# ---- F-A find-unit ------------------------------------------------------------------------
$join = Join-Path $app 'uJoin.pas'
$r = Run @('find-unit', '--name', 'CopyName', '--in', $join, '--db', $A, '--json')
Check 'F-A1 find-unit --json: the edit carries place project' (($r.rc -eq 0) -and (@($r.json).Count -ge 1) -and ($r.json[0].place -eq 'project') -and ($r.json[0].unit -eq 'uTools')) "(rc $($r.rc))"
$r = Run @('find-unit', '--name', 'CopyName', '--in', $join, '--db', $A)
Check 'F-A2 find-unit text: the Dry run line is as before plus " place=project"' (@($r.out | Where-Object { $_ -match '^Dry run: add unit "uTools"\. Pass --apply to write\. place=project$' }).Count -eq 1) "($($r.out -join ' | '))"
Check 'F-A3 find-unit prints no repository note (a repository declares no unit)' ($r.err -notmatch 'repository:')
$r = Run @('find-unit', '--name', 'CopyName', '--in', $join, '--db', $A, '--place', 'repository')
Check 'F-A4 --place repository: nothing declares the unit there, exit 1' ($r.rc -eq 1) "(rc $($r.rc))"
$r = Run @('find-unit', '--name', 'CopyName', '--in', $join, '--db', $A, '--place', 'bogus')
Check 'F-A5 --place bogus: exit 2' ($r.rc -eq 2)

Write-Host ''
Write-Host "run_v156_TSN: $($script:pass) passed, $($script:fail) failed" -ForegroundColor $(if ($script:fail -eq 0) { 'Green' } else { 'Red' })
if (-not $KeepScratch) { try { [IO.Directory]::Delete($work, $true) } catch { } }
exit $(if ($script:fail -eq 0) { 0 } else { 1 })
