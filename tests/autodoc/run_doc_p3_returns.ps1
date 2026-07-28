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

  (5) THE SUPPRESSING MUTATION MUST BE IN CODE.  Rules (1) and (4) DELETE
      documentation, so their false positives are the expensive ones: they
      silently remove a true <returns> from a routine that never had the
      defect. Three shapes did exactly that -- Inc(Result) parked in a {...}
      comment, `Result := Result + 1` left in a (*..*) or a comment, and
      'Result := Result + 1' as PROSE inside a format string -- and a
      PARAMETERLESS procedural type (`var F: function: Integer;`) made the
      nested-routine detector eat the entire routine, because the word after
      the keyword is the RETURN TYPE and was read as a routine NAME. The
      mutation test now runs on a CODE-ONLY view of the body, and ':' is a
      token so "return type follows" is distinguishable from "name follows".

  (6) A SPAN THAT BEGINS EARLY INSIDE THE ROUTINE'S OWN HEADER IS STILL THAT
      ROUTINE'S SPAN.  The routine's own header used to be recognised only on
      body line 0, so an index that starts the span on the blank line above
      the header read that header as a NESTED routine and blanked the body.
      It is now accepted on body line 0 OR as the body's LEAD token -- the
      first token, or the routine keyword of a `class function`, whose `class`
      token comes first.

      A ONE-LINE LAG IS THE FIXTURE, NOT THE BOUND. A stale span is stale by
      whatever the file moved: the real rows on the shipping
      C:\Projects\YADF\YADF.sqlite are duplicate `files` entries for one path
      differing only in drive-letter case, off by 26 to 63 lines and by whole
      routines. Shifting only impl_start_line is a faithful simulation of the
      SHAPE (a span whose first line is not the header) and is the only way to
      produce it deterministically -- prepending a source line moves
      impl_end_line too, and the truncated span then has no closing 'end' to
      pop the frame, so the bug hides and the scenario tests nothing.

  (7) ... BUT ONLY IF IT IS THIS ROUTINE'S HEADER.  Rule (6)'s lead-token
      anchor originally accepted whatever routine the span happened to start
      at. Measured on the same YADF index, that clause is eligible on 96 spans
      and 81 of them (84%) head some OTHER routine -- so it did not recover a
      lost <returns>, it published a foreign routine's return values under
      this routine's name, which is the exact defect this task exists to
      remove. The lead token is now accepted only when the identifier
      following the keyword (last dotted component) IS the documented
      routine's name; otherwise the body is masked and the answer is absence.
      Callers with no name to give get the body-line-0 rule alone.
      Command: tools\measure\returns_blast.py anchor <db> [<prefix>].

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

  LOAD-BEARING PROOFS (transcripts in the task 4b report and its fix-round-1
  report). Each mutation leaves the mechanism reachable and changes only its
  answer:
    M1  MaskNestedRoutines returns its input unchanged -> the NESTED group
        reddens (AnonHost, LocalHost, and the file-wide leak checks); the
        MUTATION, CAPTURE and CONTROL groups stay green.
    M2  HasResultMutation forced False -> the MUTATION group reddens (PrevIdx,
        Accum, and the Observed:-line count); everything else stays green.
    M3  The incomplete-RHS guard removed -> MultiLineRhs reddens alone.
    M4  The block-keyword terminator removed -> OneLiner reddens alone.
  Groups (5) and (6) need no synthetic mutation: the engine at 2fbb20d IS the
  reverted fix, and every one of their checks was RED against it -- NOT-CODE
  and the two procedural-type guards emitted no <returns> at all, and the
  lagging-span scenario returned "returns":[] where the true span returns
  ["A + B"]. Transcript in the fix-round report.
  Group (7) likewise: the engine at 55bcdaf IS its reverted fix. Against it,
  ForeignB over a span starting one line above ForeignA's header hovered
  ["A * 7"] -- ForeignA's return value, under ForeignB's name -- and
  TBox.ClassLag over a span one line early hovered [] where its true span
  hovers ["A + 41"]. Transcript in the fix-round-2 report.

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

