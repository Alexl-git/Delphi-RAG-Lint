<#
  CliFlagVerbMap.ps1 -- derive, FROM SOURCE ALONE, which CLI flags each verb
  actually consumes.

  WHY THIS EXISTS
  ---------------
  CLAUDE.md's DOCS-IN-SYNC table promises, for `--help`:

      every verb the CLI accepts is listed; EVERY FLAG A VERB ACCEPTS IS
      LISTED ON THAT VERB'S LINE

  run_docs_sync_guard.ps1 check 1 enforces the first half. The second half had
  no truth source, and check 9's own header says so: ParseArgs is
  VERB-AGNOSTIC -- it fills one flat TArgs record for every verb, so nothing in
  the parser knows that --force32 belongs to index/query/lsp/serve. Check 9
  therefore polices flags as SETS and records the per-verb axis as a follow-on.

  This module is that truth source. The chain it walks is entirely mechanical:

      flag   --(ParseArgs branch)-->  TArgs field
      field  --(AArgs.<Field> read)-->  routine
      routine --(Do<X>(AArgs) call)-->  verb entry routine   (transitively)
      verb entry routine --(Args.Command = '<verb>' dispatch)-->  verb

  IT DELIBERATELY DOES NOT USE THE INDEX. The obvious implementation is
  "ask drag-lint who reads TArgs.Force32", and it is a GHOST MEASUREMENT today:
  docs\INBOX-property-refs-never-resolve.md records that
  DRagLint.Core.Model.CallSiteRefKindSql is literally `kind = 'call'`, so a
  member-access ref never enters the resolve pass and never gets a
  refs.symbol_id. Measured there: a METHOD on a class resolved to 4 [certain]
  callers while a PROPERTY on the same class through the same receiver resolved
  to 0. A field read is the same shape. Fixing that needs a resolver-version
  bump and a call_edges design decision, both deferred; this module needs
  neither, because the text of one file already carries the whole chain.

  A TEXT SCAN CANNOT READ COMMENTS -- SO THIS ONE LEXES FIRST
  -----------------------------------------------------------
  This repo's own standing warning. A naive `AArgs\.(\w+)` sweep over
  DRagLint.CLI.pas is wrong three ways, and all three are LIVE in that file
  today, not hypothetical:

    * COMMENTS. ParseArgs' own comments discuss `Result.Edges` in prose
      ("deps-report reuses that same Result.Edges field") and quote
      args.push('--stdio'). Line 527 carries `{$IF expr}` inside a // comment.
    * STRING LITERALS. PrintHelp:892 prints the text `{$IFDEF}-resolved source`
      from inside a Writeln -- a directive scanner that runs before the string
      lexer opens a conditional that never closes and blanks the rest of the
      banner.
    * INACTIVE CONDITIONAL BRANCHES. CLI.pas:23773 is a real
      {$IFNDEF WIN64}/{$ELSE}/{$ENDIF}. Code the shipped Win64 binary never
      compiles must not contribute a (verb, flag) cell, or the guard demands
      documentation for a flag the product does not read.

  So Stage 1 is a Pascal lexer, Stage 2 resolves conditionals on ITS output,
  and nothing downstream ever sees a comment or a literal. Blanking preserves
  offsets and newlines, so every line number stays true.

  WHAT IT REFUSES TO GUESS
  ------------------------
  An {$IFDEF} on a symbol this module has no ruling for is NOT evaluated: BOTH
  branches are kept (a superset -- over-attribution, never a silent drop) and
  the directive is reported in .Unevaluated. Named, not dropped, exactly as the
  encoding guard treats its unscanned roots. $PascalDefined / $PascalUndefined
  below are the rulings, and they are deliberately short.

  Every derivation step also reports what it could NOT tie down -- flags that
  bind no TArgs field, fields no routine reads, verbs whose entry routine is
  not found. Those are printed by the caller, never swallowed.
#>

Set-StrictMode -Version Latest

# Conditional symbols this module rules on. The deployed engine is Win64
# (build\build_draglint_win64.bat), so WIN64/CPUX64 are on and the Win32 pair
# is off. Anything else is UNEVALUATED -- both branches kept and named.
$script:PascalDefined   = @('WIN64', 'CPUX64', 'MSWINDOWS', 'WIN32API')
$script:PascalUndefined = @('WIN32', 'CPUX86', 'LINUX', 'POSIX', 'MACOS', 'ANDROID', 'IOS')

# An ASSIGNMENT to a TArgs field, in any of the three shapes ParseArgs uses.
$script:ResultAssignRx = 'Result\.([A-Za-z_][A-Za-z0-9_]*)(?:\.[A-Za-z_][A-Za-z0-9_]*|\[[^\]]*\])*\s*:='

