<#
  run_doc_p2_sql.ps1 -- Auto-Document Phase 2, Task 7: SQL tables touched
  fact (for a routine that builds SQL via string literals, which tables it
  reads (FROM/JOIN) vs. writes (INSERT INTO/UPDATE/DELETE FROM)).

  Uses fixtures\docp2\sql.pas: TSqlRunner with six methods -- see that
  file's own header comment for the full per-method rationale. Summary:
    * SyncOne          -- SQL: reads OPTRLIST; writes PDF_SCAN (the task
                           brief's own literal example).
    * RunJoinConcat     -- SELECT built from 3 concatenated literals + a
                           JOIN, each table bare-aliased -> reads OPTRLIST,
                           SCANQUEUE (proves concat-merge + alias-strip).
    * MultiFromList     -- 'FROM A, B' comma-list -> reads CLIENT, VENDOR.
    * InsertAndDelete   -- INSERT INTO + DELETE FROM -> writes SCAN_LOG,
                           TEMP_ROWS; no reads side at all.
    * DynamicQuery      -- 'SELECT * FROM ' + FTableName (a field, not a
                           literal) -> the whole run is DYNAMIC and must be
                           dropped entirely; this method DOES get a managed
                           block (via the unrelated Reads: FTableName fact)
                           but must carry NO 'SQL:' line.
    * NoSql             -- no literals, no field touch -> NO managed block
                           at all (no fact of any kind fires).

  Drives `index` -> `document --unit --apply` (Stubs=False default: a decl
  with NO prior doc-comment and NO facts is skipped entirely, so a method
  with truly zero facts -- NoSql -- gets no block whatsoever).

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp2\sql.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_docp2sql'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'sql.pas'
$db     = Join-Path $scratch 'docp2sql.sqlite'
Copy-Item $fixture $target -Force

# Same scan-upward idiom run_doc_p2_fields.ps1's Get-DocBlockAbove uses:
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

# Extracts the 'SQL: ...' line's raw value (everything after 'SQL: ' to end
# of that line), or $null if $block has no such line at all (either $block
# itself is $null -- no managed block whatsoever -- or the block exists but
# carries no SQL fact).
function Get-SqlLine([string]$block) {
  if ($null -eq $block) { return $null }
  $m = [regex]::Match($block, 'SQL: ([^\r\n]*)')
  if (-not $m.Success) { return $null }
  return $m.Groups[1].Value
}

# Splits a 'reads A, B; writes C' (or just one side) raw value into its
# reads/writes name arrays. A side's key stays $null when that side's label
# is not present at all in $sqlLine (distinguishes "side present but empty"
# -- impossible per the renderer's own omit-when-empty rule -- from "side
# absent").
function Parse-SqlLine([string]$sqlLine) {
  $result = @{ reads = $null; writes = $null }
  if ($null -eq $sqlLine) { return $result }
  foreach ($part in ($sqlLine -split ';\s*')) {
    if ($part -match '^reads\s+(.*)$') {
      $result.reads = @($matches[1] -split ',\s*' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    } elseif ($part -match '^writes\s+(.*)$') {
      $result.writes = @($matches[1] -split ',\s*' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    }
  }
  return $result
}

# Order-insensitive EXACT-SET comparison: $actual (an array, possibly $null)
# must hold exactly $expected, no more, no fewer. $false when $actual is $null
# (the side was absent) even if $expected is empty -- callers only call this
# when they expect the side to be PRESENT.
function Test-SetEqual([string[]]$actual, [string[]]$expected) {
  if ($null -eq $actual) { return $false }
  $a = ($actual | Sort-Object) -join '|'
  $e = ($expected | Sort-Object) -join '|'
  return $a -eq $e
}

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
  Check 'document --apply #1 exits 0' ($LASTEXITCODE -eq 0)

  $lines = [IO.File]::ReadAllLines($target)

  # --- SyncOne: the task brief's own literal example -----------------------
  $syncBlock = Get-DocBlockAbove $lines '^\s*procedure SyncOne;\s*$'
  Check 'SyncOne has a managed block (AUTO_BEGIN)' (($null -ne $syncBlock) -and ($syncBlock -match '<!-- drag-lint:auto BEGIN -->'))
  $syncSql = Parse-SqlLine (Get-SqlLine $syncBlock)
  Check 'SyncOne SQL reads is exactly {OPTRLIST}'  (Test-SetEqual $syncSql.reads  @('OPTRLIST'))
  Check 'SyncOne SQL writes is exactly {PDF_SCAN}' (Test-SetEqual $syncSql.writes @('PDF_SCAN'))

  # --- RunJoinConcat: 3-literal concatenation + JOIN, both bare-aliased -----
  $joinBlock = Get-DocBlockAbove $lines '^\s*procedure RunJoinConcat;\s*$'
  Check 'RunJoinConcat has a managed block (AUTO_BEGIN)' (($null -ne $joinBlock) -and ($joinBlock -match '<!-- drag-lint:auto BEGIN -->'))
  $joinSql = Parse-SqlLine (Get-SqlLine $joinBlock)
  Check 'RunJoinConcat SQL reads is exactly {OPTRLIST, SCANQUEUE}' (Test-SetEqual $joinSql.reads @('OPTRLIST','SCANQUEUE'))
  Check 'RunJoinConcat SQL has NO writes side' ($null -eq $joinSql.writes)

  # --- MultiFromList: 'FROM A, B' comma-list --------------------------------
  $multiBlock = Get-DocBlockAbove $lines '^\s*procedure MultiFromList;\s*$'
  Check 'MultiFromList has a managed block (AUTO_BEGIN)' (($null -ne $multiBlock) -and ($multiBlock -match '<!-- drag-lint:auto BEGIN -->'))
  $multiSql = Parse-SqlLine (Get-SqlLine $multiBlock)
  Check 'MultiFromList SQL reads is exactly {CLIENT, VENDOR}' (Test-SetEqual $multiSql.reads @('CLIENT','VENDOR'))
  Check 'MultiFromList SQL has NO writes side' ($null -eq $multiSql.writes)

  # --- InsertAndDelete: INSERT INTO + DELETE FROM, no reads side ------------
  $insDelBlock = Get-DocBlockAbove $lines '^\s*procedure InsertAndDelete;\s*$'
  Check 'InsertAndDelete has a managed block (AUTO_BEGIN)' (($null -ne $insDelBlock) -and ($insDelBlock -match '<!-- drag-lint:auto BEGIN -->'))
  $insDelSql = Parse-SqlLine (Get-SqlLine $insDelBlock)
  Check 'InsertAndDelete SQL writes is exactly {SCAN_LOG, TEMP_ROWS}' (Test-SetEqual $insDelSql.writes @('SCAN_LOG','TEMP_ROWS'))
  Check 'InsertAndDelete SQL has NO reads side' ($null -eq $insDelSql.reads)

  # --- DynamicQuery: dynamic concat (a field, not a literal) -> dropped ----
  # This method DOES get a managed block (Reads: FTableName, an unrelated
  # fact), but must carry NO 'SQL:' line at all -- proves the dynamic-skip
  # discipline independently of whether the routine has a block for some
  # OTHER reason.
  $dynBlock = Get-DocBlockAbove $lines '^\s*procedure DynamicQuery;\s*$'
  Check 'DynamicQuery has a managed block (AUTO_BEGIN, via the unrelated Reads fact)' (($null -ne $dynBlock) -and ($dynBlock -match '<!-- drag-lint:auto BEGIN -->'))
  Check 'DynamicQuery has NO SQL: line (dynamic concat -- non-literal operand -- dropped, never guessed)' ($null -eq (Get-SqlLine $dynBlock))

  # --- NoSql: zero facts of any kind -> no managed block at all ------------
  # Get-DocBlockAbove returns '' (NOT $null) when the declaration is found
  # but zero '///'-prefixed lines precede it (vs. $null when the declaration
  # itself is not found at all) -- both mean "no doc comment here", so both
  # are accepted.
  $noSqlBlock = Get-DocBlockAbove $lines '^\s*procedure NoSql;\s*$'
  Check 'NoSql has NO managed block at all (no fact fires)' (($null -eq $noSqlBlock) -or ($noSqlBlock -eq ''))
  Check 'NoSql has NO SQL: line (redundant with the no-block check above, kept explicit per the task brief)' ($null -eq (Get-SqlLine $noSqlBlock))

  # --- Idempotency: reindex (facts are index-time) + re-apply -> no change ---
  $before = [IO.File]::ReadAllBytes($target)
  & $exePath index $scratch --db $db 2>$null | Out-Null
  & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
  $after = [IO.File]::ReadAllBytes($target)
  Check 'idempotent: file byte-identical after reindex + 2nd apply' ([System.Linq.Enumerable]::SequenceEqual([byte[]]$before,[byte[]]$after))
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
