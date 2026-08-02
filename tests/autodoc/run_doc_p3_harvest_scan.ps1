<#
  run_doc_p3_harvest_scan.ps1 -- Auto-Document Phase 3, Task 6:
  HarvestScan's boundary scan and its acceptance guards.

  WHAT IS UNDER TEST
  ------------------
  `HarvestScan(ASrcLines, ADeclLine)` walks UPWARD from the line above a
  declaration, accumulating comment and blank lines until it meets real code,
  and returns the accumulated block plus an accept/reject verdict. It is pure:
  no I/O, no index, no tree-sitter parse. That purity is the point -- the
  harvester must work on a file the parser cannot resolve, so the scan is
  line-lexical and nothing else.

  It is reached from the CLI through `selftest harvest --file <p> --line <n>`,
  which prints one machine-readable line

      REASON=<...> LINES=<n> START=<n> END=<n>

  followed by `RAW: ` + each accumulated line. The probe exists so the scan can
  be asserted BEFORE Task 7 gives it a consumer; without it the first thing
  that would exercise these guards is the text transformation built on top of
  them, and a guard's failure would surface as wrong prose three tasks later.

  THE VERDICTS, AND WHY EACH GUARD EXISTS
  ---------------------------------------
  Every reject below is a comment a human wrote that must NOT become that
  symbol's documentation. Harvesting is a WRITE into the user's source, so a
  false accept ships someone else's words as an API contract.

    ACCEPTED       a real header comment, adjacent or blank-line separated.
    NONE           nothing above the declaration but code, or the block above
                   is already DocInsight (///) -- whose precedence is Task 8's
                   question, not this scan's.
    BANNER         a separator rule (`// ------`). Decoration, not prose.
    COMMENTEDCODE  dead code parked in a comment. `:=`, begin/end;, or a line
                   that ends in ';'.
    TRAILER        a note that closes the routine ABOVE, not one that
                   introduces the declaration below. Decided by the layout
                   tie-breaker, and only when the scan stopped at `end;`.
    EMPTY          a bare `//` with nothing on it.
    NONASCII       any byte >= 128. .pas files here are strict 7-bit ASCII;
                   promoting a Latin-1 byte into a /// line would break that.
    NESTEDBRACE    a { } comment whose text itself contains a brace. Pascal
                   comments do not nest, so re-emitting that text inside braces
                   would terminate the comment early.

  THE TIE-BREAKER IS TESTED IN BOTH DIRECTIONS. CaseTrailer and CaseAfterEnd
  stop at the same keyword and differ only in where the blank line sits. A rule
  that simply rejected every block whose scan stopped at `end;` would satisfy
  CaseTrailer; CaseAfterEnd is what makes that rule fail. Both are
  IMPLEMENTATION-ONLY declarations, because only there is there an `end;` above.

  NON-VACUITY. Two controls run before the per-case checks: every invocation
  must exit 0 and print a parseable REASON line (a probe that errored would
  otherwise satisfy every "is not ACCEPTED" check), and the observed verdicts
  must cover more than one value (an engine that answered NONE to everything
  would pass all seven rejects).

  Runs from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$fx      = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\harvest_scan.pas')).Path

# ---------------------------------------------------------------------------
# Helpers. Standalone by convention -- every runner in this directory carries
# its own copies rather than dot-sourcing a shared module.
# ---------------------------------------------------------------------------

# 1-based line number of $name's declaration in $section ('interface' /
# 'implementation'), located in the RAW fixture text. Deliberately NOT read
# from the index: HarvestScan takes a line number and a line array and knows
# nothing about symbols, so making the runner depend on an index would couple
# this suite to a component the unit under test does not use. Returns 0 when
# absent, which every caller asserts on.
function Get-FixtureDeclLine([string[]]$lines, [string]$name, [string]$section) {
  $implIdx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^implementation\s*$') { $implIdx = $i; break } }
  if ($implIdx -lt 0) { return 0 }
  $rx = '^function\s+' + [regex]::Escape($name) + '\s*:\s*Integer;\s*$'
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -notmatch $rx) { continue }
    if ($section -eq 'interface')      { if ($i -lt $implIdx) { return $i + 1 } }
    elseif ($section -eq 'implementation') { if ($i -gt $implIdx) { return $i + 1 } }
  }
  return 0
}

