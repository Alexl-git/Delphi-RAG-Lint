<#
  run_doc_p2_dfm.ps1 -- Auto-Document Phase 2, Task 6: DFM event-wiring fact
  (which control/event a published method is wired to as a handler, e.g.
  Button1Click -> Button1.OnClick, mined from the paired .dfm).

  Uses fixtures\docp2\dfmwire\uForm.pas (TForm1: Button1: TButton;
  procedure Button1Click(Sender: TObject); procedure Unwired(Sender: TObject);)
  paired with uForm.dfm (object Form1: TForm1 ... object Button1: TButton ...
  OnClick = Button1Click end end):
    * Button1Click -- wired to Button1's OnClick in the .dfm. Expect the
      managed block to carry 'Handles: Button1.OnClick'.
    * Unwired -- NOT referenced by any On*-property in the .dfm at all.
      Expect NO 'Handles:' line (absence over a wrong/guessed fact) -- and,
      since this fixture's Unwired has no OTHER fact either (empty body,
      nothing calls it), no managed block at all under the facts-only
      default (Stubs=False).

  Drives `index` -> `document --unit --apply` (Stubs=False, the default: a
  decl with NO prior doc-comment and NO facts is skipped entirely -- see
  DRagLint.Doc.Batch's facts-only filter).

  DFM event wiring is INDEX-TIME (unlike Task 5's Covered-by, which is
  computed lazily at render time): symbol_facts.dfm_event is populated by
  TSymbolFactsAnalyzer.Analyze, so a fresh reindex after the build is
  required before `document` reads it back -- see the idempotency block at
  the end, which reindexes then re-applies and re-checks the 'Handles:'
  segment specifically (NOT a whole-file byte comparison -- see below).

  KNOWN PRE-EXISTING/ORTHOGONAL QUIRK (confirmed empirically, out of Task 6's
  scope to fix -- see the task report's "concerns" section): the .dfm's
  `OnClick = Button1Click` line is ALSO indexed as an 'event-binding'
  reference whose name_text is 'Button1Click'. DRagLint.Storage.SQLite's
  FindUnresolvedNameCallers (the query behind the PRE-EXISTING 'Called from:'
  fact, v14/D5) matches ANY refs row by name_text with no kind filter, so
  that same .dfm reference is ALSO picked up as an (unverified) "caller" of
  Button1Click -- a spurious 'Called from: Button1Click caller (uForm.dfm)'
  line that has nothing to do with Task 6. (Register K17: that example carried
  a trailing ' ?' until 2026-07-29. It is pre-T4 text. T4 suppresses the marker
  on a UNIFORM list, and this list has one entry, so it is uniform by
  construction and renders plain. The quirk itself is unchanged; only the
  rendering of it is.) That line's presence/absence
  across repeat runs is NOT stable once a prior doc-comment already exists
  (a separate, unresolved determinism gap in that pre-existing fact), so a
  whole-file byte-identity idempotency check would intermittently fail for a
  reason entirely outside the DFM-event-wiring fact this task owns. This
  test therefore asserts idempotency of the 'Handles:' segment specifically
  (which IS, and must be, stable: DfmEvent is a pure function of (ASym.Name,
  the paired .dfm's own content), recomputed identically every reindex).

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

$exePath = (Resolve-Path $Exe).Path
$fixtureDir = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp2\dfmwire')).Path

$scratch = Join-Path C:\TEMP 'draglint_docp2dfm'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$targetPas = Join-Path $scratch 'uForm.pas'
$targetDfm = Join-Path $scratch 'uForm.dfm'
$db        = Join-Path $scratch 'docp2dfm.sqlite'
Copy-Item (Join-Path $fixtureDir 'uForm.pas') $targetPas -Force
Copy-Item (Join-Path $fixtureDir 'uForm.dfm') $targetDfm -Force

# Same scan-upward idiom as run_doc_p2_fields.ps1's Get-DocBlockAbove: returns
# the contiguous run of ///-prefixed lines immediately above the FIRST line
# matching $declPattern. $null if the declaration is not found.
function Get-DocBlockAbove([string[]]$lines, [string]$declPattern) {
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $declPattern) { $idx = $i; break } }
  if ($idx -lt 0) { return $null }
  $blockLines = @()
  $j = $idx - 1
  while ($j -ge 0 -and $lines[$j].TrimStart() -match '^///') { $blockLines = ,($lines[$j]) + $blockLines; $j-- }
  return ($blockLines -join "`n")
}

# Extracts the 'Handles: ...' line's value from $block (to end of line), or
# $null if $block has no such line at all -- distinguishes "no managed block"
# / "no Handles fact" from "Handles present but somehow blank" (the latter
# never legitimately happens per RenderFactsBlock's omit-when-empty rule).
function Get-HandlesValue([string]$block) {
  if ($null -eq $block) { return $null }
  $m = [regex]::Match($block, 'Handles: ([^\r\n]*)')
  if (-not $m.Success) { return $null }
  return $m.Groups[1].Value.Trim()
}

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  & $exePath document --unit $targetPas --db $db --apply 2>$null | Out-Null
  Check 'document --apply #1 exits 0' ($LASTEXITCODE -eq 0)

  $lines = [IO.File]::ReadAllLines($targetPas)

  # --- Button1Click: wired in the .dfm -> Handles: Button1.OnClick ----------
  $clickBlock = Get-DocBlockAbove $lines '^\s*procedure Button1Click\(Sender: TObject\);\s*$'
  Check 'Button1Click has a managed block (AUTO_BEGIN)' (($null -ne $clickBlock) -and ($clickBlock -match '<!-- drag-lint:auto BEGIN -->'))
  Check 'Button1Click Handles is exactly Button1.OnClick' ((Get-HandlesValue $clickBlock) -eq 'Button1.OnClick')

  # --- Unwired: no .dfm reference -> NO Handles: line at all ----------------
  $unwiredBlock = Get-DocBlockAbove $lines '^\s*procedure Unwired\(Sender: TObject\);\s*$'
  Check 'Unwired has NO Handles fact (absence over a guessed fact)' (($null -eq $unwiredBlock) -or ($unwiredBlock -notmatch 'Handles:'))

  # --- Idempotency: reindex (facts are index-time) + re-apply -> the DFM
  # event-wiring fact this task owns is stable. NOT a whole-file byte
  # comparison -- see this script's header comment for the pre-existing,
  # orthogonal 'Called from:' quirk that would otherwise make a whole-file
  # comparison flaky for a reason outside Task 6's scope.
  $beforeHandles = Get-HandlesValue $clickBlock
  & $exePath index $scratch --db $db 2>$null | Out-Null
  & $exePath document --unit $targetPas --db $db --apply 2>$null | Out-Null
  $linesAfter = [IO.File]::ReadAllLines($targetPas)
  $clickBlockAfter = Get-DocBlockAbove $linesAfter '^\s*procedure Button1Click\(Sender: TObject\);\s*$'
  $afterHandles = Get-HandlesValue $clickBlockAfter
  Check 'idempotent: Handles value unchanged after reindex + 2nd apply' (($null -ne $afterHandles) -and ($beforeHandles -eq $afterHandles))
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
