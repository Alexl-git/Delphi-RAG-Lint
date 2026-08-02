<#
  run_doc_p3_harvest_impl.ps1 -- Auto-Document Phase 3, Task 8:
  implementation-side harvest, with interface-side precedence.

  WHY THIS IS WHERE THE VOLUME IS. Task 7 scans only the INTERFACE declaration.
  On the YADF corpus, 120 of 121 harvestable comments sit above the BODY, not
  above the declaration -- authors comment the code they are writing, while
  DocInsight renders the declaration. So T7 alone harvests roughly one comment in
  a hundred.

  THE ORDER, and it is the whole task: interface declaration FIRST, then the
  implementation definition; first accepted hit wins and the search STOPS. A
  comment above the declaration is unambiguously about the declaration, so it
  outranks one above the body.

  PROMOTED, NOT MOVED. The harvested text lands on the INTERFACE declaration
  while the original // comment stays exactly where the author put it. That is
  the point of the feature and also its main hazard, so assertion 4 reads the
  implementation section back and asserts all three comments survive verbatim,
  and assertion 5 asserts nothing was written above a body.

  HAND-WRITTEN WINS. A symbol with a real hand-written <summary> must never have
  a harvest run into it. The plan expects MergeComment's repair path to be
  handling that already (Task 3's three-way classification puts a hand-written
  summary on the preserve-verbatim arm); this suite is what proves it, rather
  than assuming it -- and it checks the marker is absent, not merely that the
  text looks right, because a refreshed-but-identical string would look the same.

  Runs from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$fx      = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\harvest_impl.pas')).Path

function Get-FileMd5([string]$p) { (Get-FileHash -Algorithm MD5 -Path $p).Hash }

# INTERFACE-section start line for $name, read back from the index via the
# engine's own query verb (index-first: no second parser).
function Get-DeclLine([string]$db, [string]$name) {
  $j = (& $exePath query --name $name --db $db --json 2>$null) -join "`n"
  $o = $null; try { $o = ($j | ConvertFrom-Json) } catch { return 0 }
  if ($null -eq $o) { return 0 }
  foreach ($r in @($o)) { if ($r.section -eq 'interface') { return [int]$r.start_line } }
  return 0
}

# The contiguous run of ///-prefixed lines immediately above 1-based $declLine1,
# per-line trimmed and newline-joined. Tolerates ONE leading blank line,
# mirroring FindDocRegionAbove's AllowGap=1 default.
function Get-DocBlockAtLine([string[]]$lines, [int]$declLine1) {
  $i = $declLine1 - 2
  if ($i -lt 0) { return '' }
  if ($lines[$i].Trim() -eq '') { $i-- }
  $acc = New-Object System.Collections.Generic.List[string]
  for (; $i -ge 0; $i--) {
    if ($lines[$i] -notmatch '^\s*///') { break }
    $acc.Insert(0, $lines[$i].Trim())
  }
  return [string]::Join("`n", $acc.ToArray())
}

function Get-Summary([string]$block) {
  $flat = ($block -split "`n" | ForEach-Object { $_ -replace '^\s*///\s?','' }) -join ' '
  $m = [regex]::Match($flat, '<summary>(?:<!-- drag-lint:auto -->)?\s*(.*?)\s*</summary>')
  if ($m.Success) { return ($m.Groups[1].Value -replace '\s+',' ').Trim() } else { return '' }
}

# Is the marker on the <summary> SPECIFICALLY? Scoped deliberately: a documented
# symbol's block also carries markers on <returns> and on the facts fence, both
# of which are correct and engine-owned, so a whole-block search answers a
# different question and reports "hand-written summary was refreshed" for a
# symbol whose summary was never touched. First draft of this suite did exactly
# that and flagged two false failures.
function Test-SummaryMarked([string]$block) {
  $flat = ($block -split "`n" | ForEach-Object { $_ -replace '^\s*///\s?','' }) -join ' '
  return [regex]::IsMatch($flat, '<summary>\s*<!-- drag-lint:auto -->')
}

