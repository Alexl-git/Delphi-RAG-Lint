<#
  run_doc_adjacent_decls.ps1 -- TDD lock for the FindDocRegionAbove
  intervening-declaration bug (adp2-docregion-fix).

  FindDocRegionAbove attributed a doc-comment region to a symbol by LINE
  DISTANCE ONLY (EndLine in [SymStartLine - 1 - AllowGap, SymStartLine - 1]),
  with no check for a declaration sitting BETWEEN the region and the symbol.
  So for two back-to-back declarations with NO blank line between them, where
  only the FIRST (A) is documented, the SAME doc region wrongly also matched
  the SECOND (B): BuildForSymbol treated A's block as B's *existing* doc and
  emitted an edit that rewrote/duplicated it -- corrupting A's comment and
  stamping A's prose onto B.

  Fixture fixtures\docbug\adjacent_decls.pas: ProcA (documented, "Doc for
  A.") and ProcB declared back-to-back with NO blank line between them; ProcC
  is separately documented ("Doc for C.") with a normal 1-blank-line gap (the
  LEGIT case that must keep working). ProcC's body calls ProcA and ProcB so
  both pick up a real "Called from:" fact -- this is what forces an actual
  edit (with no facts, A's and B's merged text is byte-identical to what is
  already on disk at that spot, and the bug produces zero visible edits).

  Empirically, at HEAD (ac3b661, pre-fix) `document --unit --apply` reports
  "3/3 decl(s) documented, 6 edit(s) applied" and the resulting file has
  ProcA's own interface forward-declaration DELETED entirely (eaten by a
  double-delete over the same line range: A's edit and B's wrongly-generated
  edit both target A's original doc-comment lines) and TWO back-to-back
  copies of "Doc for A." + the facts block stacked above `procedure ProcB;`.

  Asserts, after ONE `document --unit --apply`:
    * ProcA's interface declaration still exists (not eaten by the collision)
      and "Doc for A." sits directly above it, exactly once in the file.
    * ProcB's interface declaration still exists; its own doc block (if any)
      does NOT contain "Doc for A." (no cross-contamination).
    * ProcC's interface declaration still has "Doc for C." directly above it
      (the legit 1-blank-line-gap case keeps working).
    * `procedure ProcA;` appears exactly twice in the file (interface decl +
      implementation restatement) -- a direct check against the
      declaration-eating failure mode observed at HEAD.
    * IDEMPOTENT: a second index + `document --unit --apply` leaves the file
      byte-identical to the first apply's output.

  Run from a NEUTRAL CWD (C:\TEMP).
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docbug\adjacent_decls.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_docadjacent'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'adjacent_decls.pas'
$db     = Join-Path $scratch 'docadjacent.sqlite'
Copy-Item $fixture $target -Force

# Index of the 'implementation' line -- used to find the INTERFACE-section
# occurrence of a declaration specifically (the free routine's forward decl,
# textually identical to its implementation restatement further down).
function Get-ImplLineIndex([string[]]$lines) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*implementation\s*$') { return $i } }
  return $lines.Count
}

# First 0-based line index BEFORE $implIdx matching $declPattern, or -1.
function Get-InterfaceDeclIndex([string[]]$lines, [int]$implIdx, [string]$declPattern) {
  for ($i = 0; $i -lt $implIdx; $i++) { if ($lines[$i] -match $declPattern) { return $i } }
  return -1
}

# Contiguous run of ///-prefixed lines above 0-based $declIdx, tolerating AT
# MOST one blank line immediately above the declaration (mirrors the
# product's own AAllowGap=1 default -- ProcC's legit gap case must still find
# its block). $null when $declIdx < 0 or no /// line is found within that
# window.
function Get-DocBlockAbove([string[]]$lines, [int]$declIdx) {
  if ($declIdx -lt 0) { return $null }
  $j = $declIdx - 1
  if ($j -ge 0 -and $lines[$j].Trim() -eq '') { $j-- }
  $blockLines = @()
  while ($j -ge 0 -and $lines[$j].TrimStart() -match '^///') { $blockLines = ,($lines[$j]) + $blockLines; $j-- }
  if ($blockLines.Count -eq 0) { return $null }
  return ($blockLines -join "`n")
}

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
  Check 'document --apply #1 exits 0' ($LASTEXITCODE -eq 0)

  $lines = [IO.File]::ReadAllLines($target)
  $text  = [IO.File]::ReadAllText($target)
  $implIdx = Get-ImplLineIndex $lines

  $aIdx = Get-InterfaceDeclIndex $lines $implIdx '^\s*procedure ProcA;\s*$'
  $bIdx = Get-InterfaceDeclIndex $lines $implIdx '^\s*procedure ProcB;\s*$'
  $cIdx = Get-InterfaceDeclIndex $lines $implIdx '^\s*procedure ProcC;\s*$'

  Check 'ProcA interface decl still present (not eaten by the collision)' ($aIdx -ge 0)
  Check 'ProcB interface decl still present' ($bIdx -ge 0)
  Check 'ProcC interface decl still present' ($cIdx -ge 0)

  $aBlock = Get-DocBlockAbove $lines $aIdx
  $bBlock = Get-DocBlockAbove $lines $bIdx
  $cBlock = Get-DocBlockAbove $lines $cIdx

  Check 'A: doc block present directly above ProcA' ($null -ne $aBlock)
  if ($null -ne $aBlock) { Check 'A: doc carries "Doc for A." summary' ($aBlock.Contains('Doc for A.')) }

  Check 'B: doc block (if any) does NOT carry "Doc for A." (no cross-contamination)' `
    ($null -eq $bBlock -or (-not $bBlock.Contains('Doc for A.')))

  Check 'C: doc block present directly above ProcC (legit 1-blank-line gap)' ($null -ne $cBlock)
  if ($null -ne $cBlock) { Check 'C: doc carries "Doc for C." summary' ($cBlock.Contains('Doc for C.')) }

  # No duplicate of A's hand-written summary anywhere in the file.
  $countA = ([regex]::Matches($text, [regex]::Escape('Doc for A.'))).Count
  Check 'exactly ONE occurrence of "Doc for A." in the whole file (no duplication)' ($countA -eq 1)

  # No duplicate of C's hand-written summary either.
  $countC = ([regex]::Matches($text, [regex]::Escape('Doc for C.'))).Count
  Check 'exactly ONE occurrence of "Doc for C." in the whole file' ($countC -eq 1)

  # Direct check against the declaration-eating failure mode seen at HEAD:
  # 'procedure ProcA;' must appear exactly twice (interface decl + impl
  # restatement) -- not once (interface decl eaten by the double-delete).
  $declCountA = ([regex]::Matches($text, '(?m)^\s*procedure ProcA;\s*$')).Count
  Check "'procedure ProcA;' appears exactly twice (interface + impl, not eaten)" ($declCountA -eq 2)

  # --- Idempotency: reindex (facts are index-time) + re-apply -> no change ---
  $before = [IO.File]::ReadAllBytes($target)
  & $exePath index $scratch --db $db 2>$null | Out-Null
  & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
  $after = [IO.File]::ReadAllBytes($target)
  Check 'idempotent: file byte-identical after reindex + 2nd apply' ([System.Linq.Enumerable]::SequenceEqual([byte[]]$before,[byte[]]$after))
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