function ConvertTo-PascalProjections {
<#
  .SYNOPSIS
    Lex Pascal text into two offset-preserving projections.
  .DESCRIPTION
    Returns an object with two strings of the SAME LENGTH as the input:

      .NoComments  comments blanked, string literals KEPT
                   (the flag literals '--db' live in strings, so the
                   ParseArgs scan needs them)
      .Code        comments AND string literals blanked
                   (a field-read scan must not read `AArgs.Foo` out of a
                   Writeln; the banner is full of flag-shaped text)

    Blanked characters become spaces; CR and LF are preserved, so line and
    column numbers survive.

    Delphi comment rules, as the compiler applies them:
      { .. }   ends at the FIRST '}' -- brace comments do NOT nest
      {$ ..}   is a DIRECTIVE, not a comment: kept in both projections so
               Resolve-PascalConditionals can see it
      (* .. *) ends at '*)';  (*$ ..*) is likewise a directive
      // ..    ends at the line break
      '..'     a doubled '' inside a literal closes and reopens it, which the
               "end at the next quote" rule handles without a special case
#>
  param([Parameter(Mandatory)][string]$Text)

  $n  = $Text.Length
  $nc = New-Object char[] $n     # comments blanked, strings kept
  $cd = New-Object char[] $n     # comments and strings blanked
  $i  = 0

  while ($i -lt $n) {
    $ch = $Text[$i]

    # --- { ... } : comment unless it opens a directive ----------------------
    if ($ch -eq '{') {
      $isDirective = (($i + 1) -lt $n) -and ($Text[$i + 1] -eq '$')
      $j = $Text.IndexOf('}', $i)
      if ($j -lt 0) { $j = $n - 1 }
      for ($k = $i; $k -le $j; $k++) {
        if ($isDirective) { $nc[$k] = $Text[$k]; $cd[$k] = $Text[$k] }
        else {
          $c = $Text[$k]
          if ($c -eq "`r" -or $c -eq "`n") { $nc[$k] = $c; $cd[$k] = $c }
          else { $nc[$k] = ' '; $cd[$k] = ' ' }
        }
      }
      $i = $j + 1
      continue
    }

    # --- (* ... *) ----------------------------------------------------------
    if ($ch -eq '(' -and (($i + 1) -lt $n) -and ($Text[$i + 1] -eq '*')) {
      $isDirective = (($i + 2) -lt $n) -and ($Text[$i + 2] -eq '$')
      $j = $Text.IndexOf('*)', $i + 2)
      if ($j -lt 0) { $j = $n - 2 }
      $j = $j + 1
      for ($k = $i; $k -le $j; $k++) {
        if ($isDirective) { $nc[$k] = $Text[$k]; $cd[$k] = $Text[$k] }
        else {
          $c = $Text[$k]
          if ($c -eq "`r" -or $c -eq "`n") { $nc[$k] = $c; $cd[$k] = $c }
          else { $nc[$k] = ' '; $cd[$k] = ' ' }
        }
      }
      $i = $j + 1
      continue
    }

    # --- // to end of line --------------------------------------------------
    if ($ch -eq '/' -and (($i + 1) -lt $n) -and ($Text[$i + 1] -eq '/')) {
      $k = $i
      while ($k -lt $n -and $Text[$k] -ne "`r" -and $Text[$k] -ne "`n") {
        $nc[$k] = ' '; $cd[$k] = ' '; $k++
      }
      $i = $k
      continue
    }

    # --- 'string literal' ---------------------------------------------------
    if ($ch -eq "'") {
      $j = $Text.IndexOf("'", $i + 1)
      if ($j -lt 0) { $j = $n - 1 }
      for ($k = $i; $k -le $j; $k++) {
        $c = $Text[$k]
        $nc[$k] = $c
        if ($c -eq "`r" -or $c -eq "`n") { $cd[$k] = $c } else { $cd[$k] = ' ' }
      }
      $i = $j + 1
      continue
    }

    $nc[$i] = $ch; $cd[$i] = $ch; $i++
  }

  return [pscustomobject]@{
    NoComments = (-join $nc)
    Code       = (-join $cd)
  }
}

