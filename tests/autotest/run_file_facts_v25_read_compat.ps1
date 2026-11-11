<#
  run_file_facts_v25_read_compat.ps1 -- wave 151 lane ST: an engine that writes
  dfm_properties + comment_facts (schema 25 after INT's bump) READS a schema 24
  and a schema 23 index -- built by an engine without those tables -- with the
  tables ABSENT (readers take the text path), and never an AV.

  Spec: docs\superpowers\specs\2026-11-11-dfm-props-and-comment-facts.md ("Reader
  rule"); read-compat contract: docs\superpowers\specs\2026-11-09-schema-read-compat.md.

  Fixture: tests\fixtures\file-facts-149\facts (Pascal units + text .dfm) copied to
  a temp dir and indexed by -Exe. Copies of that index are made the way an older
  engine would have left them (python stdlib sqlite3, a script FILE run with -I):
    v24 copy: dfm_properties + comment_facts dropped, schema_version stamped
              min(engine, 24).
    v23 copy: also file_includes, dfm_objects, pp_regions, pp_directives,
              dfm_nav_nodes, dfm_nav_props, project_settings dropped; stamped
              min(engine, 23).
  Checks per copy (read-only verbs must NOT migrate the copy):
    Q   query --name TFfForm answers, no 'index schema v' refusal, no AV
    S   schema --db: schema_readable true, the dropped tables are NOT listed
        (proves the read did not run Migrate -- the absent state is what was read)
    F   forms-csv over the fixture with --db <copy>: exit <> 2, no AV (FormsMap
        probes HasDfmNav and falls back to the .dfm text)
    L   lint-tree --unit FfIncA.pas --db <copy>: exit <> 2, no AV
  Arm W (writer upgrade): `index` into the v24 copy ends exit 0 with both tables
  PRESENT (Migrate / rebuild created them) -- the writer half of the contract.
  Arm FRESH: on the -Exe's own index both tables are listed by `schema`.
  POSITIVE CONTROL: -Exe <the 1.49.0-alpha base engine> FAILS FRESH and W (it
  never creates the tables). The lane ran it with SCHEMA_VERSION temporarily 25 in
  the wt (REPORT.md); at 24 the stamps are 24 / 23 and the checks are the same.
  Needs python; missing python = FATAL, never a skip. Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = '')

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { Write-Host 'run_file_facts_v25_read_compat: needs pwsh 7' -ForegroundColor Red; exit 2 }
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
if ($Exe -eq '') { $Exe = Join-Path $repo 'src\cli\Win64\Debug\drag-lint.exe' }
if (-not (Test-Path $Exe)) { Write-Host "run_file_facts_v25_read_compat: no engine at $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$py = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $py) { Write-Host 'FATAL: python not found (needed to make the old-schema copies)'; exit 2 }

$work = Join-Path $env:TEMP ('dl-ff-v25-rc-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $work | Out-Null
$fx = Join-Path $work 'facts'
Copy-Item -Recurse (Join-Path $repo 'tests\fixtures\file-facts-149\facts') $fx

$script:fail = 0
$script:pass = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:pass++; Write-Host "  PASS  $Name  $Detail" -ForegroundColor Green }
  else     { $script:fail++; Write-Host "  FAIL  $Name  $Detail" -ForegroundColor Red }
}
function Run-Exe([string[]]$CliArgs) {
  $o = & $Exe @CliArgs 2>&1 | Out-String
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}
function No-Av([string]$Text) { return -not ($Text -match 'AccessViolation|Access violation') }
function Schema-Of([string]$Db) {
  $o = (Run-Exe @('schema', '--db', $Db, '--format', 'json')).Out
  $i = $o.IndexOf('{')
  if ($i -lt 0) { return $null }
  try { return ($o.Substring($i) | ConvertFrom-Json) } catch { return $null }
}
function Table-Names($Schema) {
  if ($null -eq $Schema -or $null -eq $Schema.tables) { return @() }
  return @($Schema.tables | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } })
}

