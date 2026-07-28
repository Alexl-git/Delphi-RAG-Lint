<#
  run_doc_p3_returns.ps1 -- Auto-Document Phase 3, Task 4b:
  what the mined <returns> section is allowed to say.

  Source: docs/INBOX-autodoc-returns-section-incomplete.md. The reporter's
  framing was that the generated sentence "names a value the function provably
  does not return", and that the same text is read many times a day through
  Help Insight and LSP hover. Four defects, one miner
  (src/cli/DRagLint.Hover.Returns.pas), shared by autodoc and hover.

  FOUR RULES
  ----------
  (1) MUTATION SUPPRESSES.  Result can be changed by things that are not a
      whole-Result assignment -- Dec(Result), SetLength(Result, ..), and the
      self-referential Result := Result + x. When any of those is present the
      enumeration of whole-Result assignments is not an account of what comes
      back, so it is emitted not at all. YADF's PrevSignificantIdx read
      "Observed: AFrom" for a routine whose entire job is to walk away from
      AFrom.

  (2) AN INCOMPLETE CAPTURE IS NOT EMITTED.  The RHS is captured from one
      physical line. When it does not end on that line -- unbalanced parens, a
      trailing binary operator -- the fragment used to ship as if it were the
      return value ("Observed: (A > 0) and."). Absence over wrong.

  (3) THE CAPTURE STOPS AT THE STATEMENT, NOT AT THE NEXT ';'.  On
      `begin Result := X end` there is no ';' to stop at, so `end else begin
      Result := 0 end` used to leak into prose. The capture now also ends at a
      block keyword, and it is string- and paren-aware, so a ';' inside a
      literal no longer truncates.

  (4) A NESTED ROUTINE'S Result IS ITS OWN.  Doc.Facts hands the miner the
      ENCLOSING routine's whole impl span, and an anonymous method or a named
      local routine lives inside those lines -- so their Result assignments
      were credited to the host. YADF's OptionTable listed six anonymous
      getters' Results; FormatSource listed four from local helpers.

  WHAT DOES *NOT* CHANGE, AND IS ASSERTED AS SUCH
  -----------------------------------------------
  Result.<Field> := is still not mined (DefaultCfg). This already worked -- the
  word-boundary test passes on '.', then ':=' is not what follows, so the
  candidate is rejected -- and it is the single most likely thing to break
  while widening the miner to see mutations: YADF's DefaultOptions populates 42
  fields in a row, and a careless widening would enumerate all 42 into one
  sentence.

  NOT REPRODUCIBLE, THEREFORE NOT FIXED: the INBOX's 3.1 (a nested call
  truncated to "TPath.Combine(") does NOT happen with the current engine --
  NestedCallRhs proves the whole expression is captured. The truncated text in
  the YADF working copy is output from an OLDER build that the current engine
  can no longer overwrite, because it carries no provenance marker and T3
  therefore reads it as hand-written. See docs/INBOX-REPLY-autodoc-returns.

  SCENARIO
  --------
  fixtures\docp3\returns.pas, indexed ALONE, document --unit --apply.

  Every PRECONDITION is derived from the INDEX (impl_start_line/impl_end_line
  via `query --json`) plus the PRE-APPLY source, never from the doc comments
  the checks then read. That separation is what makes them controls: the whole
  point of group (4) is that the host's indexed span COVERS the nested
  routine's lines, and that property is invisible in the rendered output. If
  the indexer ever gives a nested routine its own span, these fail and name the
  fixture instead of leaving the scenario vacuous.

  Every ABSENCE is paired with the enumerated set of routines that must still
  render. A rule that simply stopped emitting <returns> would satisfy every
  absence check in this file; the eight-strong control list and the exact
  expected texts are what tell those two apart.

  LOAD-BEARING PROOFS (transcripts in the task 4b report). Each mutation leaves
  the mechanism reachable and changes only its answer:
    M1  MaskNestedRoutines returns its input unchanged -> the NESTED group
        reddens (AnonHost, LocalHost, and the file-wide leak checks); the
        MUTATION, CAPTURE and CONTROL groups stay green.
    M2  HasResultMutation forced False -> the MUTATION group reddens (PrevIdx,
        Accum, and the Observed:-line count); everything else stays green.
    M3  The incomplete-RHS guard removed -> MultiLineRhs reddens alone.
    M4  The block-keyword terminator removed -> OneLiner reddens alone.

  Runs from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$fx      = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\returns.pas')).Path