function Resolve-PascalConditionals {
<#
  .SYNOPSIS
    Blank the branches the compiler would not compile.
  .DESCRIPTION
    Runs over the LEXER'S OUTPUT, never over raw text -- a {$IFDEF} printed by
    a Writeln or written in a comment must not steer this. Handles
    {$IFDEF}/{$IFNDEF}/{$ELSE}/{$ENDIF}/{$IFEND}, nested.

    A symbol with no ruling in $PascalDefined/$PascalUndefined, and every
    {$IF <expr>}, is UNEVALUATED: both branches are kept and the directive is
    returned in .Unevaluated. That over-attributes rather than dropping, and
    the caller prints it.
  .OUTPUTS
    .NoComments / .Code -- same two projections, inactive regions blanked
    .Unevaluated        -- the directives that got no ruling
#>
  param(
    [Parameter(Mandatory)][string]$NoComments,
    [Parameter(Mandatory)][string]$Code
  )

  $nc = $NoComments.ToCharArray()
  $cd = $Code.ToCharArray()
  $unevaluated = New-Object System.Collections.Generic.List[string]

  # Directives are located in the STRINGS-BLANKED projection, never in
  # NoComments. PrintHelp:892 prints the literal text `{$IFDEF}-resolved
  # source` from inside a Writeln; scanning NoComments reads that as a real
  # conditional with no matching {$ENDIF}, which unbalances the stack for the
  # remaining 25,000 lines. Offsets are identical across the two projections,
  # so a hit in Code blanks the same range in both.
  $scan = $Code

  # One entry per open conditional: Active = compile this branch?
  #                                 Decided = did we get a ruling at all?
  $stack = New-Object System.Collections.Generic.List[object]

  foreach ($m in [regex]::Matches($scan, '\{\$[^}]*\}')) {
    $body = $m.Value.Substring(2, $m.Value.Length - 3).Trim()
    $word = ($body -split '\s+', 2)[0].ToUpperInvariant()
    $rest = if ($body -match '^\S+\s+(.*)$') { $Matches[1].Trim() } else { '' }

    switch ($word) {
      'IFDEF' {
        $sym = $rest.ToUpperInvariant()
        if ($script:PascalDefined -contains $sym)        { $stack.Add(@{ Active = $true;  Decided = $true }) }
        elseif ($script:PascalUndefined -contains $sym)  { $stack.Add(@{ Active = $false; Decided = $true }) }
        else { $stack.Add(@{ Active = $true; Decided = $false }); $unevaluated.Add($m.Value) }
      }
      'IFNDEF' {
        $sym = $rest.ToUpperInvariant()
        if ($script:PascalDefined -contains $sym)        { $stack.Add(@{ Active = $false; Decided = $true }) }
        elseif ($script:PascalUndefined -contains $sym)  { $stack.Add(@{ Active = $true;  Decided = $true }) }
        else { $stack.Add(@{ Active = $true; Decided = $false }); $unevaluated.Add($m.Value) }
      }
      'IF'     { $stack.Add(@{ Active = $true; Decided = $false }); $unevaluated.Add($m.Value) }
      'ELSEIF' {
        if ($stack.Count -gt 0) { $top = $stack[$stack.Count - 1]; $top.Active = $true; $top.Decided = $false }
        $unevaluated.Add($m.Value)
      }
      'ELSE' {
        if ($stack.Count -gt 0) {
          $top = $stack[$stack.Count - 1]
          # An undecided conditional keeps BOTH arms; a decided one flips.
          if ($top.Decided) { $top.Active = -not $top.Active } else { $top.Active = $true }
        }
      }
      { $_ -eq 'ENDIF' -or $_ -eq 'IFEND' } {
        if ($stack.Count -gt 0) { $stack.RemoveAt($stack.Count - 1) }
      }
      default { }
    }

    # Blank the directive token itself, then -- if any enclosing conditional is
    # inactive -- everything up to the next directive.
    $inactive = $false
    foreach ($f in $stack) { if (-not $f.Active) { $inactive = $true } }

    $from = $m.Index
    $to   = if ($inactive) { $m.Index + $m.Length } else { $m.Index + $m.Length }
    for ($k = $from; $k -lt $to; $k++) {
      $c = $nc[$k]
      if ($c -ne "`r" -and $c -ne "`n") { $nc[$k] = ' '; $cd[$k] = ' ' }
    }
    if ($inactive) { $script:__pendingBlankFrom = $to } else { $script:__pendingBlankFrom = -1 }

    # Blank from here to the next directive when the region is dead.
    if ($inactive) {
      $next = $scan.IndexOf('{$', $m.Index + $m.Length)
      if ($next -lt 0) { $next = $nc.Length }
      for ($k = $m.Index + $m.Length; $k -lt $next; $k++) {
        $c = $nc[$k]
        if ($c -ne "`r" -and $c -ne "`n") { $nc[$k] = ' '; $cd[$k] = ' ' }
      }
    }
  }

  return [pscustomobject]@{
    NoComments  = (-join $nc)
    Code        = (-join $cd)
    Unevaluated = @($unevaluated | Sort-Object -Unique)
  }
}