# The hover surface's own mined return list for $qname, as an array (empty when
# hover emitted none, or when the JSON could not be parsed at all).
function Get-HoverReturns([string]$db, [string]$qname) {
  $raw = (& $exePath hover --qname $qname --db $db --format json 2>$null) -join ''
  $o = $null
  try { $o = ($raw -replace '\s*FTS5 probe:.*$','') | ConvertFrom-Json } catch { return @() }
  if ($null -eq $o) { return @() }
  return @($o.returns)
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
Check 'PRECONDITION: InlineProcVar declares a PARAMETERISED PROCEDURAL-TYPE local (the ''function'' keyword, no body) inside its indexed span' `
  (($ipSpan[0] -gt 0) -and ($ipLn.Count -eq 1) -and ($ipLn[0] -ge $ipSpan[0]) -and ($ipLn[0] -le $ipSpan[1])) `
  ("span=" + ($ipSpan -join '..') + " line=" + ($ipLn -join ','))

# (5, detector) InlineProcVar above is disarmed by its PARENTHESES, so it was
# never a guard on the parameterless forms -- which is why the detector ate
# both of these. Assert the absence of parentheses explicitly: without it,
# "a procedural type is guarded" is a claim about one spelling of three.
foreach ($p in @(
    @{ N = 'ParamlessProcVar' ; Rx = 'F: function: Integer;'        ; What = 'a PARAMETERLESS procedural-type VAR' },
    @{ N = 'LocalProcTypeDecl'; Rx = 'TGetter = function: Integer;' ; What = 'a PARAMETERLESS procedural-type local TYPE' })) {
  $span = Get-ImplSpan $db $p.N
  $ln   = @(Find-Lines $pre $p.Rx)
  $in   = @($ln | Where-Object { $_ -ge $span[0] -and $_ -le $span[1] })
  $noParen = ($in.Count -eq 1) -and ($pre[$in[0]-1] -notmatch '\(')
  Check ("PRECONDITION: {0} declares {1} inside its indexed span, with NO parentheses to disarm the detector" -f $p.N, $p.What) `
    (($span[0] -gt 0) -and ($in.Count -eq 1) -and $noParen) `
    ("span=" + ($span -join '..') + " lines=" + ($ln -join ','))
}

# (5, not-code) The NOT-CODE group only tests anything if the mutation SHAPE is
# really inside each routine's indexed span and really is inside a comment or a
# string literal. Derived from the pre-apply source, never from the output.
foreach ($p in @(
    @{ N = 'BraceCommentInc'    ; Rx = '\{ old implementation: Inc\(Result\); \}' ; What = 'Inc(Result) inside a {...} comment' },
    @{ N = 'BraceCommentSelfRef'; Rx = '\{ was: Result := Result \+ 1; \}'        ; What = 'a self-referential Result := inside a {...} comment' },
    @{ N = 'ParenStarSetLength' ; Rx = '\(\* dead: SetLength\(Result, A\); \*\)'  ; What = 'SetLength(Result, ..) inside a (*..*) comment' },
    @{ N = 'StrLiteralResult'   ; Rx = "Format\('Result := Result \+ 1; %d'"      ; What = "'Result := Result + 1' inside a STRING LITERAL" })) {
  $span = Get-ImplSpan $db $p.N
  $ln   = @(Find-Lines $pre $p.Rx)
  $in   = @($ln | Where-Object { $_ -ge $span[0] -and $_ -le $span[1] })
  Check ("PRECONDITION: {0}'s indexed impl span {1}..{2} CONTAINS {3}" -f $p.N, $span[0], $span[1], $p.What) `
    (($span[0] -gt 0) -and ($in.Count -eq 1)) ("lines=" + ($ln -join ','))
}

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
            'NestedCallRhs','MultiLineRhs','OneLiner','AnonHost','LocalHost','InlineProcVar',
            'ParamlessProcVar','LocalProcTypeDecl','BraceCommentInc','BraceCommentSelfRef',
            'ParenStarSetLength','StrLiteralResult','ClassLag','ForeignA','ForeignB')
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
Check 'CONTROL: exactly SEVENTEEN ///-prefixed "Observed:" lines in the applied file' `
  ($obsLines.Count -eq 17) ("count=" + $obsLines.Count)
foreach ($nm in @('PlainSum','DoubleIt','ConcatPath','NestedCallRhs','OneLiner','AnonHost','LocalHost','InlineProcVar',
                  'ParamlessProcVar','LocalProcTypeDecl','BraceCommentInc','BraceCommentSelfRef',
                  'ParenStarSetLength','StrLiteralResult','ClassLag','ForeignA','ForeignB')) {
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
# The PARAMETERLESS forms. InlineProcVar above is disarmed by its parentheses
# and so was never a guard on these: `function: Integer` has none, and the word
# after the keyword is the RETURN TYPE. Read as a routine NAME it stopped the
# ';' from disarming the candidate, the routine's own `begin` confirmed the
# frame, and the whole body was blanked -- both emitted no <returns> at all.
Check 'GUARD: ParamlessProcVar''s PARAMETERLESS procedural-type var did not swallow its body -- it still renders "F() + A"' `
  ((Get-Observed $blocks['ParamlessProcVar']) -eq 'F() + A') ($blocks['ParamlessProcVar'] -replace "`n",' | ')
Check 'GUARD: LocalProcTypeDecl''s local procedural TYPE did not swallow its body -- it still renders "G() + A"' `
  ((Get-Observed $blocks['LocalProcTypeDecl']) -eq 'G() + A') ($blocks['LocalProcTypeDecl'] -replace "`n",' | ')

# --- (6/7 baseline) The three stale-span carriers, with their TRUE spans. ---
# Scenarios 2 and 3 doctor these rows; a doctored result is only evidence if
# the undoctored one is right, and these are the exact texts those scenarios
# then demand back (ClassLag) or demand the ABSENCE of (ForeignA's, under
# ForeignB's name).
foreach ($p in @(
    @{ N = 'ClassLag'; Want = 'A + 41'; Why = 'a class method -- its body''s FIRST token is `class`' },
    @{ N = 'ForeignA'; Want = 'A * 7' ; Why = 'the routine a doctored ForeignB span lands in' },
    @{ N = 'ForeignB'; Want = 'A - 7' ; Why = 'the victim of that doctored span' })) {
  Check ("SPAN-BASELINE: {0} ({1}) renders exactly ""{2}"" with its TRUE span" -f $p.N, $p.Why, $p.Want) `
    ((Get-Observed $blocks[$p.N]) -eq $p.Want) ($blocks[$p.N] -replace "`n",' | ')
}

# --- (5) The suppressing mutation must be IN CODE. --------------------------
# Rule (1) DELETES documentation, so this group is its bound. Each check states
# the EXACT sentence: it cannot pass over an absent <returns> (Get-Observed
# returns '' for one), and it cannot pass on an engine that suppresses more.
Check 'NOT-CODE: BraceCommentInc renders "A + 100" -- an Inc(Result) parked in a {...} comment mutates nothing' `
  ((Get-Observed $blocks['BraceCommentInc']) -eq 'A + 100') ($blocks['BraceCommentInc'] -replace "`n",' | ')
Check 'NOT-CODE: ParenStarSetLength renders "''p'' + IntToStr(A)" -- a SetLength(Result, ..) in a (*..*) comment mutates nothing' `
  ((Get-Observed $blocks['ParenStarSetLength']) -eq "'p' + IntToStr(A)") ($blocks['ParenStarSetLength'] -replace "`n",' | ')
Check 'NOT-CODE: StrLiteralResult renders the WHOLE Format call -- "Result := Result + 1" inside a literal is prose, not a mutation' `
  ((Get-Observed $blocks['StrLiteralResult']) -eq "Format('Result := Result + 1; %d', [A])") `
  ($blocks['StrLiteralResult'] -replace "`n",' | ')
# BraceCommentSelfRef documents an OPEN defect as well as a closed one. The
# false SUPPRESSION is gone -- its real return A + 200 is named again -- but the
# MINING side still reads `Result := Result + 1` out of the comment and lists it
# first. That is register K23, deliberately still open, because mined text is
# RENDERED and blanking comments there has to decide what to leave behind. The
# expectation is pinned verbatim INCLUDING the leak, so when K23 is fixed this
# line reddens and names itself rather than the leak vanishing unnoticed.
Check 'NOT-CODE: BraceCommentSelfRef names its real return A + 200 (still preceded by the comment''s own "Result + 1" -- K23, open)' `
  ((Get-Observed $blocks['BraceCommentSelfRef']) -eq 'Result + 1; A + 200') `
  ($blocks['BraceCommentSelfRef'] -replace "`n",' | ')

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

# ===========================================================================
# (6) SCENARIO 2 -- a STALE span that still begins inside the routine's own
# header region.
#
# impl_start_line is normally the header line, but an index built before the
# last edit can start the span on the blank line ABOVE it. The header was then
# not on body line 0, was classified as a NESTED routine, and the entire body
# was blanked.
#
# Engine-verified on the shipping C:\Projects\YADF\YADF.sqlite: exactly ONE
# row is recovered this way, YADF.Groups.ParseGroups (span 123..182, header on
# 124, hovers "Root"). The earlier claim of "5 routines, every one of them
# losing its whole <returns>" was a python-port number the engine does not
# reproduce and it counted mis-anchors as gains -- see rule (7) and
# tools\measure\returns_blast.py anchor.
#
# ONE LINE IS THE FIXTURE, NOT THE BOUND -- see rule (6) in the header. Shifting
# only impl_start_line reproduces the SHAPE deterministically; a source edit
# cannot, because prepending a line moves impl_end_line too and the truncated
# span then has no closing 'end' to pop the frame, so the bug hides and the
# scenario would silently test nothing.
#
# ClassLag carries the `class function` form, whose implementation header
# begins with the `class` token: with the span one line early the routine
# keyword is the body's SECOND token, and a lead-token rule that only ever
# looked at token 0 deleted its whole <returns>. Engine-verified RED at
# 55bcdaf: "returns":[] against a true-span ["A + 41"].
# ===========================================================================
Write-Host ''
Write-Host '=== returns.pas, index span shifted one line early ===' -ForegroundColor Cyan

$sc2 = Join-Path C:\TEMP 'draglint_docp3_returns_lag'
if (Test-Path $sc2) { Remove-Item $sc2 -Recurse -Force }
New-Item -ItemType Directory -Path $sc2 | Out-Null
$tgt2 = Join-Path $sc2 'returns.pas'
$db2  = Join-Path $sc2 'r.sqlite'
Copy-Item $fx $tgt2 -Force
& $exePath index $sc2 --db $db2 2>$null | Out-Null
$src2 = [IO.File]::ReadAllLines($tgt2)

$lagPy = Join-Path $sc2 'lagspan.py'
@'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
cur = con.execute(
    "UPDATE symbols SET impl_start_line = impl_start_line - 1 "
    "WHERE name = ? AND impl_start_line > 0", (sys.argv[2],))
con.commit()
print(cur.rowcount)
'@ | Set-Content $lagPy -Encoding ascii

# PlainSum and AnonHost were both RED here before the fix; LocalHost was NOT,
# and it is kept anyway as the control that says so. The lag only swallows a
# host when the header's own candidate frame survives to the host's `begin`:
# LocalHost's NAMED nested routine spells `function` again first and OVERWRITES
# that candidate, so the bug never reaches it, while AnonHost's anonymous
# method opens after the host's `begin` and does not. Asserting only the two
# that redden would leave "the fix does not break the other nesting form"
# unstated.
foreach ($p in @(
    @{ N = 'PlainSum' ; Q = 'returns.PlainSum'      ; Hdr = '^function\s+PlainSum\('
       Want = 'A + B'        ; Why = 'a plain routine -- RED before the fix' },
    @{ N = 'AnonHost' ; Q = 'returns.AnonHost'      ; Hdr = '^function\s+AnonHost\('
       Want = 'F(ACfg) + 1'  ; Why = 'a host whose ANONYMOUS method opens after its own begin -- RED before the fix' },
    @{ N = 'LocalHost'; Q = 'returns.LocalHost'     ; Hdr = '^function\s+LocalHost\('
       Want = 'Twice(A) + 1' ; Why = 'a host with a NAMED nested routine -- green before the fix, kept as its control' },
    @{ N = 'ClassLag' ; Q = 'returns.TBox.ClassLag' ; Hdr = '^class\s+function\s+TBox\.ClassLag\('
       Want = 'A + 41'       ; Why = 'a CLASS method, whose body''s first token is `class` -- RED at 55bcdaf, "returns":[]' })) {
  $span0 = Get-ImplSpan $db2 $p.N
  $ok    = ($span0[0] -ge 2) -and ($src2[$span0[0] - 2].Trim() -eq '') -and `
           ($src2[$span0[0] - 1] -match $p.Hdr)
  Check ("PRECONDITION (lag): {0}'s TRUE span starts on its header line {1}, and the line above it is BLANK" -f $p.N, $span0[0]) `
    $ok ("above=[" + $src2[$span0[0] - 2] + "] header=[" + $src2[$span0[0] - 1] + "]")

  # Control: the shifted result is only evidence if the UNSHIFTED one is right.
  $before = @(Get-HoverReturns $db2 $p.Q)
  Check ("CONTROL (lag): with its TRUE span, {0} hovers exactly '{1}'" -f $p.N, $p.Want) `
    (($before.Count -eq 1) -and ($before[0] -eq $p.Want)) ("returns=" + ($before -join ','))

  $rc = (& python $lagPy $db2 $p.N) -join ''
  Check ("PRECONDITION (lag): the UPDATE moved exactly ONE {0} row back by a line" -f $p.N) `
    ($rc.Trim() -eq '1') ("rowcount=" + $rc)
  $span1 = Get-ImplSpan $db2 $p.N
  Check ("PRECONDITION (lag): {0}'s span now READS {1}..{2} -- one line before the header, ending where it did" -f `
         $p.N, $span1[0], $span1[1]) `
    (($span1[0] -eq $span0[0] - 1) -and ($span1[1] -eq $span0[1])) ("was=" + ($span0 -join '..') + " now=" + ($span1 -join '..'))

  # ... and the lead token really is what the rule has to cope with: for
  # ClassLag it is `class`, for the other three it is the routine keyword. Read
  # off the lagged span itself, so "the class form is covered" is an assertion
  # rather than a sentence in a comment.
  $lead = ''
  foreach ($ln in $src2[($span1[0] - 1) .. ($span1[1] - 1)]) {
    if ($ln.Trim() -ne '') { if ($ln -match '([A-Za-z_][A-Za-z0-9_]*)') { $lead = $Matches[1] }; break }
  }
  $wantLead = if ($p.N -eq 'ClassLag') { 'class' } else { 'function' }
  Check ("PRECONDITION (lag): the FIRST token of {0}'s lagged body is '{1}'" -f $p.N, $wantLead) `
    ($lead -eq $wantLead) ("lead=" + $lead)

  $after = @(Get-HoverReturns $db2 $p.Q)
  Check ("LAG: {0} ({1}) still hovers exactly '{2}' with a span that starts one line early" -f $p.N, $p.Why, $p.Want) `
    (($after.Count -eq 1) -and ($after[0] -eq $p.Want)) ("returns=" + ($after -join ','))
}
# ... and neither lagged host adopts its nested routine's Result. Recognising
# the header must not cost the masking: the whole point of accepting the FIRST
# TOKEN as a header is that everything after it is still judged normally.
foreach ($p in @(
    @{ N = 'AnonHost' ; Leak = 'AInner.Beta' },
    @{ N = 'LocalHost'; Leak = 'X * 5'       })) {
  $lagRet = @(Get-HoverReturns $db2 ('returns.' + $p.N))
  Check ("LAG: {0}'s lagged span still masks its nested routine -- '{1}' is not among its returns" -f $p.N, $p.Leak) `
    (($lagRet.Count -gt 0) -and ($lagRet -notcontains $p.Leak)) ("returns=" + ($lagRet -join ','))
}

# ===========================================================================
# (7) SCENARIO 3 -- a STALE span that begins inside a DIFFERENT ROUTINE.
#
# This is the shape rule (6)'s lead-token anchor could not tell apart from its
# own header, and it is the MAJORITY shape: on C:\Projects\YADF\YADF.sqlite,
# 81 of the 96 spans eligible for that anchor head some other routine
# (tools\measure\returns_blast.py anchor). A "recovery" there is not a
# recovery -- it publishes one routine's return values under another's name,
# which is precisely the defect this task exists to remove.
#
# ForeignB's impl_start_line is moved onto the blank line above ForeignA's
# header, so its span begins one line above ANOTHER routine's header and
# covers that routine's whole body. THE REQUIRED ANSWER IS ABSENCE. Asserting
# that here rather than "ForeignB returns A - 7" is deliberate: with the span
# stale the miner has no way to know which lines are ForeignB's, so silence is
# the only honest answer, and rule (4) of this file -- absence over wrong --
# says that is the right trade.
#
# Engine-verified RED at 55bcdaf: "returns":["A * 7"] -- ForeignA's value,
# under ForeignB's name.
# ===========================================================================
Write-Host ''
Write-Host '=== returns.pas, index span shifted INTO ANOTHER ROUTINE ===' -ForegroundColor Cyan

$sc3 = Join-Path C:\TEMP 'draglint_docp3_returns_foreign'
if (Test-Path $sc3) { Remove-Item $sc3 -Recurse -Force }
New-Item -ItemType Directory -Path $sc3 | Out-Null
$tgt3 = Join-Path $sc3 'returns.pas'
$db3  = Join-Path $sc3 'r.sqlite'
Copy-Item $fx $tgt3 -Force
& $exePath index $sc3 --db $db3 2>$null | Out-Null
$src3 = [IO.File]::ReadAllLines($tgt3)

$fgnPy = Join-Path $sc3 'foreignspan.py'
@'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
cur = con.execute(
    "UPDATE symbols SET impl_start_line = ? "
    "WHERE name = ? AND impl_start_line > 0", (int(sys.argv[3]), sys.argv[2]))
con.commit()
print(cur.rowcount)
'@ | Set-Content $fgnPy -Encoding ascii

$spanA = Get-ImplSpan $db3 'ForeignA'
$spanB = Get-ImplSpan $db3 'ForeignB'

# The two routines really are adjacent and in this order, and the line above
# ForeignA's header really is blank -- otherwise "one line above ANOTHER
# routine's header" is not what the doctored span describes.
Check ("PRECONDITION (foreign): ForeignA {0}..{1} precedes ForeignB {2}..{3}, and the line above ForeignA's header is BLANK" -f `
       $spanA[0], $spanA[1], $spanB[0], $spanB[1]) `
  (($spanA[0] -gt 1) -and ($spanB[0] -gt $spanA[1]) -and ($src3[$spanA[0] - 2].Trim() -eq '') `
   -and ($src3[$spanA[0] - 1] -match '^function\s+ForeignA\(')) `
  ("above=[" + $src3[$spanA[0] - 2] + "] header=[" + $src3[$spanA[0] - 1] + "]")

# Controls, before anything is doctored: each routine states its OWN value.
# Without these, "ForeignB returns nothing" would also be satisfied by a miner
# that returns nothing for either of them.
foreach ($p in @(@{ N = 'ForeignA'; Want = 'A * 7' }, @{ N = 'ForeignB'; Want = 'A - 7' })) {
  $r = @(Get-HoverReturns $db3 ('returns.' + $p.N))
  Check ("CONTROL (foreign): with its TRUE span, {0} hovers exactly '{1}'" -f $p.N, $p.Want) `
    (($r.Count -eq 1) -and ($r[0] -eq $p.Want)) ("returns=" + ($r -join ','))
}

$rc3 = (& python $fgnPy $db3 'ForeignB' ($spanA[0] - 1)) -join ''
Check 'PRECONDITION (foreign): the UPDATE moved exactly ONE ForeignB row' ($rc3.Trim() -eq '1') ("rowcount=" + $rc3)

$spanB2 = Get-ImplSpan $db3 'ForeignB'
Check ("PRECONDITION (foreign): ForeignB's span now READS {0}..{1} -- it begins one line ABOVE ForeignA's header and COVERS ForeignA's body" -f `
       $spanB2[0], $spanB2[1]) `
  (($spanB2[0] -eq $spanA[0] - 1) -and ($spanB2[1] -eq $spanB[1]) -and ($spanB2[1] -ge $spanA[1])) `
  ("was=" + ($spanB -join '..') + " now=" + ($spanB2 -join '..'))

# ... and ForeignA's own Result line is genuinely reachable inside that span.
# This is what makes the absence check below falsifiable: the foreign value is
# there to be picked up, and the engine used to pick it up.
$fgnLn = @(Find-Lines $src3 'Result := A \* 7')
Check ("PRECONDITION (foreign): ForeignA's own 'Result := A * 7' (line {0}) lies INSIDE ForeignB's doctored span" -f ($fgnLn -join ',')) `
  (($fgnLn.Count -eq 1) -and ($fgnLn[0] -ge $spanB2[0]) -and ($fgnLn[0] -le $spanB2[1])) `
  ("lines=" + ($fgnLn -join ','))

$fgnRet = @(Get-HoverReturns $db3 'returns.ForeignB')
Check 'FOREIGN: ForeignB does NOT adopt ForeignA''s return value "A * 7"' `
  ($fgnRet -notcontains 'A * 7') ("returns=" + ($fgnRet -join ','))
Check 'FOREIGN: ForeignB hovers NOTHING AT ALL over a span that heads another routine -- absence over wrong' `
  ($fgnRet.Count -eq 0) ("returns=" + ($fgnRet -join ','))

# The autodoc surface must agree with hover here too -- they share the miner,
# and a fix that silenced one surface only would be a defect. Asserted on the
# rendered <returns>, which is the text a human actually reads.
& $exePath document --unit $tgt3 --db $db3 --apply 2>$null | Out-Null
$lines3 = [IO.File]::ReadAllLines($tgt3)
$bad3   = @($lines3 | Where-Object { $_ -match '^\s*///' -and $_ -match 'Observed:' -and $_ -match 'A \* 7' })
Check 'FOREIGN: exactly ONE ///-prefixed "Observed:" line in the file names "A * 7" -- ForeignA''s own, and no other' `
  ($bad3.Count -eq 1) ($bad3 -join ' | ')

}
finally { Pop-Location }

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
