<#
  check-engine-drift.ps1 -- the converter stream's periodic engine + INBOX check.

  WHY THIS EXISTS. The rule editor shells out to drag-lint.exe for six verbs, and
  the engine stream builds that exe from the SAME working tree we develop in. On
  2026-09-14 the deployed engine was rebuilt at 12:55 and again at 14:02 during a
  single converter session, silently changing the binary under a GUI test in
  progress. So the editor runs against a PINNED snapshot, and this script is what
  tells us the pin has fallen behind.

  THE TRAP IT IS BUILT AROUND. The version STRING is not a drift signal. Both the
  12:55 and the 14:02 builds reported "1.11.0-alpha". Only the SHA256 and the
  build timestamp moved. This script therefore compares bytes, and treats a
  matching version string as meaning nothing at all.

  READ-ONLY by design: it writes nothing and updates no "last checked" state, so
  running it can never itself become the thing that drifts. The baseline is always
  the pin's own manifest.

  EXIT CODES (match on these, not on the text):
    0  pin matches the deployed engine AND no new INBOX notes since the pin
    1  ACTION NEEDED -- engine drifted, or new/open notes are addressed to us
    2  cannot answer -- pin or deployed engine missing/unreadable

  USAGE
    .\check-engine-drift.ps1
    .\check-engine-drift.ps1 -PinDir <dir>     # test a specific pin
#>
[CmdletBinding()]
param(
  [string] $PinDir   = '',
  [string] $Deployed = 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe',
  [string] $DocsDir  = 'C:\Projects\Delphi-RAG-lint\docs',
  [string] $PinRoot  = 'C:\Projects\Delphi-RAG-lint\third_party\engine-pinned'
)

$ErrorActionPreference = 'Stop'

function Say([string] $s) { Write-Output $s }

# --- locate the pin -----------------------------------------------------------
if ($PinDir -eq '') {
  if (-not (Test-Path $PinRoot)) {
    Say "ERROR: no pin root at $PinRoot -- nothing is pinned."
    exit 2
  }
  $cand = Get-ChildItem $PinRoot -Directory -ErrorAction SilentlyContinue |
          Where-Object { Test-Path (Join-Path $_.FullName 'ENGINE-PIN.json') } |
          Sort-Object Name -Descending
  if (-not $cand) { Say "ERROR: no directory under $PinRoot carries an ENGINE-PIN.json."; exit 2 }
  $PinDir = $cand[0].FullName
}

$manifestPath = Join-Path $PinDir 'ENGINE-PIN.json'
if (-not (Test-Path $manifestPath)) { Say "ERROR: no ENGINE-PIN.json in $PinDir"; exit 2 }
try { $pin = Get-Content $manifestPath -Raw | ConvertFrom-Json }
catch { Say "ERROR: ENGINE-PIN.json is not readable JSON: $($_.Exception.Message)"; exit 2 }

$pinExe = Join-Path $PinDir 'drag-lint.exe'
if (-not (Test-Path $pinExe))   { Say "ERROR: the pin has a manifest but no drag-lint.exe: $PinDir"; exit 2 }
if (-not (Test-Path $Deployed)) { Say "ERROR: deployed engine not found: $Deployed"; exit 2 }

Say "PIN      : $PinDir"
Say "pinned   : $($pin.pinned_utc)   version $($pin.version_string)   built $($pin.build_timestamp)"

# --- the pin must still BE what it says it is ---------------------------------
# A pin whose own bytes no longer match its manifest is worse than no pin: it is
# an authoritative-looking baseline for a binary nobody chose.
$pinNow = (Get-FileHash $pinExe -Algorithm SHA256).Hash
$problems = 0
if ($pinNow -ne $pin.exe_sha256) {
  Say ''
  Say "!! THE PIN ITSELF HAS CHANGED. Its manifest no longer describes its own exe."
  Say "   manifest : $($pin.exe_sha256)"
  Say "   on disk  : $pinNow"
  Say "   Re-pin from a known-good engine; do not trust this snapshot."
  $problems++
}