function Get-CliFlagFieldMap {
<#
  .SYNOPSIS
    flag -> TArgs field(s), read off the ParseArgs chain.
  .DESCRIPTION
    ParseArgs is one flat `else if A = '<flag>' then Result.<Field>:= ...`
    chain -- the same shape check 1 relies on for verbs and check 9 for the
    accepted set. A branch RUNS FROM its flag line to the next flag line, so a
    multi-line begin/end body is captured whole (--rebuild sets two fields;
    --config sets ConfigPath AND WorkspaceConfig).

    A BRANCH ENDS AT THE NEXT `else` AT begin-DEPTH ZERO, not at the next flag
    line. The difference is not cosmetic and was measured: ten of the chain's
    branches are POSITIONAL, testing Result.Command rather than A, and they sit
    between flag branches (:392-:401 assign Result.Target/Position/SubCommand;
    :502 assigns Result.Path). Running a flag's body to the next flag line
    swallowed all ten -- and gave --dir, --in-place, --root and --unit to
    almost every verb in the product, including `rules` and `serve`, because
    Command/Target/Path are read everywhere. 1002 (verb, flag) cells, plausible
    on their face and wrong.

    Depth is needed because `begin` sits at the SAME indentation as `else`
    here (:440-:446), so indentation cannot separate them; the inner
    `else if Result.Command = 'query'` at :444 is a real part of --unit's body
    and must not terminate it.

    Two things it reports rather than hides:
      .NoField   flags that bind no TArgs field at all. --case-sensitive is
                 the live example: it sets a process-wide switch on
                 DRagLint.Storage.SQLite, so no verb can be derived for it.
      .Orphan    branches carrying no flag literal that assign Result.<Field>.
                 They are the positional-argument branches and are correctly
                 attributed to NO flag -- listed so that a future one landing
                 mid-chain is visible rather than silent.
#>
  param(
    [Parameter(Mandatory)][string]$ParseArgsNoComments,
    [Parameter(Mandatory)][string]$ParseArgsCode
  )

  $ncLines = $ParseArgsNoComments -split "`r?`n"
  $cdLines = $ParseArgsCode       -split "`r?`n"
  $flagRx  = "--[A-Za-z][A-Za-z0-9-]*"

  # A field is BOUND to a flag only where the branch ASSIGNS it. Matching a
  # bare `Result.X` counts the branch's own guard as a binding: every
  # command-guarded handler tests Result.Command, so --unit, --in-place,
  # --root and --dir each picked up Command and inherited every verb that
  # reads it. Measured: 970 cells with the read included, 776 with only
  # assignments. The shapes that occur are `Result.X:=`, `Result.X.Y:=`,
  # `Result.X[High(Result.X)]:=`; a plain comparison is a read and is skipped.
  #                        Result . field   (.sub | [index])*        :=

  # Pass 1: which lines OPEN a flag branch, and with which flags.
  $starts = @{}
  for ($i = 0; $i -lt $ncLines.Count; $i++) {
    $flags = @()
    foreach ($m in [regex]::Matches($ncLines[$i], "\bA\s*=\s*'($flagRx)'"))      { $flags += $m.Groups[1].Value }
    foreach ($m in [regex]::Matches($ncLines[$i], "A\.StartsWith\('($flagRx)'")) { $flags += $m.Groups[1].Value }
    if ($flags.Count -gt 0) { $starts[$i] = @($flags | Sort-Object -Unique) }
  }

  $startIdx = @($starts.Keys | Sort-Object)
  $map      = [ordered]@{}
  $noField  = New-Object System.Collections.Generic.List[string]
  $claimed  = New-Object System.Collections.Generic.HashSet[int]

  foreach ($from in $startIdx) {
    $fields = New-Object System.Collections.Generic.HashSet[string]
    $depth  = 0
    for ($i = $from; $i -lt $cdLines.Count; $i++) {
      if ($i -gt $from -and $depth -le 0 -and $cdLines[$i] -match '^\s*else\b') { break }
      [void]$claimed.Add($i)
      foreach ($m in [regex]::Matches($cdLines[$i], $script:ResultAssignRx)) {
        [void]$fields.Add($m.Groups[1].Value)
      }
      $depth += [regex]::Matches($cdLines[$i], '(?i)\b(begin|case|try|record)\b').Count
      $depth -= [regex]::Matches($cdLines[$i], '(?i)\bend\b').Count
    }

    foreach ($f in $starts[$from]) {
      if ($fields.Count -eq 0) { $noField.Add($f); continue }
      if (-not $map.Contains($f)) { $map[$f] = New-Object System.Collections.Generic.HashSet[string] }
      foreach ($x in $fields) { [void]$map[$f].Add($x) }
    }
  }

  # Lines no flag branch claimed that still write a TArgs field: the positional
  # branches. Reported, so that a flag handler accidentally written outside the
  # `A = '--x'` shape shows up here instead of vanishing.
  $orphan = New-Object System.Collections.Generic.List[string]
  for ($i = 0; $i -lt $cdLines.Count; $i++) {
    if ($claimed.Contains($i)) { continue }
    if ($cdLines[$i] -match '\belse\b' -and $cdLines[$i] -match $script:ResultAssignRx) {
      $orphan.Add(("line {0}: {1}" -f ($i + 1), $cdLines[$i].Trim()))
    }
  }

  return [pscustomobject]@{
    Map     = $map
    NoField = @($noField | Sort-Object -Unique)
    Orphan  = @($orphan)
  }
}

# Control-flow keywords that precede a parenthesised Args expression (`if
# (Args.X)`), and the RTL intrinsics that take one. They are not routines this
# unit declares, so they would be dropped by the closure anyway -- excluded
# here so the .Calls sets stay readable.
$script:NotACallee = @('if','and','or','not','while','until','case','then','do','to','downto','in','is','xor','div','mod','Length','Assigned','SizeOf','High','Low','Ord','Writeln','Write')

function Get-ArgsCallees {
<#
  .SYNOPSIS
    Routines a span hands the whole TArgs record to.
  .DESCRIPTION
    The negative lookbehind for '.' is LOAD-BEARING and was found by
    measurement, not by review. Without it, `TFbSnapshot.Run(AArgs.FbConnection,
    Store)` at CLI.pas:12021 reads as a call to Run -- the DISPATCHER -- and the
    transitive closure for fb-snapshot and link-orm swelled to 161 flags, i.e.
    every flag the CLI accepts, silently and plausibly. A qualified method call
    on a class is not a call to this unit's routine of the same name.
#>
  param([Parameter(Mandatory)][string]$Span, [string]$Self = '')
  $calls = New-Object System.Collections.Generic.HashSet[string]
  foreach ($m in [regex]::Matches($Span, '(?<![A-Za-z0-9_.])([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*(?:AArgs|Args)\b')) {
    $callee = $m.Groups[1].Value
    if ($callee -eq $Self) { continue }
    if ($script:NotACallee -contains $callee) { continue }
    [void]$calls.Add($callee)
  }
  return ,$calls
}