# ---------------------------------------------------------------------------
# Helpers. Standalone by convention -- every runner in this directory carries
# its own copies rather than dot-sourcing a shared module.
# ---------------------------------------------------------------------------

function Get-FileMd5([string]$p) { (Get-FileHash -Algorithm MD5 -Path $p).Hash }

# The contiguous run of ///-prefixed lines immediately above 1-based line
# $declLine1, per-line trimmed and newline-joined. Tolerates ONE leading blank
# line, mirroring FindDocRegionAbove's own AllowGap=1 default. Anchored by LINE
# NUMBER from a fresh reindex, never by a declaration regex: an apply rewrites
# the file and shifts every line below it, and this fixture spells every
# signature twice (interface and implementation).
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

# INTERFACE-section start line for $name, read back from the index via the
# engine's own query verb (index-first: no second parser, no python).
function Get-DeclLine([string]$db, [string]$name) {
  $j = (& $exePath query --name $name --db $db --json 2>$null) -join "`n"
  $o = $null; try { $o = ($j | ConvertFrom-Json) } catch { return 0 }
  if ($null -eq $o) { return 0 }
  foreach ($r in @($o)) { if ($r.section -eq 'interface') { return [int]$r.start_line } }
  return 0
}

# The IMPLEMENTATION span (impl_start_line..impl_end_line) the index records
# for $name -- the exact line range Doc.Facts hands the miner. Returns
# @(0,0) when the symbol is absent, which the callers assert on.
function Get-ImplSpan([string]$db, [string]$name) {
  $j = (& $exePath query --name $name --db $db --json 2>$null) -join "`n"
  $o = $null; try { $o = ($j | ConvertFrom-Json) } catch { return @(0,0) }
  if ($null -eq $o) { return @(0,0) }
  foreach ($r in @($o)) {
    if ([int]$r.impl_start_line -gt 0) { return @([int]$r.impl_start_line, [int]$r.impl_end_line) }
  }
  return @(0,0)
}

# 1-based line numbers inside $src whose text matches $rx.
function Find-Lines([string[]]$src, [string]$rx) {
  $out = New-Object System.Collections.Generic.List[int]
  for ($i = 0; $i -lt $src.Count; $i++) { if ($src[$i] -match $rx) { $out.Add($i + 1) } }
  return $out
}

# The 'Observed: ...' payload of the <returns> tag inside a doc block, or ''.
function Get-Observed([string]$block) {
  $m = [regex]::Match($block, '<returns>(?:<!--[^>]*-->)?\s*Observed:\s*(.*?)\.?</returns>')
  if ($m.Success) { return $m.Groups[1].Value } else { return '' }
}