# --- compare pin against the deployed engine ----------------------------------
$depHash  = (Get-FileHash $Deployed -Algorithm SHA256).Hash
$depBuild = (Get-Item $Deployed).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
$depVer   = ''
try {
  $info = & $Deployed info 2>&1 | Select-Object -First 1
  if ($info -match 'drag-lint\s+(\S+)') { $depVer = $Matches[1] }
} catch { $depVer = '<info failed>' }

Say "DEPLOYED : $Deployed"
Say "           version $depVer   built $depBuild"
Say ''

if ($depHash -eq $pin.exe_sha256) {
  Say "ENGINE   : IN SYNC -- deployed engine is byte-identical to the pin."
} else {
  Say "ENGINE   : *** DRIFTED *** the deployed engine is not the pinned one."
  Say "           pinned   sha256 $($pin.exe_sha256)  built $($pin.build_timestamp)"
  Say "           deployed sha256 $depHash  built $depBuild"
  if ($depVer -eq $pin.version_string) {
    Say "           NOTE: both report version '$depVer'. The version string is NOT"
    Say "           a drift signal -- only the hash and build time are."
  }
  Say "           -> read the INBOX notes below, then re-pin when the engine change is settled."
  $problems++
}

# --- INBOX notes --------------------------------------------------------------
Say ''
if (-not (Test-Path $DocsDir)) {
  Say "INBOX    : ERROR -- docs dir not found: $DocsDir"
  exit 2
}

try { $pinnedAt = [DateTime]::Parse($pin.pinned_utc).ToLocalTime() }
catch { $pinnedAt = (Get-Item $pinExe).LastWriteTime }

# Only top-level INBOX-*.md: docs\INBOX-Done\ is, by construction, discharged.
$notes = Get-ChildItem $DocsDir -Filter 'INBOX-*.md' -File -ErrorAction SilentlyContinue

$addressed = @()   # written TO us by the engine stream
$newSince  = @()   # anything that landed after we pinned
foreach ($n in $notes) {
  $isOurs = ($n.Name -match 'engine-to-converter|convrules|converter')
  if ($isOurs) { $addressed += $n }
  if ($n.LastWriteTime -gt $pinnedAt) { $newSince += $n }
}

Say "INBOX    : $($notes.Count) open note(s) in docs\; $($addressed.Count) addressed to the converter stream."

if ($newSince.Count -gt 0) {
  Say ''
  Say "  NEW OR TOUCHED SINCE THE PIN ($($pinnedAt.ToString('yyyy-MM-dd HH:mm'))):"
  foreach ($n in ($newSince | Sort-Object LastWriteTime -Descending)) {
    $status = ''
    $first = Get-Content $n.FullName -TotalCount 1 -ErrorAction SilentlyContinue
    if ($first -match 'status=(\w+)') { $status = " [status=$($Matches[1])]" }
    Say ("    {0}  {1}{2}" -f $n.LastWriteTime.ToString('MM-dd HH:mm'), $n.Name, $status)
  }
  $problems++
} else {
  Say "           nothing new since the pin."
}

if ($addressed.Count -gt 0) {
  Say ''
  Say "  ADDRESSED TO US (re-read before assuming an answer is still current):"
  foreach ($n in ($addressed | Sort-Object LastWriteTime -Descending)) {
    Say ("    {0}  {1}" -f $n.LastWriteTime.ToString('MM-dd HH:mm'), $n.Name)
  }
}

Say ''
if ($problems -eq 0) {
  Say "RESULT   : clean -- pin is current and no new notes. Carry on."
  exit 0
}
Say "RESULT   : ACTION NEEDED ($problems item(s) above)."
Say "           Re-pin with:  copy the dll-win64 tree to"
Say "           third_party\engine-pinned\<version>-<yyyyMMdd-HHmmss>\ and write a"
Say "           fresh ENGINE-PIN.json. Verify the new pin RUNS (info + rules + one"
Say "           real query) before trusting it -- a pin that exists but cannot"
Say "           answer is worse than none."
exit 1