function Get-RoutineSpanRange {
<#
  .SYNOPSIS
    Offsets of the IMPLEMENTATION of one top-level routine.
  .DESCRIPTION
    Returns @{ Index; Length } for the first column-0 header of $Name whose
    span actually contains a body, or $null.

    "Whose span contains a body" is the whole point. DRagLint.CLI.pas declares
    `function Run: Integer;` twice -- at :86 in the interface and at :26606
    where it is implemented. Taking the first match yields a 0-arm span, and
    the failure is SILENT: the dispatch scan finds no verbs and every
    downstream set is legitimately empty, which is exactly what a healthy tree
    with nothing to report also looks like. ParseArgs has the same shape.
#>
  param([Parameter(Mandatory)][string]$Code, [Parameter(Mandatory)][string]$Name)
  $headers = @([regex]::Matches($Code, '(?m)^(?:procedure|function)\s+([A-Za-z_][A-Za-z0-9_]*)'))
  for ($h = 0; $h -lt $headers.Count; $h++) {
    if ($headers[$h].Groups[1].Value -ne $Name) { continue }
    $from = $headers[$h].Index
    $to   = if ($h + 1 -lt $headers.Count) { $headers[$h + 1].Index } else { $Code.Length }
    $span = $Code.Substring($from, $to - $from)
    if ($span -match '(?m)^begin\b') { return @{ Index = $from; Length = $to - $from } }
  }
  return $null
}

function Get-CliRoutineMap {
<#
  .SYNOPSIS
    Top-level routine -> the TArgs fields it reads and the routines it hands
    AArgs to.
  .DESCRIPTION
    A routine's span runs from its column-0 header to the next column-0
    header. That is the same "one specific code shape" bound check 1 states for
    the dispatch chain: nested (local) routines fall inside their enclosing
    span, which is correct -- a local proc reading AArgs.Depth is that
    routine's behaviour.

    Because comments are already blanked, a column-0 `function` written inside
    a doc block cannot open a phantom span.

    Forward declarations are skipped: their span carries no `begin`.
#>
  param([Parameter(Mandatory)][string]$Code)

  $headers = @([regex]::Matches($Code, '(?m)^(?:procedure|function)\s+([A-Za-z_][A-Za-z0-9_]*)'))
  $routines = [ordered]@{}

  for ($h = 0; $h -lt $headers.Count; $h++) {
    $name = $headers[$h].Groups[1].Value
    $from = $headers[$h].Index
    $to   = if ($h + 1 -lt $headers.Count) { $headers[$h + 1].Index } else { $Code.Length }
    $span = $Code.Substring($from, $to - $from)

    # A declaration with no body contributes nothing and must not swallow the
    # gap to the next header.
    if ($span -notmatch '(?m)^begin\b') { continue }

    $reads = New-Object System.Collections.Generic.HashSet[string]
    foreach ($m in [regex]::Matches($span, '\bAArgs\.([A-Za-z_][A-Za-z0-9_]*)')) { [void]$reads.Add($m.Groups[1].Value) }
    foreach ($m in [regex]::Matches($span, '(?<![A-Za-z0-9_.])Args\.([A-Za-z_][A-Za-z0-9_]*)')) { [void]$reads.Add($m.Groups[1].Value) }

    $calls = Get-ArgsCallees -Span $span -Self $name

    if ($routines.Contains($name)) {
      foreach ($x in $reads) { [void]$routines[$name].Reads.Add($x) }
      foreach ($x in $calls) { [void]$routines[$name].Calls.Add($x) }
    } else {
      $routines[$name] = [pscustomobject]@{ Reads = $reads; Calls = $calls }
    }
  }
  return $routines
}

