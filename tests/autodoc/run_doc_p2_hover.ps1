<#
  run_doc_p2_hover.ps1 -- Auto-Document Phase 2, Task 9: hover surfaces the
  analysis facts + the doc/hover CONSISTENCY LOCK.

  Uses fixtures\docp2\p2hover.pas: TBusy.Complex combines TWO Phase-2 facts
  in ONE routine (see that file's own header comment):
    * Cyclomatic complexity >= docs.complexity_min (10) -- the same
      if/ifElse/for/case/and/or/while mix as fixtures\docp2\complexity.pas's
      ComplexFn, reused here as a class method.
    * Reads AND writes FCount (an own-class field) in the SAME pair of
      statements ('FCount := FCount + Result; Result := FCount;') -- mirrors
      fixtures\docp2\fields.pas's AddN shape.

  Drives `index` -> `hover --qname ... --format md` (BEFORE `document`, to
  prove the Phase-2 facts are INDEX-TIME and show up in hover independent of
  whether the symbol has a doc-comment at all) -- asserts the hover markdown
  carries BOTH 'Complexity: N (cyclomatic), M lines' (N >= 10) and
  'Reads: FCount   Writes: FCount'.

  Then drives `document --unit --apply` and re-hovers. THE CONSISTENCY LOCK:
  extracts the same two fact lines from the managed doc block AND from the
  (post-document) hover markdown and asserts they are byte-identical --
  proving both surfaces render through the SAME shared
  TDocRegions.FormatPhase2FactLines helper from the SAME TDocFactsBuilder.
  Build result, so they can never show different facts for one symbol.

  Phase 3 T1 regression (hover marker leak): also documents p2hover.Echo (a
  deliberately FACTS-FREE free function -- see its own header comment in the
  fixture) via a targeted `document --qname` call, then hovers it in all 3
  formats (plain/md/json) and asserts the literal AUTO_MARK ownership token
  ('drag-lint:auto') never appears in any of them -- before the T1 hover fix,
  a managed <summary>/<param>/<returns> carrying ONLY the marker rendered the
  raw HTML comment to a human instead of the pre-marker empty string. Echo is
  used (not TBusy.Complex) specifically because it has no facts, so its hover
  output carries no <!-- drag-lint:auto BEGIN/END --> facts-fence either --
  the ONLY drag-lint:auto text that could appear comes from the tags this
  fix targets, keeping the "never appears" assertion airtight.

  v(ADP3 T3) update: omit-when-empty means Echo's generated comment now
  carries ONLY a managed <returns> (AValue has no hand-written description,
  so <param name="AValue"> is never emitted; there is no harvested summary
  either, so <summary> is never emitted). The param-row assertions below are
  rewritten accordingly: plain hover has NO param-row fallback (nothing to
  render at all), while markdown falls back to a SIGNATURE-derived row
  (name + type, e.g. "- `AValue` : const Integer") when there is no <param>
  tag to read -- still carrying no marker, just a different shape than the
  pre-T3 "empty after stripping" case.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp2\p2hover.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_docp2hover'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'p2hover.pas'
$db     = Join-Path $scratch 'docp2hover.sqlite'
Copy-Item $fixture $target -Force

# Same scan-upward idiom run_doc_p2_fields.ps1/run_doc_p2_complexity.ps1 use:
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

# Extracts the "$label: <rest of that physical line>" text from $text, NOT
# anchored to line start -- so it matches equally whether $label appears
# right after a '/// ' doc-comment prefix + source indentation (the managed
# doc block, read from the .pas file) or after a '- ' markdown bullet (the
# hover popup's own "Analysis facts" list). $null when $label's line is not
# present at all (distinguishes "fact absent" from "fact present but the
# line differs").
function Get-FactLine([string]$text, [string]$label) {
  if ($null -eq $text) { return $null }
  $m = [regex]::Match($text, "(?m)$([regex]::Escape($label)): [^\r\n]*")
  if (-not $m.Success) { return $null }
  return $m.Value.TrimEnd()
}

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  # --- hover BEFORE `document` -- proves Phase-2 facts are INDEX-TIME, not --
  # --- dependent on the symbol already having a doc-comment.               --
  $hoverMd1 = (& $exePath hover --qname p2hover.TBusy.Complex --db $db --format md 2>&1) -join "`n"
  Check 'hover (pre-document) exits 0' ($LASTEXITCODE -eq 0)

  $hoverComplexity1 = Get-FactLine $hoverMd1 'Complexity'
  Check 'hover (pre-document) shows a Complexity: line' ($null -ne $hoverComplexity1) $hoverMd1
  if ($null -ne $hoverComplexity1) {
    $m = [regex]::Match($hoverComplexity1, 'Complexity: (\d+) \(cyclomatic\), (\d+) lines')
    Check 'hover Complexity line has the "N (cyclomatic), M lines" shape' ($m.Success) $hoverComplexity1
    if ($m.Success) {
      Check 'hover Complexity N >= 10 (docs.complexity_min default)' ([int]$m.Groups[1].Value -ge 10) $hoverComplexity1
      Check 'hover Complexity M lines > 0' ([int]$m.Groups[2].Value -gt 0) $hoverComplexity1
    }
  }

  $hoverRW1 = Get-FactLine $hoverMd1 'Reads'
  Check 'hover (pre-document) shows a Reads: ... Writes: ... line' ($hoverRW1 -eq 'Reads: FCount   Writes: FCount') $hoverRW1

  # --- document --apply -- creates the managed block for TBusy.Complex -----
  & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
  Check 'document --apply exits 0' ($LASTEXITCODE -eq 0)

  $lines = [IO.File]::ReadAllLines($target)
  $docBlock = Get-DocBlockAbove $lines '^\s*function Complex\(A, B, C: Integer\): Integer;\s*$'
  Check 'TBusy.Complex has a managed block (AUTO_BEGIN)' (($null -ne $docBlock) -and ($docBlock -match '<!-- drag-lint:auto BEGIN -->'))

  $docComplexity = Get-FactLine $docBlock 'Complexity'
  Check 'doc block has a Complexity: line' ($null -ne $docComplexity) $docBlock
  $docRW = Get-FactLine $docBlock 'Reads'
  Check 'doc block Reads/Writes is exactly ''Reads: FCount   Writes: FCount''' ($docRW -eq 'Reads: FCount   Writes: FCount') $docRW

  # --- hover AFTER `document` -- re-hover so the consistency comparison ----
  # --- below is against a hover call made in the SAME state as the doc.    --
  $hoverMd2 = (& $exePath hover --qname p2hover.TBusy.Complex --db $db --format md 2>&1) -join "`n"
  Check 'hover (post-document) exits 0' ($LASTEXITCODE -eq 0)
  $hoverComplexity2 = Get-FactLine $hoverMd2 'Complexity'
  $hoverRW2          = Get-FactLine $hoverMd2 'Reads'

  # --- THE CONSISTENCY LOCK: doc block and hover md agree, byte-for-byte ---
  Check 'CONSISTENCY LOCK: Complexity line identical in doc block and hover md' (($null -ne $docComplexity) -and ($docComplexity -eq $hoverComplexity2)) "doc=[$docComplexity] hover=[$hoverComplexity2]"
  Check 'CONSISTENCY LOCK: Reads/Writes line identical in doc block and hover md' (($null -ne $docRW) -and ($docRW -eq $hoverRW2)) "doc=[$docRW] hover=[$hoverRW2]"

  # --- Phase 3 T1 regression: the AUTO_MARK ownership token must never reach --
  # --- a human via hover. Echo is deliberately FACTS-FREE (see its own      --
  # --- header comment in the fixture), so the --unit facts-only default     --
  # --- (Doc.Batch's HasManagedBlock filter) would SKIP creating a comment   --
  # --- for it -- document it with a TARGETED --qname call instead, which is --
  # --- not gated by that filter. Reindex FIRST: the --unit --apply above    --
  # --- already inserted Complex's managed comment (shifting every line      --
  # --- below it, including Echo's) without an intervening reindex, so the   --
  # --- store's symbol position for Echo is stale -- a --qname document call --
  # --- against a stale position is exactly the bug run_doc_idempotent.ps1's --
  # --- own header comment warns about. Reindex AGAIN afterward so hover     --
  # --- picks up Echo's own just-inserted comment at ITS new position.       --
  & $exePath index $scratch --db $db 2>$null | Out-Null
  & $exePath document --qname p2hover.Echo --db $db --apply 2>$null | Out-Null
  & $exePath index $scratch --db $db 2>$null | Out-Null
  $echoPlain = (& $exePath hover --qname p2hover.Echo --db $db 2>&1) -join "`n"
  Check 'Echo hover (plain) exits 0' ($LASTEXITCODE -eq 0)
  $echoMd   = (& $exePath hover --qname p2hover.Echo --db $db --format md   2>&1) -join "`n"
  Check 'Echo hover (md) exits 0' ($LASTEXITCODE -eq 0)
  $echoJson = (& $exePath hover --qname p2hover.Echo --db $db --format json 2>&1) -join "`n"
  Check 'Echo hover (json) exits 0' ($LASTEXITCODE -eq 0)

  # The literal ownership token must never leak into any of the 3 formats.
  Check 'T1: hover plain never leaks the AUTO_MARK ownership token' ($echoPlain -notmatch 'drag-lint:auto') $echoPlain
  Check 'T1: hover md never leaks the AUTO_MARK ownership token'    ($echoMd    -notmatch 'drag-lint:auto') $echoMd
  Check 'T1: hover json never leaks the AUTO_MARK ownership token'  ($echoJson  -notmatch 'drag-lint:auto') $echoJson

  # Positive checks: this must be a REAL assertion against real hover output
  # on a symbol with an engine-emitted marked tag -- not just an absence
  # check -- so also confirm the CLEANED (marker-stripped) content is there.
  Check 'T1: hover plain shows the cleaned Returns line' ($echoPlain -match 'Returns: Observed: AValue\.') $echoPlain
  Check 'T1: hover md shows the cleaned Returns line'    ($echoMd    -match '\*\*Returns:\*\* Observed: AValue\.') $echoMd
  Check 'T1: hover json summary is empty after stripping (was ONLY the marker)' ($echoJson -match '"summary":""') $echoJson
  # v(ADP3 T3) update: AValue has no hand-written description, so Echo's
  # generated comment carries NO <param name="AValue"> tag at all anymore
  # (omit-when-empty -- a fresh comment never carries a <param> skeleton).
  # Plain hover has no signature fallback for params (ADoc.ParamsJsonRaw = ''
  # -> nothing rendered), so there is no "AValue --" row at all. Markdown DOES
  # fall back to a signature-derived row when there is no <param> tag
  # (RenderSignatureParamsMarkdown), so it shows the param's NAME AND TYPE
  # instead -- still no marker leak (covered by the broad no-leak check above).
  Check 'T3: hover plain has NO param row at all (no <param> tag, no signature fallback)' `
    ($echoPlain -notmatch 'AValue --') $echoPlain
  Check 'T3: hover md falls back to the signature-derived param row (name + type, no marker)' `
    ($echoMd -match '(?m)^- `AValue` : const Integer\s*$') $echoMd

  # --- Idempotency-adjacent: reindex (facts are index-time) + re-hover -----
  # --- shows the SAME facts (no drift across a reindex with no source      --
  # --- change).                                                            --
  & $exePath index $scratch --db $db 2>$null | Out-Null
  $hoverMd3 = (& $exePath hover --qname p2hover.TBusy.Complex --db $db --format md 2>&1) -join "`n"
  Check 'reindex + re-hover: Complexity line unchanged' ((Get-FactLine $hoverMd3 'Complexity') -eq $hoverComplexity2)
  Check 'reindex + re-hover: Reads/Writes line unchanged' ((Get-FactLine $hoverMd3 'Reads') -eq $hoverRW2)

  # =========================================================================
  # v(ADP3 T14): THE PHASE 3 EXTENSION OF THE v(ADP2 T9) CONSISTENCY LOCK.
  #
  # All four Phase 3 facts render through the SAME shared
  # TDocRegions.FormatPhase2FactLines that the six Phase 2 lines do, so hover
  # gets them "for free" -- and "for free" is exactly the claim that needs a
  # test, because the freeness is a property of the call graph, not of the
  # language. If someone ever inlines the helper into RenderFactsBlock, or adds
  # a Phase 3 line to the doc path only, the doc block and the hover popup start
  # showing different facts for the same symbol and NOTHING else would notice.
  #
  # Mutates: is the fact under test (the plan section 7 asks for at least one of the four).
  # The comparison is on the fact line's TEXT, after stripping the doc block's
  # '/// ' prefix and hover's markdown bolding, so it survives cosmetic
  # differences in framing but not a difference in the fact itself.
  # =========================================================================
  $p3dir = Join-Path C:\TEMP 'draglint_docp2hover_p3'
  if (Test-Path $p3dir) { Remove-Item $p3dir -Recurse -Force }
  New-Item -ItemType Directory -Path $p3dir | Out-Null
  $p3src = Join-Path $p3dir 'mutates.pas'
  $p3db  = Join-Path $p3dir 'p3.sqlite'
  Copy-Item (Join-Path $PSScriptRoot 'fixtures\docp3\mutates.pas') $p3src -Force

  & $exePath index $p3dir --db $p3db 2>$null | Out-Null
  & $exePath document --unit $p3src --db $p3db --apply 2>$null | Out-Null
  & $exePath index $p3dir --db $p3db 2>$null | Out-Null

  # The doc side: the Mutates line out of the emitted block, /// stripped.
  $docMut = ''
  foreach ($l in [IO.File]::ReadAllLines($p3src)) {
    $t = ($l -replace '^\s*///\s?','').Trim()
    if ($t -match '^Mutates: (.*)$') { $docMut = $Matches[1].Trim(); break }
  }
  # The hover side: the same line out of the markdown render, bolding stripped.
  $p3Hover = (& $exePath hover --qname mutates.FillBoth --db $p3db --format md 2>&1) -join "`n"
  $hovMut  = ''
  $hm = [regex]::Match($p3Hover, '(?m)^\W*\*{0,2}Mutates:\*{0,2}\s*(.+?)\s*$')
  if ($hm.Success) { $hovMut = $hm.Groups[1].Value.Trim() }

  Check 'CONSISTENCY (ADP3): the doc block carries a Mutates: line' ($docMut -ne '') "doc=[$docMut]"
  Check 'CONSISTENCY (ADP3): hover carries a Mutates: line'         ($hovMut -ne '') $p3Hover
  Check 'CONSISTENCY (ADP3): doc and hover show the SAME Mutates: text' `
    (($docMut -ne '') -and ($docMut -eq $hovMut)) "doc=[$docMut] hover=[$hovMut]"
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
