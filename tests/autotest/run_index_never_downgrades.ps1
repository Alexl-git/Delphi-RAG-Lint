<#
  run_index_never_downgrades.ps1 -- an engine OLDER than the extractor version
  stamped in a database REFUSES to write it (PLAN-multi-client-index-safety,
  ruling 1, T2/T3).

  THE HAZARD THIS PINS. The indexer fingerprint (`v=<extractor>;schema=..`) is
  compared for INEQUALITY only: any difference forces a full re-parse and the
  run stamps ITS OWN version afterwards. So an older engine -- the VS Code
  extension's private copy sat at extractor 1.15.0 while the canonical engine
  had written 1.16.0 in a 7-hour re-parse; a stale CLI on someone's PATH is the
  same shape -- would re-parse every file with the older extractor and stamp
  the database DOWN. Silently, exit 0, and the evidence gone.

  WHAT IT ASSERTS, per row (the fixture is RECREATED before every row -- the
  refusal leaves the file alone, the positive control rewrites it, and a row
  reading the previous row's file measures nothing):

    R0  equal stamp        -> exit 0, no re-parse, stamp unchanged
    R1  stamp NEWER (9.x)  -> exit 2, BOTH versions named, file byte-identical,
                              stamp still the newer one (refused, not "nothing
                              happened"); same with --rebuild and --force-reparse
    R2  LEXICAL TRAP       -> a stamp that sorts BELOW the engine as a string
                              but ABOVE it numerically ('1.100.0' vs '1.16.0')
                              must still refuse. This is the exact pair a string
                              comparison lets through.
    R3  POSITIVE CONTROL   -> stamp OLDER -> exit 0, re-parse announced, stamp
                              becomes the engine's. Without this a build that
                              refuses everything passes R1/R2.
    R4  schema NEWER       -> exit 2, file byte-identical (Migrate would stamp
                              schema_version DOWN to the engine's)
    R5  index --all        -> the manifest path (BuildPlanItem) refuses too;
                              it is the path every real project DB is built by

  The stamp is planted with python's sqlite3 and CHECKPOINTED, so the planted
  value sits in the main file and the md5 before the engine runs is of a file
  that holds it. Without the checkpoint the engine's own connection close would
  fold the -wal in and the md5 would change with NO engine write at all.

  RED FIRST against 1.12.0-alpha: R1/R2/R4/R5 exit 0, announce "Indexer changed
  since this DB was built" and stamp the engine's version over the newer one.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-never-downgrade"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
  if (-not $Ok) { $script:Failed = $true }
}
function Md5([string]$Path) { (Get-FileHash -Algorithm MD5 -Path $Path).Hash }
function WriteAscii($path, $text) {
  $t = ($text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($path, $t, (New-Object System.Text.ASCIIEncoding))
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# ---- python helpers: read / plant a schema_meta value, checkpointed ---------
$pyGet = Join-Path $WorkDir 'meta_get.py'
WriteAscii $pyGet @'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
r = c.execute("SELECT value FROM schema_meta WHERE key = ?", (sys.argv[2],)).fetchone()
print('' if r is None else r[0])
c.close()
'@
$pySet = Join-Path $WorkDir 'meta_set.py'
WriteAscii $pySet @'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("INSERT OR REPLACE INTO schema_meta(key, value) VALUES (?, ?)", (sys.argv[2], sys.argv[3]))
c.commit()
c.execute("PRAGMA wal_checkpoint(TRUNCATE)")
c.close()
'@
function MetaGet([string]$Db, [string]$Key) { (& python $pyGet $Db $Key).Trim() }
function MetaSet([string]$Db, [string]$Key, [string]$Value) { & python $pySet $Db $Key $Value | Out-Null }
function StampVersion([string]$Fp) { if ($Fp -match '^v=([^;]+);') { return $Matches[1] } else { return '' } }
function PlantExtractor([string]$Db, [string]$Version) {
  $fp = MetaGet $Db 'indexer_fingerprint'
  $new = $fp -replace '^v=[^;]+;', ('v=' + $Version + ';')
  MetaSet $Db 'indexer_fingerprint' $new
}
function SidecarBytes([string]$Db) {
  $w = "$Db-wal"; if (Test-Path $w) { return (Get-Item $w).Length } else { return 0 }
}

# ---- the engine's own extractor version, from the BUILT exe -----------------
$info = (& $Exe info --json 2>&1 | Where-Object { "$_" -like '{*' } | Select-Object -First 1)
$engineVer = ''
try { $engineVer = [string](($info | ConvertFrom-Json).extractor_version) } catch { $engineVer = '' }
Check 'V0 info --json reports the extractor version' ($engineVer -match '^\d+\.\d+\.\d+') "extractor_version=$engineVer"
if ($engineVer -notmatch '^\d+\.\d+\.\d+') { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }

# ---- fixture -----------------------------------------------------------------
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $src | Out-Null
WriteAscii (Join-Path $src 'Fixture.pas') @'
unit Fixture;

interface

type
  TFoo = class
  public
    function Greet: string;
    procedure DoWork;
  end;

implementation

function TFoo.Greet: string;
begin
  Result := 'hello world from fixture';
end;

procedure TFoo.DoWork;
begin
  Greet;
end;

end.
'@

$pristine = Join-Path $WorkDir 'pristine.sqlite'
$o0 = (& $Exe index $src --db $pristine 2>&1 | Out-String)
Check 'V1 fixture index exits 0' ($LASTEXITCODE -eq 0) ($o0 -split "`r?`n" | Select-Object -Last 1)
Check 'V2 fixture has NO pending -wal (checkpointed by the run)' ((SidecarBytes $pristine) -eq 0) "wal bytes=$(SidecarBytes $pristine)"
$fp0 = MetaGet $pristine 'indexer_fingerprint'
Check 'V3 fixture stamp carries the engine extractor version' ((StampVersion $fp0) -eq $engineVer) "stamp=$fp0"
$schema0 = MetaGet $pristine 'schema_version'
Check 'V4 fixture carries a numeric schema_version' ($schema0 -match '^\d+$') "schema_version=$schema0"
$files0 = (& python -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); print(c.execute('SELECT COUNT(*) FROM files').fetchone()[0])" $pristine).Trim()
Check 'V5 fixture is POPULATED (files rows > 0), not merely present' ([int]$files0 -gt 0) "files=$files0"

$db = Join-Path $WorkDir 'under-test.sqlite'
function Fresh() {
  foreach ($s in @('', '-wal', '-shm')) { if (Test-Path "$db$s") { Remove-Item -Force "$db$s" } }
  Copy-Item $pristine $db
}
function RunIndex([string[]]$ExtraArgs) {
  $argv = @('index', $src, '--db', $db) + $ExtraArgs
  $script:LastOut = (& $Exe @argv 2>&1 | Out-String)
  $script:LastExit = $LASTEXITCODE
}
$reparseLine = 'Indexer changed since this DB was built'

# ---- R0: equal stamp ---------------------------------------------------------
Write-Host ''
Write-Host 'R0: EQUAL stamp -- an ordinary incremental run' -ForegroundColor Cyan
Fresh
RunIndex @()
Check 'R0 exit 0' ($script:LastExit -eq 0) "exit=$($script:LastExit)"
Check 'R0 no re-parse announced' ($script:LastOut -notmatch [regex]::Escape($reparseLine))
Check 'R0 stamp unchanged' ((StampVersion (MetaGet $db 'indexer_fingerprint')) -eq $engineVer)

# ---- R1: stamp NEWER, plain --------------------------------------------------
$newer = '9.0.0-alpha'
foreach ($variant in @(@(), @('--rebuild'), @('--force-reparse'))) {
  $label = if ($variant.Count -eq 0) { 'R1' } else { 'R1 ' + ($variant -join ' ') }
  Write-Host ''
  Write-Host ("{0}: stamp NEWER than the engine ({1} > {2})" -f $label, $newer, $engineVer) -ForegroundColor Cyan
  Fresh
  PlantExtractor $db $newer
  Check "$label precondition: planted stamp is in the main file" ((StampVersion (MetaGet $db 'indexer_fingerprint')) -eq $newer -and (SidecarBytes $db) -eq 0)
  $md5 = Md5 $db
  RunIndex $variant
  Check "$label REFUSES (exit 2)" ($script:LastExit -eq 2) "exit=$($script:LastExit)"
  Check "$label names the database's version" ($script:LastOut -match [regex]::Escape($newer)) ''
  Check "$label names the engine's version" ($script:LastOut -match [regex]::Escape($engineVer)) ''
  Check "$label says it refused" ($script:LastOut -match '(?i)refus') (($script:LastOut -split "`r?`n" | Where-Object { $_ -match '(?i)refus' } | Select-Object -First 1))
  Check "$label did NOT announce a re-parse" ($script:LastOut -notmatch [regex]::Escape($reparseLine))
  Check "$label file byte-identical" ((Md5 $db) -eq $md5) "before=$md5 after=$(Md5 $db)"
  Check "$label stamp still the NEWER one (refused, not 'nothing happened')" ((StampVersion (MetaGet $db 'indexer_fingerprint')) -eq $newer) "stamp=$(MetaGet $db 'indexer_fingerprint')"
}

# ---- R2: the lexical trap ----------------------------------------------------
# Find a version that is numerically ABOVE the engine but sorts BELOW it as a
# string. For engine 1.16.0 that is 1.100.0 ('0' < '6' at the third character).
Write-Host ''
Write-Host 'R2: LEXICAL TRAP -- numerically newer, lexically older' -ForegroundColor Cyan
$null = $engineVer -match '^(\d+)\.(\d+)\.(\d+)(.*)$'
$maj = [int]$Matches[1]; $min = [int]$Matches[2]; $suffix = $Matches[4]
$trap = ''
for ($m = $min + 1; $m -le $min + 400 -and -not $trap; $m++) {
  for ($p = 0; $p -le 9 -and -not $trap; $p++) {
    $cand = "$maj.$m.$p$suffix"
    if ([string]::CompareOrdinal($cand, $engineVer) -lt 0) { $trap = $cand }
  }
}
Check 'R2 precondition: found a version that sorts BELOW the engine as a string yet is numerically ABOVE it' ($trap -ne '') "engine=$engineVer trap=$trap"
if ($trap) {
  Fresh
  PlantExtractor $db $trap
  $md5 = Md5 $db
  RunIndex @()
  Check 'R2 REFUSES (exit 2) -- a string comparison would have let this through' ($script:LastExit -eq 2) "exit=$($script:LastExit)"
  Check 'R2 file byte-identical' ((Md5 $db) -eq $md5)
  Check 'R2 stamp still the trap version' ((StampVersion (MetaGet $db 'indexer_fingerprint')) -eq $trap) "stamp=$(MetaGet $db 'indexer_fingerprint')"
}

# ---- R3: POSITIVE CONTROL -- stamp OLDER, the engine writes normally --------
Write-Host ''
Write-Host 'R3: POSITIVE CONTROL -- stamp OLDER than the engine: the normal bump-and-re-parse path' -ForegroundColor Cyan
$older = '0.1.0-alpha'
Fresh
PlantExtractor $db $older
RunIndex @()
Check 'R3 exit 0' ($script:LastExit -eq 0) "exit=$($script:LastExit)"
Check 'R3 re-parse announced' ($script:LastOut -match [regex]::Escape($reparseLine))
Check 'R3 stamp is now the engine version (the write happened)' ((StampVersion (MetaGet $db 'indexer_fingerprint')) -eq $engineVer) "stamp=$(MetaGet $db 'indexer_fingerprint')"
Check 'R3 no refusal text' ($script:LastOut -notmatch '(?i)refus')

# ---- R4: schema NEWER --------------------------------------------------------
Write-Host ''
Write-Host 'R4: schema_version NEWER than the engine' -ForegroundColor Cyan
Fresh
$schemaNewer = [string]([int]$schema0 + 1000)
MetaSet $db 'schema_version' $schemaNewer
$md5 = Md5 $db
RunIndex @()
Check 'R4 REFUSES (exit 2)' ($script:LastExit -eq 2) "exit=$($script:LastExit)"
Check 'R4 names both schema versions' (($script:LastOut -match "v$schemaNewer\b") -and ($script:LastOut -match "v$schema0\b")) (($script:LastOut -split "`r?`n" | Where-Object { $_ -match 'schema' } | Select-Object -First 1))
Check 'R4 file byte-identical' ((Md5 $db) -eq $md5)
Check 'R4 schema_version still the newer one' ((MetaGet $db 'schema_version') -eq $schemaNewer) "schema_version=$(MetaGet $db 'schema_version')"

# ---- R5: the manifest path (index --all) ------------------------------------
Write-Host ''
Write-Host 'R5: index --all (BuildPlanItem) refuses the same way' -ForegroundColor Cyan
$manifest = Join-Path $WorkDir 'manifest.drag-lint.json'
$mtext = '{' + [char]10 +
  '  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 1 },' + [char]10 +
  '  "indexes": { "outDir": "out", "sections": [ { "name": "SecND", "db": "nd.sqlite", "include": ["src"] } ] }' + [char]10 +
  '}'
[System.IO.File]::WriteAllText($manifest, $mtext, [System.Text.Encoding]::ASCII)
$allDb = Join-Path $WorkDir 'out\nd.sqlite'
Push-Location C:\TEMP
try {
  $b0 = (& $Exe index --all --config $manifest --only SecND --jobs 1 2>&1 | Out-String)
  Check 'R5 precondition: the manifest section built' ((Test-Path $allDb) -and ($LASTEXITCODE -eq 0)) "exit=$LASTEXITCODE"
  if (Test-Path $allDb) {
    PlantExtractor $allDb $newer
    $md5 = Md5 $allDb
    $b1 = (& $Exe index --all --config $manifest --only SecND --jobs 1 2>&1 | Out-String)
    $e1 = $LASTEXITCODE
    Check 'R5 exits non-zero' ($e1 -ne 0) "exit=$e1"
    Check 'R5 names both versions' (($b1 -match [regex]::Escape($newer)) -and ($b1 -match [regex]::Escape($engineVer))) ''
    Check 'R5 did NOT announce a re-parse' ($b1 -notmatch [regex]::Escape($reparseLine))
    Check 'R5 file byte-identical' ((Md5 $allDb) -eq $md5)
    Check 'R5 stamp still the NEWER one' ((StampVersion (MetaGet $allDb 'indexer_fingerprint')) -eq $newer) "stamp=$(MetaGet $allDb 'indexer_fingerprint')"
  }
} finally { Pop-Location }

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