Push-Location C:\TEMP
try {

Write-Host ''
Write-Host '=== harvest_impl.pas, document --unit --apply ===' -ForegroundColor Cyan

$sc = Join-Path C:\TEMP 'draglint_docp3_harvestimpl'
if (Test-Path $sc) { Remove-Item $sc -Recurse -Force }
New-Item -ItemType Directory -Path $sc | Out-Null
$tgt = Join-Path $sc 'harvest_impl.pas'
$db  = Join-Path $sc 'h.sqlite'
Copy-Item $fx $tgt -Force

& $exePath index $sc --db $db 2>$null | Out-Null

# --- PRECONDITIONS ----------------------------------------------------------
# Without these, every assertion below could pass against a fixture that no
# longer poses the question the suite exists to ask.
$pre = [IO.File]::ReadAllLines($tgt)
Check 'PRECONDITION: exactly ONE /// line before the apply (HandWins'' hand-written summary)' `
  (@($pre | Where-Object { $_ -match '^\s*///' }).Count -eq 1) ''
Check 'PRECONDITION: ImplOnly has NO comment above its interface declaration' `
  ($null -eq ($pre | Select-String -Pattern '^// .*ImplOnly' | Where-Object { $_.LineNumber -lt 14 })) ''
Check 'PRECONDITION: all three implementation-side // comments are present' `
  ((@($pre | Where-Object { $_ -match '^// Implementation-side' }).Count) -eq 3) ''

# ===========================================================================
# APPLY
# ===========================================================================
& $exePath document --unit $tgt --db $db --apply 2>$null | Out-Null
$md5Cycle1 = Get-FileMd5 $tgt
& $exePath index $sc --db $db 2>$null | Out-Null

$post = [IO.File]::ReadAllLines($tgt)

# --- 1. THE TASK: an implementation-side comment reaches the DECLARATION -----
$lnImplOnly = Get-DeclLine $db 'ImplOnly'
Check '1. ImplOnly''s interface declaration was located' ($lnImplOnly -gt 0) "line=$lnImplOnly"
$blkImplOnly = Get-DocBlockAtLine $post $lnImplOnly
Check '1. ImplOnly''s summary is the IMPLEMENTATION-side prose, promoted onto the declaration' `
  ((Get-Summary $blkImplOnly) -eq 'Implementation-side prose for ImplOnly.') `
  "summary='$(Get-Summary $blkImplOnly)'"
Check '1. ...and the SUMMARY is marked engine-owned' (Test-SummaryMarked $blkImplOnly) ''

# --- 2. PRECEDENCE: interface side outranks implementation side -------------
$lnBoth = Get-DeclLine $db 'BothSides'
$blkBoth = Get-DocBlockAtLine $post $lnBoth
Check '2. BothSides takes the INTERFACE-side comment' `
  ((Get-Summary $blkBoth) -eq 'Interface-side prose wins.') "summary='$(Get-Summary $blkBoth)'"
Check '2. BothSides did NOT take the implementation-side comment' `
  ($blkBoth -notmatch 'must LOSE') ''

# --- 3. HAND-WRITTEN WINS ---------------------------------------------------
$lnHand = Get-DeclLine $db 'HandWins'
$blkHand = Get-DocBlockAtLine $post $lnHand
Check '3. HandWins keeps its hand-written summary' `
  ((Get-Summary $blkHand) -eq 'Hand-written and authoritative.') "summary='$(Get-Summary $blkHand)'"
Check '3. ...and the SUMMARY is NOT marked (a refresh would have marked it)' `
  (-not (Test-SummaryMarked $blkHand)) ''
Check '3. ...and the implementation-side comment did not leak in' `
  ($blkHand -notmatch 'must lose') ''

# --- 4. COPY, NEVER MOVE ----------------------------------------------------
Check '4. all three implementation-side // comments survive VERBATIM' `
  ((@($post | Where-Object { $_ -match '^// Implementation-side' }).Count) -eq 3) `
  "found=$(@($post | Where-Object { $_ -match '^// Implementation-side' }).Count)"
Check '4. the interface-side // comment survives too' `
  ((@($post | Where-Object { $_ -match '^// Interface-side prose wins\.' }).Count) -eq 1) ''

# --- 5. NOTHING is written above an implementation DEFINITION ---------------
# The engine documents declarations. A /// block above a body would be both
# wrong and invisible to DocInsight. Locate the implementation section and
# assert it holds no /// at all.
$implIdx = ($post | Select-String -Pattern '^implementation' | Select-Object -First 1).LineNumber
Check '5. the implementation section was located' ($implIdx -gt 0) "line=$implIdx"
$implLines = $post[($implIdx)..($post.Count - 1)]
Check '5. NO /// line anywhere in the implementation section' `
  ((@($implLines | Where-Object { $_ -match '^\s*///' }).Count) -eq 0) `
  "found=$(@($implLines | Where-Object { $_ -match '^\s*///' }).Count)"

# --- 6. IDEMPOTENCY ---------------------------------------------------------
& $exePath document --unit $tgt --db $db --apply 2>$null | Out-Null
$md5Cycle2 = Get-FileMd5 $tgt
Check '6. a second apply is byte-identical' ($md5Cycle1 -eq $md5Cycle2) `
  "md5 c1=$($md5Cycle1.Substring(0,8)) c2=$($md5Cycle2.Substring(0,8))"

} finally { Pop-Location }

Write-Host ''
if ($script:Failed) { Write-Host 'HARVEST IMPL: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'HARVEST IMPL: PASS' -ForegroundColor Green
exit 0
