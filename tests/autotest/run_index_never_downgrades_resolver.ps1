<#
  run_index_never_downgrades_resolver.ps1 -- an engine whose RESOLVER is older
  than the one that stamped a database refuses to write it
  (docs\INBOX-URGENT-resolver-downgrade-not-refused.md, ENG-2).

  THE HAZARD. RefuseIfEngineOlderThanDb covered the extractor and the schema
  axes and not the resolver. The resolver fingerprint (`r=<ver>;schema=N`) is
  compared for INEQUALITY: any difference clears every call edge, re-derives
  them with THIS engine's resolver and stamps ITS version. So a 1.5.1 engine
  re-resolving a 1.6.0 index silently undid the newer resolve -- exit 0, the
  newer stamp gone. run_index_never_downgrades.ps1 pins the other two axes;
  this is the third, with the same rows and the same rules:

    R0  equal resolver stamp        -> exit 0, stamp unchanged
    R1  resolver NEWER (9.x)        -> exit 2, BOTH versions named, "refus",
                                       file byte-identical, stamp still newer;
                                       plain, --rebuild, --force-reparse AND
                                       --resolve-only (the pure resolver write)
    R2  LEXICAL TRAP                -> numerically newer, lexically older: refuse
    R3  POSITIVE CONTROL            -> resolver OLDER -> exit 0, re-derive
                                       announced, stamp becomes the engine's
    R4  absent stamp                -> exit 0 (an absent stamp is STALE, never
                                       newer -- run_resolver_stamp_absent_is_stale)
    R5  index --all (BuildPlanItem) -> refuses the same way
    N1  the read-side note states the DIRECTION: a newer stamp is named as
        NEWER and is NOT told to re-derive with --resolve-only (the old note
        gave "your edges are stale, re-derive" for both directions)

  The stamp is planted with python's sqlite3 and CHECKPOINTED, exactly as the
  sibling suite does, so the md5 before the run is of a file that holds it.

  RED FIRST against the merged 1.17.0-alpha engine: R1/R2/R5 exit 0 and stamp
  the engine's resolver over the newer one; N1 prints the re-derive advice.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-never-downgrade-resolver"
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
if sys.argv[3] == '<DELETE>':
    c.execute("DELETE FROM schema_meta WHERE key = ?", (sys.argv[2],))
else:
    c.execute("INSERT OR REPLACE INTO schema_meta(key, value) VALUES (?, ?)", (sys.argv[2], sys.argv[3]))
c.commit()
c.execute("PRAGMA wal_checkpoint(TRUNCATE)")
c.close()
'@
function MetaGet([string]$Db, [string]$Key) { (& python $pyGet $Db $Key).Trim() }
function MetaSet([string]$Db, [string]$Key, [string]$Value) { & python $pySet $Db $Key $Value | Out-Null }
function StampVersion([string]$Fp) { if ($Fp -match '^r=([^;]+);') { return $Matches[1] } else { return '' } }
function PlantResolver([string]$Db, [string]$Version) {
  $fp = MetaGet $Db 'resolver_fingerprint'
  MetaSet $Db 'resolver_fingerprint' ($fp -replace '^r=[^;]+;', ('r=' + $Version + ';'))
}
function SidecarBytes([string]$Db) { $w = "$Db-wal"; if (Test-Path $w) { return (Get-Item $w).Length } else { return 0 } }

$info = (& $Exe info --json 2>&1 | Where-Object { "$_" -like '{*' } | Select-Object -First 1)
$engineVer = ''
try { $engineVer = [string](($info | ConvertFrom-Json).resolver_version) } catch { $engineVer = '' }
Check 'V0 info --json reports the resolver version' ($engineVer -match '^\d+\.\d+\.\d+') "resolver_version=$engineVer"
if ($engineVer -notmatch '^\d+\.\d+\.\d+') { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }

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
  Result := 'hello';
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
Check 'V2 fixture has NO pending -wal' ((SidecarBytes $pristine) -eq 0) "wal bytes=$(SidecarBytes $pristine)"
$rfp0 = MetaGet $pristine 'resolver_fingerprint'
Check 'V3 fixture resolver stamp carries the engine resolver version' ((StampVersion $rfp0) -eq $engineVer) "stamp=$rfp0"

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
$rederive = 'Resolver changed since this DB was resolved'

Write-Host ''
Write-Host 'R0: EQUAL resolver stamp' -ForegroundColor Cyan
Fresh
RunIndex @()
Check 'R0 exit 0' ($script:LastExit -eq 0) "exit=$($script:LastExit)"
Check 'R0 no refusal' ($script:LastOut -notmatch '(?i)refus')
Check 'R0 stamp unchanged' ((StampVersion (MetaGet $db 'resolver_fingerprint')) -eq $engineVer)