# Runs the probe and returns a hashtable of its parsed output:
#   Exit, Reason, Lines, Start, End, Raw (string[]), Out (raw stdout, for msgs)
# Reason is '' when no REASON= line was printed at all, which the non-vacuity
# control asserts against before any per-case check reads it.
function Invoke-Harvest([string]$file, [int]$line) {
  $out  = & $exePath selftest harvest --file $file --line $line 2>&1
  $code = $LASTEXITCODE
  $txt  = @($out | ForEach-Object { "$_" })
  $res  = @{ Exit = $code; Reason = ''; Lines = -1; Start = -1; End = -1; Raw = @(); Out = ($txt -join ' | ') }
  foreach ($l in $txt) {
    $m = [regex]::Match($l, '^REASON=(\S+)\s+LINES=(-?\d+)\s+START=(-?\d+)\s+END=(-?\d+)\s*$')
    if ($m.Success) {
      $res.Reason = $m.Groups[1].Value
      $res.Lines  = [int]$m.Groups[2].Value
      $res.Start  = [int]$m.Groups[3].Value
      $res.End    = [int]$m.Groups[4].Value
    }
    elseif ($l -match '^RAW: (.*)$') { $res.Raw += $Matches[1] }
  }
  return $res
}

Push-Location C:\TEMP
try {

Write-Host ''
Write-Host '=== harvest_scan.pas, selftest harvest ===' -ForegroundColor Cyan

$src = [IO.File]::ReadAllLines($fx)

# ---------------------------------------------------------------------------
# The cases. Section is load-bearing: the two trailer layouts exist only in the
# implementation section, and CaseAdjacent's interface and implementation
# headers have DIFFERENT things above them.
# ---------------------------------------------------------------------------
$cases = @(
  @{ N = 'CaseAdjacent'     ; S = 'interface'     ; Want = 'ACCEPTED'      ; Why = 'a plain adjacent header comment' },
  @{ N = 'CaseBlankGap'     ; S = 'interface'     ; Want = 'ACCEPTED'      ; Why = 'separated from the declaration by a blank line' },
  @{ N = 'CaseBanner'       ; S = 'interface'     ; Want = 'BANNER'        ; Why = 'a separator rule is decoration, not prose' },
  @{ N = 'CaseCommentedCode'; S = 'interface'     ; Want = 'COMMENTEDCODE' ; Why = 'dead code parked in a comment' },
  @{ N = 'CaseNoComment'    ; S = 'interface'     ; Want = 'NONE'          ; Why = 'nothing but code above the declaration' },
  @{ N = 'CaseEmptyComment' ; S = 'interface'     ; Want = 'EMPTY'         ; Why = 'a bare // with no content' },
  @{ N = 'CaseNestedBrace'  ; S = 'interface'     ; Want = 'NESTEDBRACE'   ; Why = 'a { } comment whose own text contains a brace' },
  @{ N = 'CaseAlreadyDoc'   ; S = 'interface'     ; Want = 'NONE'          ; Why = 'the block above is already DocInsight -- not a harvest candidate' },
  @{ N = 'CaseTrailer'      ; S = 'implementation'; Want = 'TRAILER'       ; Why = 'the comment hugs end; and a blank line separates it from the declaration' },
  @{ N = 'CaseAfterEnd'     ; S = 'implementation'; Want = 'ACCEPTED'      ; Why = 'same stop keyword, opposite layout -- blank after end;, comment adjacent' }
)

# --- Declaration lines resolve at all. --------------------------------------
foreach ($c in $cases) {
  $c.Line = Get-FixtureDeclLine $src $c.N $c.S
  Check ("FIXTURE: {0}'s {1} declaration resolved to a line" -f $c.N, $c.S) ($c.Line -gt 0) ("line=" + $c.Line)
}

# --- Run the probe once per case. -------------------------------------------
foreach ($c in $cases) { $c.R = Invoke-Harvest $fx $c.Line }

# --- NON-VACUITY CONTROLS, asserted BEFORE any per-case verdict. ------------
# A probe that failed to run prints no REASON line, and every "is not ACCEPTED"
# check below would then pass on an engine that does nothing at all.
$noRun = @($cases | Where-Object { ($_.R.Exit -ne 0) -or ($_.R.Reason -eq '') })
Check 'CONTROL: every invocation exited 0 and printed a parseable REASON= line' `
  ($noRun.Count -eq 0) (($noRun | ForEach-Object { "$($_.N):exit=$($_.R.Exit):[$($_.R.Out)]" }) -join ' || ')

# ... and answered more than one thing. An engine hardwired to NONE satisfies
# all seven rejects; this is what tells that apart from a working scan.
$distinct = @($cases | ForEach-Object { $_.R.Reason } | Sort-Object -Unique)
Check 'CONTROL: the observed verdicts cover more than one value' `
  ($distinct.Count -ge 2) ("distinct=" + ($distinct -join ','))

# --- The verdict table. -----------------------------------------------------
foreach ($c in $cases) {
  Check ("{0} ({1}) -> {2}" -f $c.N, $c.Why, $c.Want) ($c.R.Reason -eq $c.Want) `
    ("got=" + $c.R.Reason + " lines=" + $c.R.Lines + " raw=[" + ($c.R.Raw -join ' / ') + "]")
}

# --- The accepted block's payload, not just its verdict. --------------------
# ACCEPTED with an empty block would satisfy the row above. Assert the count
# the plan pins and the text that identifies it.
$adj = ($cases | Where-Object { $_.N -eq 'CaseAdjacent' }).R
Check 'CaseAdjacent: the accepted block is exactly ONE line' ($adj.Lines -eq 1) ("LINES=" + $adj.Lines)
Check 'CaseAdjacent: the raw text carries the comment it harvested' `
  (($adj.Raw -join ' ') -match 'plain adjacent header') ("raw=[" + ($adj.Raw -join ' / ') + "]")
# START/END must delimit that line in the SOURCE, not an offset inside the
# block: Task 9's strip round-trip deletes by those numbers.
Check 'CaseAdjacent: START/END delimit the comment line in the file, and the source there is that comment' `
  (($adj.Start -gt 0) -and ($adj.Start -eq $adj.End) -and ($src[$adj.Start - 1] -match 'plain adjacent header')) `
  ("start=" + $adj.Start + " end=" + $adj.End + " src=[" + $(if ($adj.Start -gt 0) { $src[$adj.Start - 1] } else { '' }) + "]")

# The blank-gap block must be the COMMENT, with the separating blank line
# dropped -- otherwise Task 7 splits a trailing empty paragraph off it.
$gap = ($cases | Where-Object { $_.N -eq 'CaseBlankGap' }).R
Check 'CaseBlankGap: the accepted block is the comment alone -- the separating blank line is not part of it' `
  (($gap.Lines -eq 1) -and (($gap.Raw -join ' ') -match 'separated from the declaration')) `
  ("LINES=" + $gap.Lines + " raw=[" + ($gap.Raw -join ' / ') + "]")

# A rejected verdict reports no block. Otherwise a caller that ignored Reason
# would harvest the banner anyway.
foreach ($c in @($cases | Where-Object { $_.Want -eq 'NONE' })) {
  Check ("{0}: NONE reports an empty block and zeroed line numbers" -f $c.N) `
    (($c.R.Lines -eq 0) -and ($c.R.Start -eq 0) -and ($c.R.End -eq 0) -and ($c.R.Raw.Count -eq 0)) `
    ("lines=" + $c.R.Lines + " start=" + $c.R.Start + " end=" + $c.R.End)
}

# --- NONASCII: a scratch copy with one Latin-1 byte in an ACCEPTED comment. --
# Built from the accepted case on purpose: the only difference between it and
# the green row above is the byte, so a NONASCII verdict here is attributable
# to the byte and to nothing else.
$sc = Join-Path C:\TEMP 'draglint_docp3_harvest'
if (Test-Path $sc) { Remove-Item $sc -Recurse -Force }
New-Item -ItemType Directory -Path $sc | Out-Null
$tgt = Join-Path $sc 'harvest_scan_latin1.pas'

$adjCase  = ($cases | Where-Object { $_.N -eq 'CaseAdjacent' })
$bytes    = [IO.File]::ReadAllBytes($fx)
$hiBefore = @($bytes | Where-Object { $_ -ge 128 }).Count
Check 'CONTROL: the shipped fixture is 7-bit ASCII (so the scratch copy''s byte is the only one)' `
  ($hiBefore -eq 0) ("high_bytes=" + $hiBefore)

$scratch = [IO.File]::ReadAllLines($fx)
$scratch[$adjCase.Line - 2] = $scratch[$adjCase.Line - 2] -replace 'plain', "plain`u{00E9}"
$sw = New-Object System.IO.StreamWriter($tgt, $false, [Text.Encoding]::GetEncoding(1252))
foreach ($l in $scratch) { $sw.Write($l); $sw.Write("`r`n") }
$sw.Close()

$hiAfter = @([IO.File]::ReadAllBytes($tgt) | Where-Object { $_ -ge 128 }).Count
Check 'CONTROL: the scratch copy really carries exactly ONE byte >= 128' ($hiAfter -eq 1) ("high_bytes=" + $hiAfter)

$la = Invoke-Harvest $tgt $adjCase.Line
Check 'NONASCII: the same comment, plus one Latin-1 byte, is rejected' ($la.Reason -eq 'NONASCII') `
  ("got=" + $la.Reason + " out=[" + $la.Out + "]")

# --- The probe's own error contract. ----------------------------------------
$missing = Invoke-Harvest (Join-Path $sc 'no_such_file.pas') 5
Check 'PROBE: a missing --file exits 2' ($missing.Exit -eq 2) ("exit=" + $missing.Exit + " out=[" + $missing.Out + "]")

# A line number outside the file is NONE, not a crash: Task 8 calls this with
# line numbers that came from an index which may lag the file on disk.
$oob = Invoke-Harvest $fx ($src.Count + 500)
Check 'PROBE: a --line past end-of-file is NONE, not a crash' `
  (($oob.Exit -eq 0) -and ($oob.Reason -eq 'NONE')) ("exit=" + $oob.Exit + " reason=" + $oob.Reason)

}
finally { Pop-Location }

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