try {
  Write-Host "run_file_facts_v25_read_compat: engine $Exe" -ForegroundColor Cyan
  $fresh = Join-Path $work 'fresh.sqlite'
  $r = Run-Exe @('index', $fx, '--db', $fresh)
  Check 'VACUITY the fixture was indexed' ($r.Code -eq 0) "(exit $($r.Code))"
  $sch = Schema-Of $fresh
  $engine = if ($null -ne $sch.engine_schema_version) { [int]$sch.engine_schema_version } else { [int]$sch.schema_version }
  $names = Table-Names $sch
  Check 'VACUITY schema --format json lists tables' ($names.Count -gt 10) "($($names.Count) tables)"
  Check 'FRESH the engine creates dfm_properties and comment_facts' (($names -contains 'dfm_properties') -and ($names -contains 'comment_facts')) ''
  Write-Host "  engine schema v$engine"

  $stamp = Join-Path $work 'stamp.py'
  [IO.File]::WriteAllText($stamp, @'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("UPDATE schema_meta SET value = ? WHERE key = 'schema_version'", (sys.argv[2],))
for t in sys.argv[3].split(","):
    c.execute("DROP TABLE IF EXISTS " + t)
c.commit()
c.close()
'@)
  $drop24 = 'dfm_properties,comment_facts'
  $drop23 = $drop24 + ',file_includes,dfm_objects,pp_regions,pp_directives,dfm_nav_nodes,dfm_nav_props,project_settings'
  $copies = @(
    [pscustomobject]@{ Tag = 'v24'; Ver = [Math]::Min($engine, 24); Drop = $drop24 },
    [pscustomobject]@{ Tag = 'v23'; Ver = [Math]::Min($engine, 23); Drop = $drop23 })
  foreach ($c in $copies) {
    $db = Join-Path $work "$($c.Tag).sqlite"
    [IO.File]::Copy($fresh, $db, $true)
    & $py -I $stamp $db "$($c.Ver)" $c.Drop
    if ($LASTEXITCODE -ne 0) { throw "stamp $db failed" }
    $c | Add-Member -NotePropertyName Db -NotePropertyValue $db
    Write-Host "  -- $($c.Tag): stamped v$($c.Ver), dropped $($c.Drop)" -ForegroundColor Cyan

    $q = Run-Exe @('query', '--name', 'TFfForm', '--db', $db)
    Check "$($c.Tag) Q query answers" (($q.Code -eq 0) -and ($q.Out -match 'TFfForm') -and -not ($q.Out -match 'index schema v\d+ <') -and (No-Av $q.Out)) "(exit $($q.Code))"

    $s = Schema-Of $db
    $sn = Table-Names $s
    $gone = @($c.Drop.Split(',') | Where-Object { $sn -contains $_ })
    Check "$($c.Tag) S schema reads it and the dropped tables stay absent" (($null -ne $s) -and ($s.schema_readable -ne $false) -and ($gone.Count -eq 0) -and ($sn.Count -gt 10)) "(still listed: $($gone -join ','))"

    $f = Run-Exe @('forms-csv', $fx, '--db', $db)
    Check "$($c.Tag) F forms-csv falls back to the text, no AV" (($f.Code -ne 2) -and (No-Av $f.Out)) "(exit $($f.Code))"

    $l = Run-Exe @('lint-tree', '--unit', (Join-Path $fx 'FfIncA.pas'), '--db', $db)
    Check "$($c.Tag) L lint-tree reads it, no AV" (($l.Code -ne 2) -and -not ($l.Out -match 'older than this engine reads') -and (No-Av $l.Out)) "(exit $($l.Code))"
  }

  # ---- arm W: a writer upgrades the v24 copy -----------------------------------
  $w = $copies[0].Db
  $r = Run-Exe @('index', $fx, '--db', $w)
  $wn = Table-Names (Schema-Of $w)
  Check 'W index into the v24 copy: exit 0, both tables created' (($r.Code -eq 0) -and ($wn -contains 'dfm_properties') -and ($wn -contains 'comment_facts') -and (No-Av $r.Out)) "(exit $($r.Code))"
}
finally {
  try { [IO.Directory]::Delete($work, $true) } catch { Write-Host "  (scratch $work left: $($_.Exception.Message))" }
}
Write-Host ("run_file_facts_v25_read_compat: {0} passed, {1} failed" -f $script:pass, $script:fail) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
exit $(if ($script:fail) { 1 } else { 0 })