$newer = '9.0.0-alpha'
foreach ($variant in @(@(), @('--rebuild'), @('--force-reparse'), @('--resolve-only'))) {
  $label = if ($variant.Count -eq 0) { 'R1' } else { 'R1 ' + ($variant -join ' ') }
  Write-Host ''
  Write-Host ("{0}: resolver stamp NEWER than the engine ({1} > {2})" -f $label, $newer, $engineVer) -ForegroundColor Cyan
  Fresh
  PlantResolver $db $newer
  Check "$label precondition: planted stamp is in the main file" ((StampVersion (MetaGet $db 'resolver_fingerprint')) -eq $newer -and (SidecarBytes $db) -eq 0)
  $md5 = Md5 $db
  RunIndex $variant
  Check "$label REFUSES (exit 2)" ($script:LastExit -eq 2) "exit=$($script:LastExit)"
  Check "$label names the database's resolver version" ($script:LastOut -match [regex]::Escape($newer)) ''
  Check "$label names the engine's resolver version" ($script:LastOut -match [regex]::Escape($engineVer)) ''
  Check "$label says it refused" ($script:LastOut -match '(?i)refus') (($script:LastOut -split "`r?`n" | Where-Object { $_ -match '(?i)refus' } | Select-Object -First 1))
  Check "$label did NOT announce a re-derive" ($script:LastOut -notmatch [regex]::Escape($rederive))
  Check "$label file byte-identical" ((Md5 $db) -eq $md5) "before=$md5 after=$(Md5 $db)"
  Check "$label stamp still the NEWER one" ((StampVersion (MetaGet $db 'resolver_fingerprint')) -eq $newer) "stamp=$(MetaGet $db 'resolver_fingerprint')"
}

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
Check 'R2 precondition: a version that sorts BELOW the engine yet is numerically ABOVE it' ($trap -ne '') "engine=$engineVer trap=$trap"
if ($trap) {
  Fresh
  PlantResolver $db $trap
  $md5 = Md5 $db
  RunIndex @('--resolve-only')
  Check 'R2 REFUSES (exit 2)' ($script:LastExit -eq 2) "exit=$($script:LastExit)"
  Check 'R2 file byte-identical' ((Md5 $db) -eq $md5)
}

Write-Host ''
Write-Host 'R3: POSITIVE CONTROL -- resolver stamp OLDER: the normal re-derive path' -ForegroundColor Cyan
Fresh
PlantResolver $db '0.1.0-alpha'
RunIndex @('--resolve-only')
Check 'R3 exit 0' ($script:LastExit -eq 0) "exit=$($script:LastExit)"
Check 'R3 re-derive announced' ($script:LastOut -match [regex]::Escape($rederive))
Check 'R3 stamp is now the engine version' ((StampVersion (MetaGet $db 'resolver_fingerprint')) -eq $engineVer) "stamp=$(MetaGet $db 'resolver_fingerprint')"
Check 'R3 no refusal text' ($script:LastOut -notmatch '(?i)refus')

Write-Host ''
Write-Host 'R4: ABSENT resolver stamp -- stale, never newer' -ForegroundColor Cyan
Fresh
MetaSet $db 'resolver_fingerprint' '<DELETE>'
RunIndex @()
Check 'R4 exit 0' ($script:LastExit -eq 0) "exit=$($script:LastExit)"
Check 'R4 no refusal' ($script:LastOut -notmatch '(?i)refus')
Check 'R4 stamp written' ((StampVersion (MetaGet $db 'resolver_fingerprint')) -eq $engineVer)

Write-Host ''
Write-Host 'N1: the read-side note states the DIRECTION' -ForegroundColor Cyan
Fresh
PlantResolver $db $newer
$n1 = (& $Exe lint-project --db $db --rule god-class 2>&1 | Out-String)
$n1Line = ($n1 -split "`r?`n" | Where-Object { $_ -match 'resolver:' } | Select-Object -First 1)
Check 'N1 a note about the resolver is printed' ([bool]$n1Line) $n1Line
Check 'N1 it calls the index NEWER' ($n1Line -match 'NEWER') ''
Check 'N1 it does NOT advise re-deriving with --resolve-only' ($n1Line -notmatch 'resolve-only') 'that advice is exactly the downgrade'
Fresh
PlantResolver $db '0.1.0-alpha'
$n2 = (& $Exe lint-project --db $db --rule god-class 2>&1 | Out-String)
$n2Line = ($n2 -split "`r?`n" | Where-Object { $_ -match 'resolver:' } | Select-Object -First 1)
Check 'N1 CONTROL: an OLDER stamp still gets the re-derive advice' ($n2Line -match 'resolve-only') $n2Line

Write-Host ''
Write-Host 'R5: index --all (BuildPlanItem) refuses the same way' -ForegroundColor Cyan
$manifest = Join-Path $WorkDir 'manifest.drag-lint.json'
$mtext = '{' + [char]10 +
  '  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 1 },' + [char]10 +
  '  "indexes": { "outDir": "out", "sections": [ { "name": "SecNDR", "db": "ndr.sqlite", "include": ["src"] } ] }' + [char]10 +
  '}'
[System.IO.File]::WriteAllText($manifest, $mtext, [System.Text.Encoding]::ASCII)
$allDb = Join-Path $WorkDir 'out\ndr.sqlite'
Push-Location C:\TEMP
try {
  $null = (& $Exe index --all --config $manifest --only SecNDR --jobs 1 2>&1 | Out-String)
  Check 'R5 precondition: the manifest section built' ((Test-Path $allDb) -and ($LASTEXITCODE -eq 0)) "exit=$LASTEXITCODE"
  if (Test-Path $allDb) {
    PlantResolver $allDb $newer
    $md5 = Md5 $allDb
    $b1 = (& $Exe index --all --config $manifest --only SecNDR --jobs 1 --resolve-only 2>&1 | Out-String)
    $e1 = $LASTEXITCODE
    Check 'R5 exits non-zero' ($e1 -ne 0) "exit=$e1"
    Check 'R5 names both versions' (($b1 -match [regex]::Escape($newer)) -and ($b1 -match [regex]::Escape($engineVer))) ''
    Check 'R5 file byte-identical' ((Md5 $allDb) -eq $md5)
    Check 'R5 stamp still the NEWER one' ((StampVersion (MetaGet $allDb 'resolver_fingerprint')) -eq $newer) "stamp=$(MetaGet $allDb 'resolver_fingerprint')"
  }
} finally { Pop-Location }

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
