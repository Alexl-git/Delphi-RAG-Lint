<#
  run_missing_doc_fix.ps1 -- missing-doc "Fix it" (ADF Task 11c).

  missing-doc is FIXABLE but SINGLE-FIX-ONLY: a single targeted finding
  (lint-all --fix --fix-line <L> --fix-rule missing-doc) inserts the same
  DocInsight comment `document --qname` produces (a managed block); the blanket
  batch (lint-all --fix, no narrowing) EXCLUDES it (so it never injects TODO
  stubs project-wide).

  Fixture: fixtures\missingdocfix\missfix.pas
    Undocumented(Value: Integer): Integer  -- line 16, public, NO doc, has a
        param + a caller (CallsIt) -> the missing-doc finding whose Fix-it
        inserts a document-qname comment (<returns> from the mined
        `Result := Value + 1` case, plus the Called-from facts block).
        v(ADP3 T3) omit-when-empty: NO <summary> and NO <param name="Value">
        are emitted -- there is no hand-written or harvested description for
        either, and a blank tag is worse than none.
    CallsIt: Integer                       -- public, NO doc, calls Undocumented
        (Called-from source). Also a missing-doc finding, never targeted.
  No documented decl -> nothing for doc-drift to touch, so the blanket-batch
  check can assert byte-for-byte no change.

  missing-doc + doc-drift are store-backed (only run on lint-all/lint-project),
  and ship OFF by default (ADF Task 11b) -> enabled here via --config.

  Part A -- single-fix WORKS: lint-all --fix --fix-line 16 --fix-rule missing-doc
    --apply INSERTS a /// DocInsight comment with a managed block on the
    Undocumented decl (matching document --qname output -- post-T3 that is
    <returns> + the facts block, and deliberately no <summary>/<param>).
  Part B -- IDEMPOTENT: re-index + a 2nd single-fix finds no missing-doc (the
    decl now has a doc) -> no-op.
  Part C -- batch EXCLUDES it: on a fresh copy, lint-all --fix --apply (blanket
    batch, missing-doc enabled) does NOT insert a doc-comment for the missing-doc
    case -- the file's Undocumented decl is UNCHANGED (single-fix-only excluded).
  Part D -- rules --json reports missing-doc fixable=true.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\missingdocfix\missfix.pas')).Path
$L       = 16   # the Undocumented decl line in the fixture

# ---- Part A + B: single-fix (own scratch) ---------------------------------
$scratch = Join-Path C:\TEMP 'draglint_missdocfix_single'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target  = Join-Path $scratch 'missfix.pas'
$db      = Join-Path $scratch 'missfix.sqlite'
Copy-Item $fixture $target -Force

