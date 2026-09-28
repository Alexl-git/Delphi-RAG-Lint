<#
  Trace.FormA.ps1 -- the round-trip step MODEL and its Form A text: a canonical
  writer and a parser for what the writer emits. Functions only, dot-sourced;
  NO index access and no file writes -- Emit-RoundTrip builds the model and
  writes the bytes, Test-RoundTripHelpers proves the round trip (spec AC-2).

  Grammar: charts\form-a-grammar-spec.md section 8 (the amendments for this
  question): ANCHOR / ALSO are sections, STOPS is a numbered step that also
  counts as unresolved, WHEN / UNLESS are conditions under a step (counted where
  the golden counts GUARD), FROM / REGENERATE are header attributes, and
  `[by name]` is a certainty marker beside `[certain]` / `[inferred]`.

  Canonical layout (the ONLY layout Read-FormA reads; the hand-aligned golden
  is checked by Test-FormA.ps1, never parsed here):

    TRACE <name>
      TITLE "<title>"
      FROM <selection>
      INDEX <a> + <b> + <c> AS OF <date>
      REGENERATE <command>
      TIERS <t> -> <t> -> ...
    <blank>
    <SECTION>
      -- <note>                    (an EMPTY section only, instead of any step: T6-R2)
    [NN] [<ACTOR> ]<text>[ [by name]|[inferred]] @<file>:<line>[ -- <note>]
           WHEN|UNLESS "<condition>" @<file>:<line>[ -- <note>]
           <FACET> <text>[ @<file>:<line>][ -- <note>]
    [NN] [<ACTOR> ]CROSSES <text> @<file>:<line>[ -- <note>]
    [NN] [<ACTOR> ]STOPS <reason> @<file>:<line>[ -- <note>]
    <blank>
    END TRACE  <n> steps, <n> conditions, <n> crossings, <n> unresolved.

  A note is `in <Routine>`, then `; <free text>`, then `; ask <E>`, each part
  optional and in that order, so the parser splits it back (Routine, Note, Ask).
  Free text therefore never contains `; `, and a text never contains ` @`, ` [`
  or ` -- ` -- the model refuses both, which is what keeps the line regexes
  unambiguous. No field may hold a CR or LF (it would split the line).

  Conditions are quoted VERBATIM (owner decision 2026-09-27: double quotes,
  because Pascal's '' breaks single ones): the writer never shortens, negates
  or rewrites one, and never escapes a quote inside one. A condition that
  CARRIES a double-quote therefore cannot be quoted and New-TraceCond refuses
  it; the walk turns such a hop into a STOPS step instead. The TITLE is quoted
  the same way and refused the same way (New-Trace and Write-FormA).

  A step text also must not open with a word the checker COUNTS or the parser
  reads as an actor/kind, nor end in ' --' (Test-TraceText -Head, fix round 1):
  everything the writer accepts, its parser and Test-FormA.ps1 read back.
#>

$script:FormAFacets = @('VIA', 'ONTO', 'AT', 'CONTRACT', 'FROM', 'TO', 'OVER', 'WITH')
$script:FormAConds  = @('WHEN', 'UNLESS')
$script:FormAActors = @('USER', 'CLIENT', 'SERVER', 'DATABASE')
$script:FormAAnchor = '^[A-Za-z0-9_$.\-]+:\d+$'

function New-Trace([string] $Name, [string] $Title, [string] $From, [string] $Index, [string] $AsOf, [string] $Regenerate, [string] $Tiers) {
  Test-TraceTitle $Title
  [pscustomobject]@{ Name = $Name; Title = $Title; From = $From; Index = $Index; AsOf = $AsOf
                     Regenerate = $Regenerate; Tiers = $Tiers; Sections = (New-Object System.Collections.ArrayList) }
}

function Add-TraceSection($Trace, [string] $Name) {
  if ($Name -cnotmatch '^[A-Z]+$') { throw "Add-TraceSection: '$Name' is not an upper-case section name" }
  # Note: a GENERATED line under the header, written `  -- <note>` (a Form A comment the checker skips) --
  # what an EMPTY section says instead of a STOPS (Task 6 ruling T6-R2: nothing failed, nothing is unresolved)
  $s = [pscustomobject]@{ Name = $Name; Note = ''; Items = (New-Object System.Collections.ArrayList) }
  [void]$Trace.Sections.Add($s)
  $s
}

# A text must not carry what the line regexes split on, nor begin with a word
# the step regex would read back as an actor or a kind. -Head adds the rules for
# a STEP text, which stands first on a numbered line: there Test-FormA.ps1 reads
# its first token as the line's head, so a word it COUNTS (WHEN UNLESS GUARD
# UNRESOLVED, a section word before STOPS / CROSSES) or a lone annotation it
# DROPS would change the END TRACE recount. Case-insensitive, as the checker is.
# A facet text follows its head word, so none of the -Head rules can reach it.
function Test-TraceText([string] $Text, [string] $What, [switch] $Head) {
  if ([string]::IsNullOrWhiteSpace($Text)) { throw "Form A $What is empty" }
  if ($Text -match '[\r\n]') { throw "Form A $What must not contain a line break: $Text" }
  if ($Text -match ' @| \[| -- ') { throw "Form A $What must not contain ' @', ' [' or ' -- ': $Text" }
  # a trailing ' --' becomes ' -- ' before the anchor or note (the parser then reads the rest as a note);
  # a leading '--' makes the checker strip the whole line as a comment
  if ($Text -match ' --$' -or $Text -match '^--') { throw "Form A $What must not begin with '--' or end with ' --': $Text" }
  if ($Text -match '^(USER|CLIENT|SERVER|DATABASE) ') { throw "Form A $What must not begin with an actor word (pass -Actor): $Text" }
  if ($Text -match '^(CROSSES|STOPS) ') { throw "Form A $What must not begin with CROSSES or STOPS (pass -Kind): $Text" }
  if (-not $Head) { return }
  if ($Text -match '^(USER|CLIENT|SERVER|DATABASE|CROSSES|STOPS)(\s|$)') { throw "Form A $What must not be or begin with an actor or kind word (pass -Actor / -Kind): $Text" }
  if ($Text -match '^(WHEN|UNLESS|GUARD|UNRESOLVED)(\s|$)') { throw "Form A $What must not begin with a counted head word (WHEN UNLESS GUARD UNRESOLVED): $Text" }
  if ($Text -match '^(WRITE|READ|RESPONSE|ANCHOR|ALSO|USER|CLIENT|SERVER|DATABASE|PIPE)\s+(STOPS|CROSSES)(\s|$)') { throw "Form A $What must not be a section word before STOPS / CROSSES: $Text" }
  if ($Text -match '^[\[@]') { throw "Form A $What must not begin with '[' or '@' (the checker drops an annotation token): $Text" }
}

# A quoted header or condition is written VERBATIM (P16), so it cannot carry a double-quote.
function Test-TraceTitle([string] $Title) {
  if ($Title.Contains('"')) { throw "Form A title carries a double-quote, so it cannot be quoted verbatim: $Title" }
}

# Kind: step | stops | crosses. Anchor is '<file leaf>:<line>' without the '@' --
# REQUIRED for every kind (AC-11), a CROSSES anchors at the send line.
function New-TraceStep([string] $Kind, [string] $Text, [string] $Anchor, [string] $Grade = '', [string] $Routine = '',
                       [string] $Note = '', [string] $Ask = '', [string] $Actor = '') {
  if ($Kind -notin 'step', 'stops', 'crosses') { throw "New-TraceStep: kind '$Kind' is not step/stops/crosses" }
  if ($Anchor -notmatch $script:FormAAnchor) { throw "New-TraceStep: '$Text' has no anchor '<file>:<line>' (AC-11: every step carries one); got '$Anchor'" }
  if ($Grade -notin '', 'by name', 'inferred') { throw "New-TraceStep: grade '$Grade' is not ''/'by name'/'inferred'" }
  if ($Actor -and $Actor -cnotin $script:FormAActors) { throw "New-TraceStep: actor '$Actor' is not USER/CLIENT/SERVER/DATABASE" }
  Test-TraceText $Text 'step text' -Head
  [pscustomobject]@{ Kind = $Kind; Number = 0; Actor = $Actor; Text = $Text; Grade = $Grade; Anchor = $Anchor
                     Routine = $Routine; Note = $Note; Ask = $Ask; Children = (New-Object System.Collections.ArrayList) }
}

# The condition is kept VERBATIM; one carrying a double-quote or a line break is refused (see the header).
# $Routine: set when the condition hangs on a step of ANOTHER routine (a CALLS step), so it does not
# read as the callee's -- written as the note's `in <Routine>` part (Task 5 ruling T5-R2).
function New-TraceCond([string] $Keyword, [string] $Condition, [string] $Anchor, [string] $Note = '', [string] $Ask = '', [string] $Routine = '') {
  if ($Keyword -cnotin $script:FormAConds) { throw "New-TraceCond: '$Keyword' is not WHEN/UNLESS" }
  if ($Anchor -notmatch $script:FormAAnchor) { throw "New-TraceCond: '$Condition' has no anchor; got '$Anchor'" }
  if ([string]::IsNullOrWhiteSpace($Condition)) { throw 'New-TraceCond: empty condition' }
  if ($Condition.Contains('"')) { throw "New-TraceCond: the condition carries a double-quote, so it cannot be quoted verbatim: $Condition" }
  if ($Condition -match '[\r\n]') { throw "New-TraceCond: the condition must not contain a line break (join a wrapped condition first): $Condition" }
  [pscustomobject]@{ Kind = 'cond'; Keyword = $Keyword; Condition = $Condition; Anchor = $Anchor; Note = $Note; Ask = $Ask; Routine = $Routine }
}

function New-TraceFacet([string] $Head, [string] $Text, [string] $Anchor = '', [string] $Note = '') {
  if ($Head -cnotin $script:FormAFacets) { throw "New-TraceFacet: '$Head' is not a facet head ($($script:FormAFacets -join '/'))" }
  if ($Anchor -and $Anchor -notmatch $script:FormAAnchor) { throw "New-TraceFacet: bad anchor '$Anchor'" }
  Test-TraceText $Text 'facet text'
  [pscustomobject]@{ Kind = 'facet'; Head = $Head; Text = $Text; Anchor = $Anchor; Note = $Note; Ask = '' }
}

# Recomputed from the items, never stored (AC-3).
function Get-TraceCounts($Trace) {
  $s = 0; $c = 0; $x = 0; $u = 0
  foreach ($sec in $Trace.Sections) {
    foreach ($i in $sec.Items) {
      $s++
      if ($i.Kind -eq 'crosses') { $x++ }
      if ($i.Kind -eq 'stops')   { $u++ }
      foreach ($ch in $i.Children) { if ($ch.Kind -eq 'cond') { $c++ } }
    }
  }
  [pscustomobject]@{ Steps = $s; Conditions = $c; Crossings = $x; Unresolved = $u }
}

function Get-TraceAnchors($Trace) {
  $n = 0
  foreach ($sec in $Trace.Sections) {
    foreach ($i in $sec.Items) {
      if ($i.Anchor) { $n++ }
      foreach ($ch in $i.Children) { if ($ch.Anchor) { $n++ } }
    }
  }
  $n
}

function Format-TraceNote([string] $Routine, [string] $Note, [string] $Ask) {
  $parts = @()
  if ($Routine) {
    if ($Routine -notmatch '^[^\s;]+$') { throw "Form A routine must be one word with no ';': $Routine" }
    $parts += "in $Routine"
  }
  if ($Note) {
    if ($Note -match '[\r\n]') { throw "Form A note must not contain a line break: $Note" }
    if ($Note.Contains('; ')) { throw "Form A note must not contain '; ' (it is the note separator): $Note" }
    if ($Note -match '^in \S+$' -or $Note -match '^ask \S+$') { throw "Form A note must not read like a routine or ask part: $Note" }
    $parts += $Note
  }
  if ($Ask) {
    if ($Ask -notmatch '^[^\s;]+$') { throw "Form A ask must be one word with no ';': $Ask" }
    $parts += "ask $Ask"
  }
  $parts -join '; '
}

function Split-TraceNote([string] $Note) {
  $rn = ''; $ask = ''; $rest = @()
  $first = $true
  foreach ($p in @($Note -split '; ' | Where-Object { $_ -ne '' })) {
    if ($first -and $p -match '^in (\S+)$') { $rn = $Matches[1] }
    elseif ($p -match '^ask (\S+)$') { $ask = $Matches[1] }
    else { $rest += $p }
    $first = $false
  }
  # NO unary comma: the caller destructures `$rn, $nt, $ask = Split-TraceNote ...`, and a
  # comma-wrapped array lands whole in $rn (measured: routine ' DataBinding.FieldName ')
  @($rn, ($rest -join '; '), $ask)
}

# The canonical text. Numbers the steps in place (1..n across the whole script),
# recomputes the END TRACE counts, and refuses a byte outside 0x20-0x7E/CR/LF.
function Write-FormA($Trace) {
  $sb = New-Object System.Text.StringBuilder
  $L = { param($s) [void]$sb.Append($s).Append("`r`n") }
  foreach ($k in 'Name', 'Title', 'From', 'Index', 'AsOf', 'Regenerate', 'Tiers') {
    if ([string]::IsNullOrWhiteSpace([string]$Trace.$k)) { throw "Write-FormA: header $k is empty" }
    if ([string]$Trace.$k -match '[\r\n]') { throw "Write-FormA: header $k contains a line break" }
  }
  if ([string]$Trace.AsOf -match '\s') { throw "Write-FormA: header AsOf must be one word (the parser reads 'AS OF <word>'): $($Trace.AsOf)" }
  Test-TraceTitle ([string]$Trace.Title)   # again here: Title is a settable property
  & $L "TRACE $($Trace.Name)"
  & $L "  TITLE `"$($Trace.Title)`""
  & $L "  FROM $($Trace.From)"
  & $L "  INDEX $($Trace.Index) AS OF $($Trace.AsOf)"
  & $L "  REGENERATE $($Trace.Regenerate)"
  & $L "  TIERS $($Trace.Tiers)"
  $n = 0
  foreach ($sec in $Trace.Sections) {
    & $L ''
    & $L $sec.Name
    if ($sec.Note) {
      if ($sec.Items.Count) { throw "Write-FormA: section $($sec.Name) has steps AND a note -- a note stands only for an empty section" }
      if ($sec.Note -match '[\r\n]') { throw "Write-FormA: section $($sec.Name) note contains a line break" }
      & $L "  -- $($sec.Note)"
    }
    foreach ($i in $sec.Items) {
      $n++; $i.Number = $n
      $head = ('[{0:00}] ' -f $n) + $(if ($i.Actor) { "$($i.Actor) " } else { '' })
      $note = Format-TraceNote $i.Routine $i.Note $i.Ask
      $tail = " @$($i.Anchor)" + $(if ($note) { " -- $note" } else { '' })
      switch ($i.Kind) {
        'crosses' { & $L ($head + "CROSSES $($i.Text)" + $tail) }
        'stops'   { & $L ($head + "STOPS $($i.Text)" + $tail) }
        default   { & $L ($head + $i.Text + $(if ($i.Grade) { " [$($i.Grade)]" } else { '' }) + $tail) }
      }
      foreach ($ch in $i.Children) {
        $cn = Format-TraceNote $(if ($ch.Kind -eq 'cond') { $ch.Routine } else { '' }) $ch.Note $ch.Ask
        if ($ch.Kind -eq 'cond') {
          # verbatim: no truncation, no quote rewriting (New-TraceCond refused a '"' already)
          & $L ("       $($ch.Keyword) `"$($ch.Condition)`" @$($ch.Anchor)" + $(if ($cn) { " -- $cn" } else { '' }))
        } else {
          & $L ("       $($ch.Head) $($ch.Text)" + $(if ($ch.Anchor) { " @$($ch.Anchor)" } else { '' }) + $(if ($cn) { " -- $cn" } else { '' }))
        }
      }
    }
  }
  $c = Get-TraceCounts $Trace
  & $L ''
  & $L "END TRACE  $($c.Steps) steps, $($c.Conditions) conditions, $($c.Crossings) crossings, $($c.Unresolved) unresolved."
  $text = $sb.ToString()
  $bad = [regex]::Match($text, '[^\x0D\x0A\x20-\x7E]')
  if ($bad.Success) {
    $lineNo = ($text.Substring(0, $bad.Index) -split "\r\n").Count
    throw "Form A text is not 7-bit ASCII: byte 0x$(([int][char]$bad.Value).ToString('X2')) at line $lineNo (offset $($bad.Index))"
  }
  $text
}

