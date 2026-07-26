<#
  run_doc_p3_provenance.ps1 -- Auto-Document Phase 3, Task 1: uniform
  <!-- drag-lint:auto --> provenance marker; delete the Observed: content sniff.

  Fixture fixtures\docp3\provenance.pas:
    * Marked(const AText: string): Integer -- UNDOCUMENTED. A fresh managed
      comment is generated; its <param name="AText"> and <returns> tags must
      each carry the marker as the FIRST characters of their text content
      (immediately after the opening tag), exactly once.
    * HandWritten: Integer -- ALREADY carries a hand-written comment whose
      <returns> text happens to start with the word "Observed:" (prose, not
      engine output). Pre-T1, StartsText('Observed:', ...) misclassified this
      as MANAGED content and silently overwrote it on every `document --apply`.
      Post-T1, ownership is marker-keyed only: this tag carries no AUTO_MARK,
      so it must survive byte-identical.

  Drives `index` -> `document --unit --apply` and asserts:
    1. Marked's <param name="AText"> line carries exactly one
       <!-- drag-lint:auto --> immediately after the opening tag.
    2. Marked's <returns> line carries exactly one <!-- drag-lint:auto -->
       immediately after the opening tag.
    3. HandWritten's <summary> and <returns> lines are byte-identical to the
       fixture (no marker added; the hand-written Observed:-prefixed prose is
       neither adopted as managed nor rewritten; that same prose string is not
       duplicated into a separate Returns: fact line -- the real mined return
       case, "1", is a legitimately DIFFERENT fact and may appear on its own
       line, same as the existing Doubler precedent in run_doc_returns_merge).
    4. Idempotency: reindex + a second --apply leaves the file byte-identical.
    5. Every emitted /// line is 7-bit ASCII.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\provenance.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_docp3provenance'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'provenance.pas'
$db     = Join-Path $scratch 'docp3provenance.sqlite'
Copy-Item $fixture $target -Force

# Returns the contiguous run of ///-prefixed lines immediately above the FIRST
# line matching $declPattern (the interface declaration -- always the earlier
# of the two textually-identical free-function decl/impl signature lines,
# since interface precedes implementation in a well-formed unit). '' if the
# declaration is not found.
function Get-DocBlockAbove([string[]]$lines, [string]$declPattern) {
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $declPattern) { $idx = $i; break } }
  if ($idx -lt 0) { return $null }
  $blockLines = @()
  $j = $idx - 1
  while ($j -ge 0 -and $lines[$j].TrimStart() -match '^///') { $blockLines = ,($lines[$j]) + $blockLines; $j-- }
  return ($blockLines -join "`n")
}

$MARK = '<!-- drag-lint:auto -->'

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
  Check 'document --apply #1 exits 0' ($LASTEXITCODE -eq 0)

  $lines = [IO.File]::ReadAllLines($target)

  # --- Marked: fresh managed comment; param + returns each carry ONE marker ---
  $markedBlock = Get-DocBlockAbove $lines '^function Marked\(const AText: string\): Integer;'
  Check 'Marked decl found' ($null -ne $markedBlock)

  $paramLine = $lines | Where-Object { $_ -match [regex]::Escape('<param name="AText">') } | Select-Object -First 1
  Check 'Marked <param name="AText"> line found' ($null -ne $paramLine)
  if ($null -ne $paramLine) {
    $paramMarkCount = ([regex]::Matches($paramLine, [regex]::Escape($MARK))).Count
    Check 'Marked <param name="AText"> carries exactly one marker' ($paramMarkCount -eq 1)
    Check 'Marked <param name="AText"> marker sits immediately after the opening tag' `
      ($paramLine -match [regex]::Escape('<param name="AText">' + $MARK))
  }

  $returnsLineMarked = $null
  if ($null -ne $markedBlock) {
    $returnsLineMarked = ($markedBlock -split "`n") | Where-Object { $_ -match '<returns>' } | Select-Object -First 1
  }
  Check 'Marked <returns> line found' ($null -ne $returnsLineMarked)
  if ($null -ne $returnsLineMarked) {
    $returnsMarkCount = ([regex]::Matches($returnsLineMarked, [regex]::Escape($MARK))).Count
    Check 'Marked <returns> carries exactly one marker' ($returnsMarkCount -eq 1)
    Check 'Marked <returns> marker sits immediately after the opening tag' `
      ($returnsLineMarked -match [regex]::Escape('<returns>' + $MARK))
  }

  # --- HandWritten: hand-written prose that merely starts with "Observed:" ---
  $handBlock = Get-DocBlockAbove $lines '^function HandWritten: Integer;'
  Check 'HandWritten decl found' ($null -ne $handBlock)

  Check 'HandWritten <summary> byte-identical to fixture (no marker added)' `
    (($lines | Where-Object { $_ -eq '/// <summary>Hand-written and must survive verbatim.</summary>' }).Count -eq 1)
  Check 'HandWritten <returns> byte-identical to fixture (NOT adopted/rewritten by the deleted sniff)' `
    (($lines | Where-Object { $_ -eq '/// <returns>Observed: this is hand-written prose that merely starts with the word.</returns>' }).Count -eq 1)
  Check 'HandWritten doc block carries no marker anywhere' `
    ($null -eq $handBlock -or (-not ($handBlock -match [regex]::Escape($MARK))))
  Check 'HandWritten hand-written prose is not duplicated into a Returns: fact line' `
    ($null -eq $handBlock -or (-not ($handBlock -match 'Returns:\s*Observed: this is hand-written')))

  # --- Idempotency: reindex (facts are index-time) + re-apply -> no change ---
  $before = [IO.File]::ReadAllBytes($target)
  & $exePath index $scratch --db $db 2>$null | Out-Null
  & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
  $after = [IO.File]::ReadAllBytes($target)
  Check 'idempotent: file byte-identical after reindex + 2nd apply' ([System.Linq.Enumerable]::SequenceEqual([byte[]]$before,[byte[]]$after))

  # --- Every emitted /// line is 7-bit ASCII ---
  $docLines = [IO.File]::ReadAllLines($target) | Where-Object { $_.TrimStart() -match '^///' }
  $nonAscii = $docLines | Where-Object { $_ -match '[^\x00-\x7F]' }
  Check 'every /// line is 7-bit ASCII' ($nonAscii.Count -eq 0)
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