$cfg = Join-Path $scratch 'missfix.config.json'
'{ "enabled": ["missing-doc"] }' | Set-Content -Path $cfg -Encoding ascii -NoNewline

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null

  # Sanity: a missing-doc finding is reported on the Undocumented line (15).
  $rawL = (& $exePath lint-all --db $db --config $cfg --json 2>$null) -join "`n"
  $aS = $rawL.IndexOf('['); $aE = $rawL.LastIndexOf(']')
  $findings = @()
  if ($aS -ge 0 -and $aE -gt $aS) { $findings = @(ConvertFrom-Json $rawL.Substring($aS, $aE - $aS + 1)) }
  $md = @($findings | Where-Object { $_.rule -eq 'missing-doc' -and $_.start_line -eq $L })
  Check 'A0 missing-doc finding present on the Undocumented line (16)' ($md.Count -ge 1)

  # --- Part A: single-fix INSERTS the document-qname comment ---
  # ADF Task 13: missing-doc ships OFF by default, so --fix must opt it in via
  # --config (the same "enabled":["missing-doc"] used for the sanity lint above) --
  # otherwise ShouldKeep drops the finding before the --fix block builds edits.
  # --fix-rule NARROWS the surviving set; it does not re-enable a disabled rule.
  & $exePath lint-all --db $db --config $cfg --fix --fix-line $L --fix-rule missing-doc --apply --no-backup 2>$null | Out-Null
  $txt = [IO.File]::ReadAllText($target)
  # A1 = something was inserted AT ALL (safe whole-file: the fixture's own
  # header uses '//', it carries no '///' line of its own).
  Check 'A1 inserted a /// DocInsight comment'          ($txt -match '(?m)^\s*///\s')
  # A7 = ...and it landed ABOVE the decl (whose function line moved down).
  # Locate the decl, then take the contiguous run of ///-prefixed lines
  # immediately above it -- the same scan-upward idiom
  # tests\autodoc\run_doc_p3_emptytags.ps1 uses. Every CONTENT assertion runs
  # against that block, NOT the whole file: the fixture's own // header quotes
  # '<param name="Value">' as prose, so a whole-file regex would match the
  # fixture instead of the engine's output (it silently did).
  $lines = [IO.File]::ReadAllLines($target)
  $declIx = -1
  for ($i=0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match 'function Undocumented\(Value: Integer\): Integer;' -and $lines[$i] -notmatch '///') { $declIx = $i; break } }
  Check 'A6 the Undocumented decl still exists after the fix' ($declIx -ge 1)
  $block = ''
  if ($declIx -ge 1) {
    $bl = @(); $j = $declIx - 1
    while ($j -ge 0 -and $lines[$j].TrimStart() -match '^///') { $bl = ,($lines[$j]) + $bl; $j-- }
    $block = ($bl -join "`n")
  }
  Check 'A7 a /// comment precedes the Undocumented decl' ($block -match '(?m)^\s*///\s')
  # v(ADP3 T3) omit-when-empty: Undocumented has no hand-written or harvested
  # summary and no hand-written description for `Value`, so the inserted comment
  # carries NEITHER <summary> NOR <param name="Value"> -- see
  # tests\autodoc\run_doc_p3_emptytags.ps1, which locks that behaviour on the
  # `document` side. The fix-it path emits the same text `document --qname` does,
  # so A3 asserts the surviving shape, not the pre-T3 one.
  Check 'A2 inserted a managed drag-lint:auto block'   ($block.Contains('<!-- drag-lint:auto BEGIN -->') -and $block.Contains('<!-- drag-lint:auto END -->'))
  # A3 carries its own positive precondition. As a pure negative it would pass
  # vacuously on an EMPTY $block -- '' has no <summary> either -- so a comment
  # inserted in the wrong place, or not inserted at all, would satisfy a check
  # whose label claims to prove the emitted shape. A7 and A2 already catch that,
  # but a check must not depend on a sibling to be non-vacuous: read on its own,
  # A3 now says "a block exists AND it omits both tags".
  Check 'A3 block exists AND has NO <summary> and NO <param> tag (v(ADP3 T3): nothing to say -> omitted, never a blank stub)' `
    (($block -match '(?m)^\s*///\s') -and (-not ($block -match '<summary>')) -and (-not ($block -match '<param')))
  Check 'A4 comment carries <returns>'                 ($block -match '///\s*<returns>')
  Check 'A5 comment carries a Called-from fact (CallsIt)' ($block -match 'Called from:.*missfix\.CallsIt')

  # --- Part B: IDEMPOTENT -- re-index, 2nd single-fix is a no-op (decl now documented) ---
  & $exePath index $scratch --db $db 2>$null | Out-Null
  $rawB = (& $exePath lint-all --db $db --config $cfg --json 2>$null) -join "`n"
  $bS = $rawB.IndexOf('['); $bE = $rawB.LastIndexOf(']')
  $findingsB = @()
  if ($bS -ge 0 -and $bE -gt $bS) { $findingsB = @(ConvertFrom-Json $rawB.Substring($bS, $bE - $bS + 1)) }
  $mdB = @($findingsB | Where-Object { $_.rule -eq 'missing-doc' -and $_.start_line -eq $L })
  Check 'B1 no missing-doc finding on the now-documented decl (idempotent)' ($mdB.Count -eq 0)
  $before2 = [IO.File]::ReadAllText($target)
  # opt missing-doc in again (OFF by default -- ADF Task 13); the decl is now
  # documented so this is a no-op regardless, but the finding must survive to reach
  # the --fix block for the no-op path to be genuinely exercised.
  & $exePath lint-all --db $db --config $cfg --fix --fix-line $L --fix-rule missing-doc --apply --no-backup 2>$null | Out-Null
  $after2 = [IO.File]::ReadAllText($target)
  Check 'B2 2nd single-fix is byte-identical (no-op)' ($before2 -eq $after2)

  # ---- Part C: blanket batch EXCLUDES missing-doc ------------------------
  $scratchB = Join-Path C:\TEMP 'draglint_missdocfix_batch'
  if (Test-Path $scratchB) { Remove-Item $scratchB -Recurse -Force }
  New-Item -ItemType Directory -Path $scratchB | Out-Null
  $targetB = Join-Path $scratchB 'missfix.pas'
  $dbB     = Join-Path $scratchB 'missfix.sqlite'
  $cfgB    = Join-Path $scratchB 'missfix.config.json'
  Copy-Item $fixture $targetB -Force
  '{ "enabled": ["missing-doc"] }' | Set-Content -Path $cfgB -Encoding ascii -NoNewline
  & $exePath index $scratchB --db $dbB 2>$null | Out-Null

  $beforeBatch = [IO.File]::ReadAllText($targetB)
  # blanket batch: --fix with NO --fix-line / --fix-rule narrowing.
  & $exePath lint-all --db $dbB --config $cfgB --fix --apply --no-backup 2>$null | Out-Null
  $afterBatch = [IO.File]::ReadAllText($targetB)
  # v(ADP3 T3d2): C1 used to be its own check probing for the managed-block
  # marker (a v(ADP3 T3) fix -- the ORIGINAL probe, '<param name="Value">', had
  # gone vacuous once the engine stopped emitting that tag for ANY input, so it
  # would have passed even if the batch HAD inserted a full comment). But over
  # $beforeBatch (this fixture's ORIGINAL, undocumented text -- no drag-lint
  # marker anywhere in it) byte-identical STRICTLY IMPLIES "no marker was
  # inserted": C1 could never fail while C2 passed, so it contributed a second
  # failure LABEL, not second coverage. Folded into C2, which now carries both
  # meanings.
  Check 'C2 Undocumented decl unchanged by the blanket batch, INCLUDING no doc-comment marker inserted (single-fix-only excluded)' ($beforeBatch -eq $afterBatch)

  # ---- Part D: rules --json fixable ---------------------------------------
  $rj = & $exePath rules --json 2>$null | Out-String
  $ro = $rj | ConvertFrom-Json
  $byId = @{}; foreach($r in $ro.rules){ $byId[$r.id] = $r }
  Check 'D1 missing-doc fixable=true' ($byId['missing-doc'].fixable -eq $true)
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