Push-Location C:\TEMP
try {

Write-Host ''
Write-Host '=== returns.pas, document --unit --apply ===' -ForegroundColor Cyan

$sc = Join-Path C:\TEMP 'draglint_docp3_returns'
if (Test-Path $sc) { Remove-Item $sc -Recurse -Force }
New-Item -ItemType Directory -Path $sc | Out-Null
$tgt = Join-Path $sc 'returns.pas'
$db  = Join-Path $sc 'r.sqlite'
Copy-Item $fx $tgt -Force

& $exePath index $sc --db $db 2>$null | Out-Null

$pre = [IO.File]::ReadAllLines($tgt)   # PRE-APPLY source: what the miner sees.

# ===========================================================================
# PRECONDITIONS -- derived from the INDEX + the pre-apply source, never from
# the doc comments the checks below read.
# ===========================================================================

# (4) The whole nested-routine group only tests anything if the HOST's indexed
# impl span really does cover the nested routine's lines -- that is the bug.
# Neither the span nor the coverage is observable in the rendered <returns>,
# so neither may be inherited from fixture prose.
foreach ($p in @(
    @{ Host_ = 'AnonHost' ; Rx = 'Result := AInner\.Beta' ; What = 'the anonymous method''s Result' },
    @{ Host_ = 'LocalHost'; Rx = 'Result := X \* 5'       ; What = 'the local routine Twice''s Result' })) {
  $span = Get-ImplSpan $db $p.Host_
  $ln   = @(Find-Lines $pre $p.Rx)
  $ok   = ($span[0] -gt 0) -and ($ln.Count -eq 1) -and ($ln[0] -ge $span[0]) -and ($ln[0] -le $span[1])
  Check ("PRECONDITION: {0}'s indexed impl span {1}..{2} CONTAINS {3} (line {4})" -f `
         $p.Host_, $span[0], $span[1], $p.What, ($ln -join ',')) $ok
}
# ... and only if the nested routine is NOT a symbol in its own right. Nested
# routines are not indexed today; asserting it means the day that changes, this
# fails and names the fixture rather than going quietly vacuous.
$twiceSpan = Get-ImplSpan $db 'Twice'
Check 'PRECONDITION: the nested routine Twice is NOT indexed as its own symbol' `
  ($twiceSpan[0] -eq 0) ("span=" + ($twiceSpan -join '..'))

# (1) The mutation group needs its mutations to actually be inside the span.
foreach ($p in @(
    @{ N = 'PrevIdx'; Rx = 'Dec\(Result\)'          ; What = 'a Dec(Result) mutation' },
    @{ N = 'Accum'  ; Rx = 'Result := Result \+ '   ; What = 'a self-referential Result := Result + x' })) {
  $span = Get-ImplSpan $db $p.N
  $ln   = @(Find-Lines $pre $p.Rx)
  $in   = @($ln | Where-Object { $_ -ge $span[0] -and $_ -le $span[1] })
  Check ("PRECONDITION: {0}'s indexed impl span {1}..{2} CONTAINS {3}" -f $p.N, $span[0], $span[1], $p.What) `
    (($span[0] -gt 0) -and ($in.Count -eq 1)) ("lines=" + ($ln -join ','))
}

# (2) MultiLineRhs only tests the incomplete-capture rule if its RHS genuinely
# runs onto a second physical line: the assignment line must carry no ';' and
# the NEXT line must.
$mlSpan = Get-ImplSpan $db 'MultiLineRhs'
$mlLn   = @(Find-Lines $pre 'Result := \(A > 0\) and')
$mlOk   = ($mlSpan[0] -gt 0) -and ($mlLn.Count -eq 1) -and ($mlLn[0] -ge $mlSpan[0]) -and ($mlLn[0] -le $mlSpan[1]) `
          -and ($pre[$mlLn[0]-1] -notmatch ';') -and ($pre[$mlLn[0]] -match ';')
Check 'PRECONDITION: MultiLineRhs''s RHS spans TWO physical lines inside its indexed span (no '';'' on the first, one on the second)' `
  $mlOk ("span=" + ($mlSpan -join '..') + " line=" + ($mlLn -join ',') )

# (3) OneLiner only tests the block-keyword terminator if an 'end' really does
# sit between its Result assignment and the line's only ';'.
$olSpan = Get-ImplSpan $db 'OneLiner'
$olLn   = @(Find-Lines $pre 'Result := A \* 3')
$olTxt  = if ($olLn.Count -eq 1) { $pre[$olLn[0]-1] } else { '' }
$olTail = if ($olTxt -match 'Result := A \* 3(.*)$') { $Matches[1] } else { '' }
Check 'PRECONDITION: OneLiner''s Result assignment is followed by ''end'' BEFORE the line''s first '';''' `
  (($olSpan[0] -gt 0) -and ($olLn.Count -eq 1) -and ($olLn[0] -ge $olSpan[0]) -and ($olLn[0] -le $olSpan[1]) `
   -and ($olTail -match '^\s+end') ) ("tail=" + $olTail)

# (2c, the item that did NOT reproduce) NestedCallRhs is only evidence for
# "the whole nested call is captured" if the call really is nested, really has
# the space after the open paren that the reporter blamed, and really is ONE
# physical line ending in ';'.
$ncSpan = Get-ImplSpan $db 'NestedCallRhs'
$ncLn   = @(Find-Lines $pre 'Result := ConcatPath\( ConcatPath\(')
$ncTxt  = if ($ncLn.Count -eq 1) { $pre[$ncLn[0]-1] } else { '' }
Check 'PRECONDITION: NestedCallRhs''s RHS is ONE physical line, nested, with a space after the open paren, ending in '';''' `
  (($ncSpan[0] -gt 0) -and ($ncLn.Count -eq 1) -and ($ncLn[0] -ge $ncSpan[0]) -and ($ncLn[0] -le $ncSpan[1]) `
   -and ($ncTxt.TrimEnd() -match ';$')) ("line=" + ($ncLn -join ',') + " :: " + $ncTxt.Trim())

# (regression) DefaultCfg only guards the 42-field blow-up if it really does
# assign several distinct members of Result and nothing else.
$dcSpan   = Get-ImplSpan $db 'DefaultCfg'
$dcFields = @('Alpha','Beta','Gamma','Delta','Sigma','Omega')
$dcHits   = @($dcFields | Where-Object { @(Find-Lines $pre ("Result\.$_\s*:=")) | Where-Object { $_ -ge $dcSpan[0] -and $_ -le $dcSpan[1] } })
Check 'PRECONDITION: DefaultCfg assigns all SIX Result.<Field> members inside its indexed span' `
  (($dcSpan[0] -gt 0) -and ($dcHits.Count -eq 6)) ("fields=" + ($dcHits -join ','))

# (guard) InlineProcVar only guards the nested-routine DETECTOR if it really
# spells the 'function' keyword inside its own span without opening a scope.
$ipSpan = Get-ImplSpan $db 'InlineProcVar'
$ipLn   = @(Find-Lines $pre 'F: function\(X: Integer\): Integer;')
Check 'PRECONDITION: InlineProcVar declares a PROCEDURAL-TYPE local (the ''function'' keyword, no body) inside its indexed span' `
  (($ipSpan[0] -gt 0) -and ($ipLn.Count -eq 1) -and ($ipLn[0] -ge $ipSpan[0]) -and ($ipLn[0] -le $ipSpan[1])) `
  ("span=" + ($ipSpan -join '..') + " line=" + ($ipLn -join ','))

# ===========================================================================
# APPLY
# ===========================================================================
& $exePath document --unit $tgt --db $db --apply 2>$null | Out-Null
$md5Cycle1 = Get-FileMd5 $tgt
# Reindex so the declaration lines below describe the file the apply just wrote.
& $exePath index $sc --db $db 2>$null | Out-Null

$text  = [IO.File]::ReadAllText($tgt)
$lines = [IO.File]::ReadAllLines($tgt)

$names  = @('PlainSum','DoubleIt','ConcatPath','PrevIdx','Accum','DefaultCfg',
            'NestedCallRhs','MultiLineRhs','OneLiner','AnonHost','LocalHost','InlineProcVar')
$blocks = @{}
foreach ($nm in $names) {
  $ln = Get-DeclLine $db $nm
  Check "$nm resolved to an interface declaration line" ($ln -gt 0) "line=$ln"
  $blocks[$nm] = Get-DocBlockAtLine $lines $ln
}

# --- NON-VACUITY CONTROL, asserted BEFORE any absence check. ----------------
# 'no Observed: here' is trivially true over a file with no <returns> at all,
# and a rule that stopped emitting <returns> entirely would satisfy every
# absence check below. Pin the exact population instead: EIGHT ///-prefixed
# Observed: lines, one for each routine that must still render.
#
# The '^\s*///' half of the filter is load-bearing, not decoration: this
# fixture's own header comment DISCUSSES the word Observed: in '//' prose, and
# without the filter this control reads one more line than the engine emitted.
# A filter that matches the thing it is describing is the exact shape of a
# vacuous test.
$obsLines = @($lines | Where-Object { $_ -match '^\s*///' -and $_ -match 'Observed:' })
Check 'CONTROL: exactly EIGHT ///-prefixed "Observed:" lines in the applied file' `
  ($obsLines.Count -eq 8) ("count=" + $obsLines.Count)
foreach ($nm in @('PlainSum','DoubleIt','ConcatPath','NestedCallRhs','OneLiner','AnonHost','LocalHost','InlineProcVar')) {
  Check "CONTROL: $nm still renders an Observed: line" ((Get-Observed $blocks[$nm]) -ne '') `
    ($blocks[$nm] -replace "`n",' | ')
}

# --- (1) MUTATION suppresses. ----------------------------------------------
# Three DIFFERENT claims per routine, not one restated: the payload is gone,
# the tag itself is gone (T3's omit-when-empty -- an empty <returns></returns>
# renders as a blank tooltip, which is worse than none), and the exact sentence
# that shipped before is nowhere in the file. $Was is the VERBATIM pre-fix
# output, so 'it no longer says this' cannot pass by naming a substring that
# was never emitted.
foreach ($p in @(
    @{ N = 'PrevIdx'; Was = 'Observed: AFrom.'                     ; Why = 'Dec(Result) makes the seed a false claim' },
    @{ N = 'Accum'  ; Was = 'Observed: 0; Result + AItems[I].'     ; Why = 'a self-referential RHS leaks an intermediate' })) {
  Check ("MUTATION: {0} emits NO Observed: at all ({1})" -f $p.N, $p.Why) `
    ((Get-Observed $blocks[$p.N]) -eq '') ($blocks[$p.N] -replace "`n",' | ')
  Check ("MUTATION: {0} emits no <returns> TAG at all (omit-when-empty)" -f $p.N) `
    (-not ($blocks[$p.N] -match '<returns>')) ($blocks[$p.N] -replace "`n",' | ')
  $bad = @($lines | Where-Object { $_ -match '^\s*///' -and $_ -match [regex]::Escape($p.Was) })
  Check ("MUTATION: the sentence that used to ship for {0} -- '{1}' -- is nowhere in the file" -f $p.N, $p.Was) `
    ($bad.Count -eq 0) ($bad -join ' | ')
}

# --- (2) An incomplete capture is not emitted. -----------------------------
Check 'CAPTURE: MultiLineRhs emits NO Observed: (its RHS does not end on its line)' `
  ((Get-Observed $blocks['MultiLineRhs']) -eq '') ($blocks['MultiLineRhs'] -replace "`n",' | ')
Check 'CAPTURE: MultiLineRhs emits no <returns> TAG at all (omit-when-empty)' `
  (-not ($blocks['MultiLineRhs'] -match '<returns>')) ($blocks['MultiLineRhs'] -replace "`n",' | ')
Check 'CAPTURE: no <returns> anywhere ships the unbalanced fragment "(A &gt; 0) and"' `
  (-not ($text -match '\(A &gt; 0\) and')) ''

# --- (3) The capture stops at the statement. -------------------------------
Check 'CAPTURE: OneLiner renders exactly "A * 3" -- the block keyword ends the RHS' `
  ((Get-Observed $blocks['OneLiner']) -eq 'A * 3') ($blocks['OneLiner'] -replace "`n",' | ')
# Scoped to the <returns> LINE, not the whole block: the managed remarks block
# legitimately ends with '<!-- drag-lint:auto END -->', and PowerShell's -match
# is case-insensitive, so a block-wide test for 'end' matches the engine's own
# marker and fails green code. Still falsifiable -- the pre-fix line read
# "Observed: A * 3 end else begin Result := 0 end.".
$olRet = @(($blocks['OneLiner'] -split "`n") | Where-Object { $_ -match '<returns>' })
Check 'CAPTURE: OneLiner''s <returns> LINE leaks no raw block syntax ("end", "else", a second "Result :=")' `
  (($olRet.Count -eq 1) -and (-not ($olRet[0] -match '(?:\bend\b|\belse\b|Result :=)'))) ($olRet -join ' | ')

# --- (4) A nested routine's Result is its own. ------------------------------
Check 'NESTED: AnonHost renders exactly its OWN return, "F(ACfg) + 1"' `
  ((Get-Observed $blocks['AnonHost']) -eq 'F(ACfg) + 1') ($blocks['AnonHost'] -replace "`n",' | ')
Check 'NESTED: LocalHost renders exactly its OWN return, "Twice(A) + 1"' `
  ((Get-Observed $blocks['LocalHost']) -eq 'Twice(A) + 1') ($blocks['LocalHost'] -replace "`n",' | ')
# File-wide, so a nested Result leaking onto SOME OTHER symbol's block is caught
# too. Both strings are unique to a nested routine's body in this fixture.
foreach ($leak in @('AInner.Beta','X * 5')) {
  $bad = @($lines | Where-Object { $_ -match '^\s*///' -and $_ -match [regex]::Escape($leak) })
  Check "NESTED: '$leak' (a nested routine's own Result) appears in NO doc comment in the file" `
    ($bad.Count -eq 0) ($bad -join ' | ')
}

# --- (guard) The nested-routine detector must not swallow a routine. --------
Check 'GUARD: InlineProcVar''s procedural-type local did not swallow its body -- it still renders "F(A) + 9"' `
  ((Get-Observed $blocks['InlineProcVar']) -eq 'F(A) + 9') ($blocks['InlineProcVar'] -replace "`n",' | ')

# --- (2c) The nested call is captured whole, not truncated at a paren. ------
Check 'CAPTURE: NestedCallRhs renders the WHOLE nested call, never a "ConcatPath(" fragment' `
  ((Get-Observed $blocks['NestedCallRhs']) -eq "ConcatPath( ConcatPath(ADir, 'sub'), AName)") `
  ($blocks['NestedCallRhs'] -replace "`n",' | ')

# --- (regression) Member-level assignment is still not a return value. ------
Check 'MEMBERS: DefaultCfg''s doc block was written at all (so the checks below are not over an absent block)' `
  ($blocks['DefaultCfg'] -match '///') ($blocks['DefaultCfg'] -replace "`n",' | ')
Check 'MEMBERS: DefaultCfg emits NO Observed: -- Result.<Field> := is not a return value' `
  ((Get-Observed $blocks['DefaultCfg']) -eq '') ($blocks['DefaultCfg'] -replace "`n",' | ')
Check 'MEMBERS: DefaultCfg emits no <returns> TAG at all (omit-when-empty)' `
  (-not ($blocks['DefaultCfg'] -match '<returns>')) ($blocks['DefaultCfg'] -replace "`n",' | ')
$retLines = @($lines | Where-Object { $_ -match '^\s*///' -and $_ -match '<returns>' })
foreach ($f in @('Alpha','Beta','Gamma','Delta','Sigma','Omega')) {
  $bad = @($retLines | Where-Object { $_ -match ('\.' + $f + '\b') })
  Check "MEMBERS: no <returns> line in the file enumerates the member '$f'" ($bad.Count -eq 0) ($bad -join ' | ')
}

# --- Hover and autodoc share the miner: assert they agree. ------------------
# Deliberate coupling (Doc.Facts calls MineReturnExpressions, the same function
# the hover popup's Returns section is built from), so a change that fixed one
# surface and not the other is a defect. One positive fixture and one
# suppressed fixture -- the positive alone would pass if hover simply returned
# nothing.
$hvA = (& $exePath hover --qname returns.AnonHost --db $db --format json 2>$null) -join ''
$hvP = (& $exePath hover --qname returns.PrevIdx  --db $db --format json 2>$null) -join ''
$jA = $null; $jP = $null
try { $jA = ($hvA -replace '\s*FTS5 probe:.*$','') | ConvertFrom-Json } catch {}
try { $jP = ($hvP -replace '\s*FTS5 probe:.*$','') | ConvertFrom-Json } catch {}
Check 'HOVER: AnonHost''s hover returns the SAME single expression autodoc rendered' `
  (($null -ne $jA) -and (@($jA.returns).Count -eq 1) -and (@($jA.returns)[0] -eq 'F(ACfg) + 1')) $hvA
Check 'HOVER: PrevIdx''s hover returns NOTHING, exactly as its <returns> was suppressed' `
  (($null -ne $jP) -and (@($jP.returns).Count -eq 0)) $hvP

# --- Idempotency: reindex + a second --apply is byte-identical. --------------
& $exePath document --unit $tgt --db $db --apply --json 2>$null | Out-Null
$md5Cycle2 = Get-FileMd5 $tgt
Check 'IDEMPOTENT: a second --apply after a reindex is byte-identical' ($md5Cycle1 -eq $md5Cycle2) `
  "c1=$md5Cycle1 c2=$md5Cycle2"

# Every emitted /// line stays 7-bit ASCII.
$bad = @()
foreach ($l in $lines) { if ($l -match '^\s*///') { foreach ($ch in $l.ToCharArray()) { if ([int]$ch -gt 126) { $bad += $l; break } } } }
Check 'every emitted /// line is 7-bit ASCII' ($bad.Count -eq 0) ($bad -join ' | ')

}
finally { Pop-Location }

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