# Reads the canonical layout back into a model. Any line it cannot place is an
# error (never a partial model), and the END TRACE counts must recompute.
# Case-SENSITIVE throughout: the keywords are upper case, and a text that
# happens to start with 'stops' is text, not a kind.
function Read-FormA([string] $Text) {
  if ($Text -match '(?<!\r)\n') { throw 'Read-FormA: bare LF (E-EOL)' }
  if (-not $Text.EndsWith("`r`n")) { throw 'Read-FormA: the last line does not end in CRLF (E-EOL)' }
  $lines = $Text -split "\r\n"
  $lines = $lines[0..($lines.Count - 2)]
  $rxStep  = '^\[(\d{2,3})\] (?:(USER|CLIENT|SERVER|DATABASE) )?(?:(CROSSES|STOPS) )?(.*?)(?: \[(by name|inferred)\])?(?: @(\S+))?(?: -- (.*))?$'
  $rxCond  = '^       (WHEN|UNLESS) "([^"]*)" @(\S+)(?: -- (.*))?$'
  $rxFacet = '^       (VIA|ONTO|AT|CONTRACT|FROM|TO|OVER|WITH) (.*?)(?: @(\S+))?(?: -- (.*))?$'
  $rxEnd   = '^END TRACE  (\d+) steps, (\d+) conditions, (\d+) crossings, (\d+) unresolved\.$'
  $T = New-Trace 'x' 'x' 'x' 'x' 'x' 'x' 'x'
  $sec = $null; $cur = $null; $counts = $null
  foreach ($raw in $lines) {
    if ($raw -eq '') { continue }
    if ($raw -cmatch '^TRACE (.+)$')        { $T.Name = $Matches[1]; continue }
    if ($raw -cmatch '^  TITLE "([^"]*)"$') { $T.Title = $Matches[1]; continue }
    if ($raw -cmatch '^  FROM (.+)$')       { $T.From = $Matches[1]; continue }
    if ($raw -cmatch '^  INDEX (.+) AS OF (\S+)$') { $T.Index = $Matches[1]; $T.AsOf = $Matches[2]; continue }
    if ($raw -cmatch '^  REGENERATE (.+)$') { $T.Regenerate = $Matches[1]; continue }
    if ($raw -cmatch '^  TIERS (.+)$')      { $T.Tiers = $Matches[1]; continue }
    if ($raw -cmatch $rxEnd) {
      $counts = [pscustomobject]@{ Steps = [int]$Matches[1]; Conditions = [int]$Matches[2]; Crossings = [int]$Matches[3]; Unresolved = [int]$Matches[4] }
      continue
    }
    if ($raw -cmatch '^[A-Z]+$') { $sec = Add-TraceSection $T $raw; $cur = $null; continue }
    if ($raw -cmatch '^  -- (.+)$' -and $sec -and -not $sec.Items.Count -and -not $sec.Note) { $sec.Note = $Matches[1]; continue }
    if ($raw -cmatch $rxStep) {
      $m = $Matches
      if (-not $sec) { throw "Read-FormA: a step before any section: $raw" }
      $kind = $(switch -CaseSensitive ([string]$m[3]) { 'CROSSES' { 'crosses' } 'STOPS' { 'stops' } default { 'step' } })
      $rn, $nt, $ask = Split-TraceNote ([string]$m[7])
      $cur = New-TraceStep $kind ([string]$m[4]) ([string]$m[6]) ([string]$m[5]) $rn $nt $ask ([string]$m[2])
      $cur.Number = [int]$m[1]
      [void]$sec.Items.Add($cur)
      continue
    }
    if ($raw -cmatch $rxCond) {
      $m = $Matches
      if (-not $cur) { throw "Read-FormA: a condition before any step: $raw" }
      $rn, $nt, $ask = Split-TraceNote ([string]$m[4])
      [void]$cur.Children.Add((New-TraceCond ([string]$m[1]) ([string]$m[2]) ([string]$m[3]) $nt $ask $rn))
      continue
    }
    if ($raw -cmatch $rxFacet) {
      $m = $Matches
      if (-not $cur) { throw "Read-FormA: a facet before any step: $raw" }
      $rn, $nt, $ask = Split-TraceNote ([string]$m[4])
      [void]$cur.Children.Add((New-TraceFacet ([string]$m[1]) ([string]$m[2]) ([string]$m[3]) $nt))
      continue
    }
    throw "Read-FormA: unparseable line: $raw"
  }
  if (-not $counts) { throw 'Read-FormA: no END TRACE line (E-NO-END)' }
  $rc = Get-TraceCounts $T
  foreach ($k in 'Steps', 'Conditions', 'Crossings', 'Unresolved') {
    if ($rc.$k -ne $counts.$k) { throw "Read-FormA: END TRACE $k declared $($counts.$k), recomputed $($rc.$k) (E-COUNTS)" }
  }
  $T
}
