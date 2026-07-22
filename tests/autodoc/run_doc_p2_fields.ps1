<#
  run_doc_p2_fields.ps1 -- Auto-Document Phase 2, Task 4: Reads/Writes fields
  fact (which instance fields of the owning class a routine reads vs.
  writes).

  Uses fixtures\docp2\fields.pas: TCounter (FCount: Integer; FName: string;
  plus FA..FH: Integer) with three methods:
    * Bump -- reads FName (an 'if' guard), writes FCount (an Inc target in
      one branch, a plain ':=' in the other). Expect the managed block to
      carry 'Reads: FName' and 'Writes: FCount' with no overlap.
    * AddN(N) -- 'FCount := FCount + N' reads AND writes FCount in the SAME
      statement. Expect FCount in BOTH Reads and Writes.
    * TouchMany -- writes NINE distinct fields (FA..FH, FCount) and reads
      none. Expect the display cap (8 shown) + ' (+1 more)' suffix, and NO
      'Reads:' segment at all (an empty side is omitted, never rendered as
      an empty 'Reads: ').

  Drives `index` -> `document --unit --apply` (Stubs=False, the default: a
  decl with NO prior doc-comment and NO facts is skipped entirely -- see
  DRagLint.Doc.Batch's facts-only filter -- so BEFORE Task 4 these three
  methods get NO managed block whatsoever; the RED state is "no block", not
  "block missing one line").

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp2\fields.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_docp2fields'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'fields.pas'
$db     = Join-Path $scratch 'docp2fields.sqlite'
Copy-Item $fixture $target -Force

# Same scan-upward idiom as run_doc_p2_complexity.ps1's Get-DocBlockAbove:
# returns the contiguous run of ///-prefixed lines immediately above the
# FIRST line matching $declPattern. $null if the declaration is not found.
function Get-DocBlockAbove([string[]]$lines, [string]$declPattern) {
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $declPattern) { $idx = $i; break } }
  if ($idx -lt 0) { return $null }
  $blockLines = @()
  $j = $idx - 1
  while ($j -ge 0 -and $lines[$j].TrimStart() -match '^///') { $blockLines = ,($lines[$j]) + $blockLines; $j-- }
  return ($blockLines -join "`n")
}

# Extracts the segment after "<label>: " up to (but not including) the '   '
# (3-space) separator that precedes a sibling segment on the SAME line, or to
# end of that line otherwise. $null if <label> does not appear in $block at
# all (distinguishes "segment present but empty" -- impossible per the
# renderer's own omit-when-empty rule -- from "segment/side absent").
function Get-Segment([string]$block, [string]$label) {
  if ($null -eq $block) { return $null }
  $m = [regex]::Match($block, "${label}: ([^\r\n]*)")
  if (-not $m.Success) { return $null }
  $rest = $m.Groups[1].Value
  $idx = $rest.IndexOf('   ')
  if ($idx -ge 0) { return $rest.Substring(0, $idx) }
  return $rest
}

# Order-insensitive EXACT-SET comparison: $segment's comma-separated entries
# (trimmed) must be exactly $expectedNames, no more, no fewer.
function Test-NamesEqual([string]$segment, [string[]]$expectedNames) {
  if ($null -eq $segment) { return $false }
  $actual = @($segment -split ',\s*' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
  $expSorted = ($expectedNames | Sort-Object) -join '|'
  $actSorted = ($actual | Sort-Object) -join '|'
  return $expSorted -eq $actSorted
}

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
  Check 'document --apply #1 exits 0' ($LASTEXITCODE -eq 0)

  $lines = [IO.File]::ReadAllLines($target)

  # --- Bump: Reads: FName / Writes: FCount, no overlap ---------------------
  $bumpBlock = Get-DocBlockAbove $lines '^\s*procedure Bump;\s*$'
  Check 'Bump has a managed block (AUTO_BEGIN)' (($null -ne $bumpBlock) -and ($bumpBlock -match '<!-- drag-lint:auto BEGIN -->'))
  Check 'Bump Reads is exactly {FName}'  (Test-NamesEqual (Get-Segment $bumpBlock 'Reads')  @('FName'))
  Check 'Bump Writes is exactly {FCount}' (Test-NamesEqual (Get-Segment $bumpBlock 'Writes') @('FCount'))

  # --- AddN: FCount in BOTH Reads and Writes --------------------------------
  $addnBlock = Get-DocBlockAbove $lines '^\s*procedure AddN\(N: Integer\);\s*$'
  Check 'AddN has a managed block (AUTO_BEGIN)' (($null -ne $addnBlock) -and ($addnBlock -match '<!-- drag-lint:auto BEGIN -->'))
  Check 'AddN Reads is exactly {FCount}'  (Test-NamesEqual (Get-Segment $addnBlock 'Reads')  @('FCount'))
  Check 'AddN Writes is exactly {FCount}' (Test-NamesEqual (Get-Segment $addnBlock 'Writes') @('FCount'))

  # --- TouchMany: cap at 8 + '(+1 more)', Reads side omitted entirely ------
  $touchBlock = Get-DocBlockAbove $lines '^\s*procedure TouchMany;\s*$'
  Check 'TouchMany has a managed block (AUTO_BEGIN)' (($null -ne $touchBlock) -and ($touchBlock -match '<!-- drag-lint:auto BEGIN -->'))
  Check 'TouchMany has NO Reads segment (empty side omitted, not rendered empty)' ($null -eq (Get-Segment $touchBlock 'Reads'))
  $writesSeg = Get-Segment $touchBlock 'Writes'
  Check 'TouchMany has a Writes segment' ($null -ne $writesSeg)
  if ($null -ne $writesSeg) {
    Check 'TouchMany Writes is 8 comma-joined names + '' (+1 more)''' ($writesSeg -match '^(?:F[A-H], ){7}F[A-H] \(\+1 more\)$')
    $shownNames = ($writesSeg -replace ' \(\+1 more\)$', '') -split ',\s*'
    Check 'TouchMany Writes shows 8 DISTINCT FA..FH names' (($shownNames | Select-Object -Unique).Count -eq 8)
    Check 'TouchMany Writes does NOT include FCount (9th occurrence, dropped by the cap)' ($writesSeg -notmatch 'FCount')
  }

  # --- Idempotency: reindex (facts are index-time) + re-apply -> no change ---
  $before = [IO.File]::ReadAllBytes($target)
  & $exePath index $scratch --db $db 2>$null | Out-Null
  & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
  $after = [IO.File]::ReadAllBytes($target)
  Check 'idempotent: file byte-identical after reindex + 2nd apply' ([System.Linq.Enumerable]::SequenceEqual([byte[]]$before,[byte[]]$after))
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