function Get-CliVerbFlagMap {
<#
  .SYNOPSIS
    The whole chain: verb -> the flags that verb actually consumes.
  .PARAMETER CliPath
    src\cli\DRagLint.CLI.pas
  .OUTPUTS
    .VerbFlags   ordered verb -> sorted flag list
    .FlagFields  flag -> TArgs fields
    .FieldFlags  TArgs field -> flags
    .Global      fields read BEFORE dispatch (Run itself) -- cross-verb, so
                 their flags belong to no single verb line
    .NoField     flags binding no TArgs field  (named, not dropped)
    .NoReader    fields no routine reads       (named, not dropped)
    .NoEntry     verbs whose dispatch target could not be resolved
    .Unevaluated conditional directives that got no ruling
#>
  param([Parameter(Mandatory)][string]$CliPath)

  $raw  = [IO.File]::ReadAllText($CliPath)
  $lex  = ConvertTo-PascalProjections -Text $raw
  $res  = Resolve-PascalConditionals -NoComments $lex.NoComments -Code $lex.Code

  # --- flag -> field ---------------------------------------------------------
  # The span is delimited ON THE LEXED TEXT, header to next column-0 header --
  # the same rule Get-CliRoutineMap uses. check 9 anchors its own copy on
  # `end; // function`, which CANNOT work here: that terminator is a comment and
  # the lexer has already blanked it. Offsets are preserved by the lexer, so
  # NoComments and Code are sliced at the identical positions.
  $pa = Get-RoutineSpanRange -Code $res.Code -Name 'ParseArgs'
  if (-not $pa) { throw 'the ParseArgs implementation was not found in the lexed source' }
  $ff = Get-CliFlagFieldMap `
          -ParseArgsNoComments $res.NoComments.Substring($pa.Index, $pa.Length) `
          -ParseArgsCode       $res.Code.Substring($pa.Index, $pa.Length)

  $fieldFlags = @{}
  foreach ($flag in $ff.Map.Keys) {
    foreach ($fld in $ff.Map[$flag]) {
      if (-not $fieldFlags.ContainsKey($fld)) { $fieldFlags[$fld] = New-Object System.Collections.Generic.HashSet[string] }
      [void]$fieldFlags[$fld].Add($flag)
    }
  }

  # --- routine -> reads / calls ---------------------------------------------
  $routines = Get-CliRoutineMap -Code $res.Code

  # --- verb -> its dispatch ARM ---------------------------------------------
  # An arm runs from its `Args.Command = '<verb>'` test to the next one, and is
  # bounded by Run's own span. That treats the one-liner
  # `else if Args.Command = 'query' then Result:= DoQuery(Args)` and the four
  # MULTI-LINE arms identically. The multi-line shape is not an edge case: the
  # 'index' arm rejects --rebuild+--recompile inline before calling anything,
  # 'lsp' reads --parent-pid and the whole --proxy group inline, and 'serve'
  # reads --size-guard-mb inline. An entry-routine-only model scored all four
  # as unresolved and would have mapped none of those flags.
  #
  # Matched on NoComments: the verb name is a STRING LITERAL, so the
  # strings-blanked projection has nothing left to match.
  $run = Get-RoutineSpanRange -Code $res.Code -Name 'Run'
  if (-not $run) { throw 'the Run dispatcher implementation was not found in the lexed source' }
  $runBeg = $run.Index
  $runEnd = $run.Index + $run.Length

  $armHits = @([regex]::Matches($res.NoComments, "Args\.Command\s*=\s*'([a-z0-9-]+)'") |
                Where-Object { $_.Index -ge $runBeg -and $_.Index -lt $runEnd })
  $dispatch = [ordered]@{}
  $noEntry  = New-Object System.Collections.Generic.List[string]
  $armReads = @{}
  for ($a = 0; $a -lt $armHits.Count; $a++) {
    $verb = $armHits[$a].Groups[1].Value
    $from = $armHits[$a].Index
    $to   = if ($a + 1 -lt $armHits.Count) { $armHits[$a + 1].Index } else { $runEnd }
    $span = $res.Code.Substring($from, $to - $from)

    if (-not $dispatch.Contains($verb)) {
      $dispatch[$verb] = New-Object System.Collections.Generic.HashSet[string]
      $armReads[$verb] = New-Object System.Collections.Generic.HashSet[string]
    }
    foreach ($c in (Get-ArgsCallees -Span $span -Self 'Run')) { [void]$dispatch[$verb].Add($c) }
    foreach ($m in [regex]::Matches($span, '(?<![A-Za-z0-9_.])Args\.([A-Za-z_][A-Za-z0-9_]*)')) {
      [void]$armReads[$verb].Add($m.Groups[1].Value)
    }
  }
  foreach ($v in $dispatch.Keys) {
    if ($dispatch[$v].Count -eq 0 -and $armReads[$v].Count -le 1) { $noEntry.Add($v) }
  }

  # --- transitive closure of reads from each entry routine ------------------
  function Get-Closure([string]$Start, $Routines) {
    $seen = New-Object System.Collections.Generic.HashSet[string]
    $todo = New-Object System.Collections.Generic.Stack[string]
    $todo.Push($Start)
    $fields = New-Object System.Collections.Generic.HashSet[string]
    while ($todo.Count -gt 0) {
      $r = $todo.Pop()
      if (-not $seen.Add($r)) { continue }
      if (-not $Routines.Contains($r)) { continue }
      foreach ($f in $Routines[$r].Reads) { [void]$fields.Add($f) }
      foreach ($c in $Routines[$r].Calls) { if (-not $seen.Contains($c)) { $todo.Push($c) } }
    }
    return $fields
  }

  # Fields Run reads BEFORE the first dispatch arm are cross-verb plumbing
  # (--db resolution, --platform, --help/--version, the manifest). They belong
  # to no single verb line, so they are reported separately and never demanded
  # of one verb. Taking ALL of Run's reads would be wrong: the four multi-line
  # arms read --parent-pid, --proxy and --size-guard-mb INSIDE Run, and those
  # are lsp's and serve's, not everybody's.
  $global = New-Object System.Collections.Generic.HashSet[string]
  $preEnd = if ($armHits.Count -gt 0) { $armHits[0].Index } else { $runEnd }
  $preSpan = $res.Code.Substring($runBeg, $preEnd - $runBeg)
  foreach ($m in [regex]::Matches($preSpan, '(?<![A-Za-z0-9_.])Args\.([A-Za-z_][A-Za-z0-9_]*)')) {
    [void]$global.Add($m.Groups[1].Value)
  }
  foreach ($c in (Get-ArgsCallees -Span $preSpan -Self 'Run')) {
    foreach ($f in (Get-Closure -Start $c -Routines $routines)) { [void]$global.Add($f) }
  }

  $verbFlags = [ordered]@{}
  foreach ($verb in @($dispatch.Keys | Sort-Object)) {
    $fields = New-Object System.Collections.Generic.HashSet[string]
    foreach ($f in $armReads[$verb]) { [void]$fields.Add($f) }
    foreach ($entry in $dispatch[$verb]) {
      foreach ($f in (Get-Closure -Start $entry -Routines $routines)) { [void]$fields.Add($f) }
    }
    $flags = New-Object System.Collections.Generic.HashSet[string]
    foreach ($f in $fields) {
      if ($fieldFlags.ContainsKey($f)) { foreach ($x in $fieldFlags[$f]) { [void]$flags.Add($x) } }
    }
    $verbFlags[$verb] = @($flags | Sort-Object)
  }

  # --- fields nothing reads --------------------------------------------------
  $allRead = New-Object System.Collections.Generic.HashSet[string]
  foreach ($r in $routines.Keys) { foreach ($f in $routines[$r].Reads) { [void]$allRead.Add($f) } }
  $noReader = @($fieldFlags.Keys | Where-Object { -not $allRead.Contains($_) } | Sort-Object)

  return [pscustomobject]@{
    VerbFlags   = $verbFlags
    FlagFields  = $ff.Map
    FieldFlags  = $fieldFlags
    Routines    = $routines
    Dispatch    = $dispatch
    Global      = @($global | Sort-Object)
    NoField     = $ff.NoField
    NoReader    = $noReader
    Orphan      = $ff.Orphan
    NoEntry     = @($noEntry | Sort-Object -Unique)
    Unevaluated = $res.Unevaluated
  }
}

