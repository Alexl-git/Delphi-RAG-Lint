<#
  Index-speed scenarios: the yardstick for the index-speed work.

  Runs one exe against one project closure (a test copy -- never a repo someone
  works in) and prints the wall time and the stage table of each run:

    full  -- index --rebuild into a fresh DB (also becomes the base of the others)
    none  -- incremental on a copy of the base, nothing changed
    one   -- copy of the base with one file forced stale (sha256='forced'):
             a real re-parse of one file, no source written
    ten   -- the same with ten files forced stale

  -OneFile / -TenFiles name the files (by file name); without them the first 1 / 10
  .pas files of the base index, in path order, are used -- the same set for every
  exe measured against the same base.

  The incremental scenarios need a base DB built by the SAME exe (a fingerprint
  mismatch turns them into a full re-parse): run 'full' first, or pass -BaseDb.

  Usage:
    pwsh -NoProfile -File tools\perf\scenarios.ps1 -Tag new -Project <x.dproj> -Exe <drag-lint.exe>
    pwsh -NoProfile -File tools\perf\scenarios.ps1 -Tag new -Project <x.dproj> -Scenarios none,one,ten -BaseDb <db>
#>
param(
  [Parameter(Mandatory)] [string]$Tag,
  [Parameter(Mandatory)] [string]$Project,
  [string]$Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$Out       = (Join-Path $env:TEMP 'drag-lint-perf'),
  [string]$BaseDb    = '',
  [string[]]$Scenarios = @('full', 'none', 'one', 'ten'),
  [string[]]$OneFile  = @(),
  [string[]]$TenFiles = @()
)
$ErrorActionPreference = 'Stop'
[cultureinfo]::CurrentCulture = [cultureinfo]::InvariantCulture
$env:DRAGLINT_PROFILE = '1'
New-Item -ItemType Directory -Force $Out | Out-Null
# pwsh -File hands 'none,one,ten' over as ONE string; split it here.
$Scenarios = @($Scenarios | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

function Remove-Db([string]$Db) {
  foreach ($s in '', '-wal', '-shm') { Remove-Item "$Db$s" -ErrorAction SilentlyContinue }
}

function Copy-Base([string]$To) {
  Remove-Db $To
  Copy-Item $script:BaseDb $To
  # Write to the fresh copy once before the clock starts. The FIRST checkpoint
  # into a freshly copied 500 MB file stalls ~20 s on this machine (measured
  # with Python: 2 pages, 19.4 s; the second checkpoint is instant) -- an
  # OS/antivirus effect of the copy, not of the indexer, and it landed on
  # whichever run wrote first: 'none' read 30-47 s against 9 s.
  $warm = @'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute('PRAGMA journal_mode=WAL')
c.execute("INSERT OR REPLACE INTO schema_meta(key, value) VALUES ('perf_warmup', '1')")
c.commit()
c.execute("DELETE FROM schema_meta WHERE key = 'perf_warmup'")
c.commit()
c.execute('PRAGMA wal_checkpoint(TRUNCATE)')
c.close()
'@
  $warm | py -I - $To
}

function Set-Stale([string]$Db, [string[]]$Names) {
  $py = @'
import sqlite3, sys
db, names = sys.argv[1], sys.argv[2:]
c = sqlite3.connect(db)
hit = 0
cols = [r[1] for r in c.execute('PRAGMA table_info(files)')]
for n in names:
    key = ('%' + chr(92) + n.lower(),)
    hit += c.execute("UPDATE files SET sha256='forced' WHERE lower(path) LIKE ?", key).rowcount
    # Since 2026-10-14 the walk takes a same-time, same-size file as current
    # without reading it; a NULL size sends it to the SHA test, which the
    # forced SHA then fails -- a real re-parse, as before.
    if 'size' in cols:
        c.execute("UPDATE files SET size = NULL WHERE lower(path) LIKE ?", key)
c.commit()
print(hit)
'@
  $hit = $py | py -I - $Db @Names
  if ([int]$hit -ne $Names.Count) { throw "forced $hit file(s), expected $($Names.Count) -- a name is missing from the closure" }
}

function Invoke-Index([string]$Name, [string]$Db, [string[]]$Extra) {
  $log = Join-Path $Out "$($Name)_$Tag"
  $sw  = [Diagnostics.Stopwatch]::StartNew()
  & $Exe index --project $Project --platform win32 --db $Db @Extra 2> "$log.stderr.txt" > "$log.stdout.txt"
  $code = $LASTEXITCODE
  $sw.Stop()
  $stages = [ordered]@{}
  foreach ($line in (Get-Content "$log.stdout.txt", "$log.stderr.txt")) {
    if ($line -match '^stage: (\S+) -- done in ([0-9.]+)s') { $stages[$Matches[1]] = [double]$Matches[2] }
  }
  $done = (Get-Content "$log.stdout.txt" | Where-Object { $_ -match '^Done\.' } | Select-Object -Last 1)
  [pscustomobject]@{
    scenario = $Name; exit = $code; wall_s = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    stages   = ($stages.GetEnumerator() | ForEach-Object { '{0}={1}' -f $_.Key, $_.Value }) -join ' '
    done     = $done
  }
}

$results = @()
if ($Scenarios -contains 'full') {
  $full = Join-Path $Out "full_$Tag.sqlite"
  Remove-Db $full
  $results += Invoke-Index 'full' $full @('--rebuild')
  if (-not $BaseDb) { $BaseDb = $full }
}
if (-not $BaseDb) { throw 'no base DB: run the full scenario or pass -BaseDb' }
$script:BaseDb = $BaseDb

# Files forced stale: the ones named, else the first 1 / 10 .pas files of the base
# index in path order -- a fixed set for every exe measured against this base.
if ($OneFile.Count -eq 0 -or $TenFiles.Count -eq 0) {
  $pyPick = "import sqlite3, sys, os`nc = sqlite3.connect(sys.argv[1])`n" +
           "rows = c.execute(""SELECT path FROM files WHERE lower(path) LIKE '%.pas' ORDER BY lower(path) LIMIT 10"").fetchall()`n" +
           "print(' '.join(os.path.basename(r[0]) for r in rows))"
  $picked = @(($pyPick | py -I - $script:BaseDb) -split ' ' | Where-Object { $_ })
  if ($OneFile.Count -eq 0)  { $OneFile  = @($picked | Select-Object -First 1) }
  if ($TenFiles.Count -eq 0) { $TenFiles = @($picked | Select-Object -First 10) }
}

foreach ($s in 'none', 'one', 'ten') {
  if ($Scenarios -notcontains $s) { continue }
  $db = Join-Path $Out "$($s)_$Tag.sqlite"
  Copy-Base $db
  switch ($s) {
    'one' { Set-Stale $db $OneFile }
    'ten' { Set-Stale $db $TenFiles }
  }
  $results += Invoke-Index $s $db @()
}

$results | Format-List
$results | ConvertTo-Json | Set-Content (Join-Path $Out "summary_$Tag.json")