function Get-CliVerbSubcommandMap {
<#
  .SYNOPSIS
    verb -> the SUBcommands that verb actually accepts, derived from source.
  .DESCRIPTION
    THE AXIS run_docs_sync_guard.ps1 CHECK 1 CANNOT SEE. Check 1 enumerates
    TOP-LEVEL verbs only: it matches `Args.Command = 'x'` in Run and
    `^  drag-lint <verb>` in the banner. `query` is in both, so check 1 passes
    while `query descendants` -- a shipping subcommand -- appears ZERO times in
    --help. That is the founding DOCS-IN-SYNC failure ("four shipping verbs
    missing from --help") repeating one level down, inside the guard written to
    prevent it.

    THE BINDING RULE, and why it is not a flat harvest. A subcommand literal
    belongs to the verb whose dispatch closure reaches the routine the literal
    sits in -- the same verb -> arm -> entry-routine -> transitive-callee walk
    Get-CliVerbFlagMap uses for flags. A flat `SubCommand = 'x'` harvest over
    the whole unit cannot tell `query`'s eight from `selftest`'s fifteen, and
    would demand that --help document the self-test dispatcher's internals.

    TWO SHAPES ARE DELIBERATELY EXCLUDED, both measured on the live source:

      * `Result.SubCommand` -- the PARSER side. ParseArgs WRITES the field
        (:1161 `Result.SubCommand:= A`) and one guard reads it back
        (:1483, the `workspace add` positional-target rule). Those are how the
        value is produced, not which verb accepts it; counting them would put
        'add' in the pre-dispatch GLOBAL set, belonging to every verb.
      * anything inside a comment -- :1253 is prose that literally reads
        "Its guards tested Result.SubCommand". The caller passes the LEXED
        projection, so comments are already blanked; this note records WHY that
        matters here rather than leaving the next reader to rediscover it.

    A verb with no subcommand literal in its closure is absent from the result
    (not present-with-an-empty-list), so a consumer can distinguish "takes no
    subcommands" from "takes some" without a second lookup.
  .PARAMETER CliPath
    src\cli\DRagLint.CLI.pas
  .OUTPUTS
    .VerbSubs   ordered verb -> sorted subcommand list (verbs with none omitted)
    .All        every subcommand literal found, whatever verb it bound to
    .Unbound    literals in no verb's closure -- named, never silently dropped
#>
  param([Parameter(Mandatory)][string]$CliPath)

  $raw = [IO.File]::ReadAllText($CliPath)
  $lex = ConvertTo-PascalProjections -Text $raw
  $res = Resolve-PascalConditionals -NoComments $lex.NoComments -Code $lex.Code

  # Reader side only: AArgs.SubCommand / Args.SubCommand, never Result.SubCommand.
  # Two patterns for the same reason Get-CliRoutineMap uses two: the lookbehind
  # that keeps `Args.` from matching inside `AArgs.` also keeps it from matching
  # `AArgs.` at all.
  $subRx = [regex]"(?:\bAArgs|(?<![A-Za-z0-9_.])Args)\.SubCommand\s*(?:=|<>)\s*'([a-z0-9][a-z0-9-]*)'"

  # --- routine -> the subcommand literals in its own span --------------------
  $headers  = @([regex]::Matches($res.Code, '(?m)^(?:procedure|function)\s+([A-Za-z_][A-Za-z0-9_]*)'))
  $perRoutine = @{}
  $all = New-Object System.Collections.Generic.HashSet[string]
  for ($h = 0; $h -lt $headers.Count; $h++) {
    $name = $headers[$h].Groups[1].Value
    $from = $headers[$h].Index
    $to   = if ($h + 1 -lt $headers.Count) { $headers[$h + 1].Index } else { $res.Code.Length }
    $span = $res.Code.Substring($from, $to - $from)
    if ($span -notmatch '(?m)^begin\b') { continue }   # forward decl: no body
    # Span DETECTION on Code (strings blanked, so a `begin` inside a literal
    # cannot open a phantom body); literal HARVEST on NoComments, where the
    # subcommand strings still exist. The projections are offset-preserving,
    # so the identical slice reads both.
    foreach ($m in $subRx.Matches($res.NoComments.Substring($from, $to - $from))) {
      if (-not $perRoutine.ContainsKey($name)) { $perRoutine[$name] = New-Object System.Collections.Generic.HashSet[string] }
      [void]$perRoutine[$name].Add($m.Groups[1].Value)
      [void]$all.Add($m.Groups[1].Value)
    }
  }

  # --- verb -> dispatch arm -> entry routines --------------------------------
  $run = Get-RoutineSpanRange -Code $res.Code -Name 'Run'
  if (-not $run) { throw 'the Run dispatcher implementation was not found in the lexed source' }
  $runBeg = $run.Index
  $runEnd = $run.Index + $run.Length

  $armHits = @([regex]::Matches($res.NoComments, "Args\.Command\s*=\s*'([a-z0-9-]+)'") |
                Where-Object { $_.Index -ge $runBeg -and $_.Index -lt $runEnd })
  $dispatch = [ordered]@{}
  for ($a = 0; $a -lt $armHits.Count; $a++) {
    $verb = $armHits[$a].Groups[1].Value
    $from = $armHits[$a].Index
    $to   = if ($a + 1 -lt $armHits.Count) { $armHits[$a + 1].Index } else { $runEnd }
    $span = $res.Code.Substring($from, $to - $from)
    if (-not $dispatch.Contains($verb)) { $dispatch[$verb] = New-Object System.Collections.Generic.HashSet[string] }
    foreach ($c in (Get-ArgsCallees -Span $span -Self 'Run')) { [void]$dispatch[$verb].Add($c) }
    # A one-line arm may compare SubCommand inline rather than in a Do<Verb>.
    foreach ($m in $subRx.Matches($res.NoComments.Substring($from, $to - $from))) {
      if (-not $perRoutine.ContainsKey("Run:$verb")) { $perRoutine["Run:$verb"] = New-Object System.Collections.Generic.HashSet[string] }
      [void]$perRoutine["Run:$verb"].Add($m.Groups[1].Value)
      [void]$all.Add($m.Groups[1].Value)
    }
  }

  $routines = Get-CliRoutineMap -Code $res.Code

  # --- transitive closure, collecting subcommands instead of fields ----------
  function Get-SubClosure([string]$Start, $Routines, $PerRoutine) {
    $seen = New-Object System.Collections.Generic.HashSet[string]
    $todo = New-Object System.Collections.Generic.Stack[string]
    $todo.Push($Start)
    $subs = New-Object System.Collections.Generic.HashSet[string]
    while ($todo.Count -gt 0) {
      $r = $todo.Pop()
      if (-not $seen.Add($r)) { continue }
      if ($PerRoutine.ContainsKey($r)) { foreach ($s in $PerRoutine[$r]) { [void]$subs.Add($s) } }
      if (-not $Routines.Contains($r)) { continue }
      foreach ($c in $Routines[$r].Calls) { if (-not $seen.Contains($c)) { $todo.Push($c) } }
    }
    return $subs
  }

  $verbSubs = [ordered]@{}
  $bound    = New-Object System.Collections.Generic.HashSet[string]
  foreach ($verb in @($dispatch.Keys | Sort-Object)) {
    $subs = New-Object System.Collections.Generic.HashSet[string]
    if ($perRoutine.ContainsKey("Run:$verb")) { foreach ($s in $perRoutine["Run:$verb"]) { [void]$subs.Add($s) } }
    foreach ($entry in $dispatch[$verb]) {
      foreach ($s in (Get-SubClosure -Start $entry -Routines $routines -PerRoutine $perRoutine)) { [void]$subs.Add($s) }
    }
    if ($subs.Count -gt 0) {
      $verbSubs[$verb] = @($subs | Sort-Object)
      foreach ($s in $subs) { [void]$bound.Add($s) }
    }
  }

  return [pscustomobject]@{
    VerbSubs = $verbSubs
    All      = @($all | Sort-Object)
    Unbound  = @($all | Where-Object { -not $bound.Contains($_) } | Sort-Object)
  }
}
