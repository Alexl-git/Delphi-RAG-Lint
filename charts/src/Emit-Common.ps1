<#
  Emit-Common.ps1 -- shared helpers, DOT-SOURCED by the emitters. Functions only,
  no top-level side effects: dot-sourcing this must never write a file, call the
  engine, or print.

  Dot-sourcing puts these functions in the CALLER's scope, so they resolve
  $Engine, $Dot and $DbPath dynamically from the emitter's own param block.
  That is deliberate -- it keeps the call sites short -- but it means an emitter
  MUST declare all three parameters with those exact names.

  Two traps are baked in here rather than left to each emitter:

  1. `--format json` splices a human staleness note INTO the JSON stream, and
     with 2>&1 it lands inside the document and breaks ConvertFrom-Json. Every
     engine call is routed through Get-EngineText, which drops ErrorRecords and
     `drag-lint:` lines before anything tries to parse.

  2. The engine emits BOTH shapes: reverse-calltree returns an OBJECT `{...}`
     and `query find-callers --json` returns a bare ARRAY `[...]`. Trimming to
     the first `{` (as an earlier draft did) silently corrupts the array into an
     object followed by garbage. Get-EngineText brackets on whichever of `{` or
     `[` comes FIRST and pairs it with the matching closer.
#>

# NOTE: deliberately NO Set-StrictMode here. Dot-sourcing runs in the CALLER's
# scope, so setting it would silently change the strictness of every emitter --
# exactly the top-level side effect this file is supposed to be free of.

# ---- text -------------------------------------------------------------------

function ConvertTo-XmlText([string] $s) {
  if ($null -eq $s) { return '' }
  $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
}

function Get-UnitName([string] $file) {
  if ([string]::IsNullOrWhiteSpace($file)) { return '(unknown)' }
  [IO.Path]::GetFileNameWithoutExtension($file)
}

function Get-ShortName([string] $qname, [string] $unit) {
  if ([string]::IsNullOrWhiteSpace($qname)) { return '' }
  if ($unit -and $qname.StartsWith("$unit.", [StringComparison]::OrdinalIgnoreCase)) {
    return $qname.Substring($unit.Length + 1)
  }
  $qname
}

function New-RowHref([string] $File, [int] $Line) {
  'draglint://open?file=' + [uri]::EscapeDataString($File) + '&amp;line=' + $Line
}

# ---- database safety ---------------------------------------------------------

# Resolve a database path and REFUSE a live corpus DB.
#
# WHY THIS EXISTS -- and what it is NOT about
# -------------------------------------------
# On 2026-09-23 at 05:30 the engine team reindexed the corpus to
# v=1.17.0-alpha / r=1.6.0-alpha. The engine deployed in this worktree is
# 1.16.0-alpha with resolver 1.5.1-alpha -- OLDER on two axes -- and
# RefuseIfEngineOlderThanDb does not cover the resolver axis, so nothing
# refuses. The skew yields SMALLER CONFIDENT ANSWERS, never an error.
#
# This guard is NOT about corruption. Reads are proven safe: only `index`
# re-resolves, and a full day of reads left both DBs still on r=1.6.0-alpha.
# It exists for two things a habit produces:
#
#   * a live DB is opened RW by some verbs and fails `database is locked`
#     against a WAL writer, which reads as an emitter bug rather than as
#     contention;
#   * a live DB can be re-indexed underneath a run, so an asserted count stops
#     being reproducible. The clones FREEZE the numbers the suite asserts --
#     which is the whole reason the 9 known-red assertions are evidence.
#
# It is a WHITELIST of the clone root, not a blacklist of known corpus paths.
# A blacklist would not know about a new project's DB, and the miss would be
# silent -- the exact failure mode this project exists to prevent.
#
# $PSScriptRoot resolves in the CALLER's scope (see the file header), which is
# charts\src for every emitter and for the test harness, so the clone root is
# always its sibling scratch\db.
#
# The override is an ENVIRONMENT VARIABLE on purpose: a parameter can be passed
# by habit, and "by habit" is precisely what is being guarded against.
#
# THE SUFFIX RULE (N35, controller ruling R3, 2026-09-23). The clone root also
# holds HISTORY: `*.sqlite.pre-1.18` and `*.sqlite.pre-reindex-0530` are
# byte-for-byte older clones kept for comparison. They sit under the root, so the
# whitelist alone ACCEPTS them -- and a 562-file pre-1.18 CLIENT answers every
# query confidently with the older parse. The file name must END in `.sqlite`.
# This is checked BEFORE the live-DB override on purpose: the override exists to
# reach a live corpus DB, never to reach a history copy.
function Get-CloneDb([string] $Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Get-CloneDb: no database path given' }

  $root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\scratch\db'))

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "database not found: $Path (clones live in $root)"
  }
  $full = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).ProviderPath)

  if (-not $full.EndsWith('.sqlite', [StringComparison]::OrdinalIgnoreCase)) {
    throw ("refusing a database whose name does not end in .sqlite: $full -- the clone root keeps " +
           'history copies (*.sqlite.pre-1.18, *.sqlite.pre-reindex-0530) beside the live clones, and ' +
           'they answer with an OLDER parse. Point at the *.sqlite clone itself.')
  }

  if ($full.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    return $full
  }

  if ($env:DRAGLINT_CHARTS_ALLOW_LIVE_DB -eq '1') {
    Write-Host "  NOTE: DRAGLINT_CHARTS_ALLOW_LIVE_DB=1 -- using a NON-CLONE database: $full"
    return $full
  }

  throw ("refusing a non-clone database: $full -- charts run against the clones in $root. " +
         'The deployed engine (1.16.0-alpha / resolver 1.5.1-alpha) is OLDER than the indexed ' +
         'corpus (v=1.17.0-alpha / r=1.6.0-alpha), and a live DB can be re-indexed mid-run, so ' +
         'an asserted count would not be reproducible. Set DRAGLINT_CHARTS_ALLOW_LIVE_DB=1 to ' +
         'override deliberately once the engine has been redeployed.')
}

# ---- engine -----------------------------------------------------------------

# Runs the engine and returns ONLY the JSON document, or '' when there is none.
# Records the exit code in $script:LastEngineExit for the caller's message.
function Get-EngineText([string[]] $ArgList) {
  $raw = & $Engine @ArgList 2>&1 |
         Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } |
         Where-Object {
           $s = [string]$_
           $s -notmatch '^\(?loaded defaults' -and
           $s -notmatch '^drag-lint:'         -and
           $s -notmatch '^\s+may be stale'    -and
           $s -notmatch '^\s+drag-lint index ' -and
           # The resolver-mismatch note, emitted when the index was resolved by a
           # NEWER build than this engine. It goes to stderr, so the ErrorRecord
           # filter above already catches it -- this line is belt and braces for
           # a host that merges the streams, because when it does reach the
           # document the failure is an opaque ConvertFrom-Json error a long way
           # from its cause.
           $s -notmatch '^\s*resolver:'
         }
  $script:LastEngineExit = $LASTEXITCODE
  $txt = ($raw -join "`n")
  if ([string]::IsNullOrWhiteSpace($txt)) { return '' }

  # bracket on whichever opener comes first -- see header note 2
  $bo = $txt.IndexOf('{')
  $ba = $txt.IndexOf('[')
  if ($bo -lt 0 -and $ba -lt 0) { return '' }
  if ($bo -lt 0) { $open = $ba } elseif ($ba -lt 0) { $open = $bo } else { $open = [Math]::Min($bo, $ba) }
  $close = if ($txt[$open] -eq '[') { $txt.LastIndexOf(']') } else { $txt.LastIndexOf('}') }
  if ($close -le $open) { return '' }
  $txt.Substring($open, $close - $open + 1)
}

function Invoke-EngineJson([string[]] $ArgList) {
  $txt = Get-EngineText $ArgList
  if ([string]::IsNullOrWhiteSpace($txt)) {
    throw "engine returned nothing for $($ArgList -join ' ') (exit $script:LastEngineExit)"
  }
  $txt | ConvertFrom-Json
}

# schema sql/1 returns `columns` (name/type) and `rows` as POSITIONAL ARRAYS --
# zip them so callers can use property names. Hard row cap 200; the caller is
# expected to assert .Truncated where the plan says to.
function Invoke-IndexQuery([string] $sql, [string] $FailOnTruncate) {
  $txt = Get-EngineText @('sql', '--db', $DbPath, '--query', $sql, '--format', 'json')
  if ([string]::IsNullOrWhiteSpace($txt)) { return , @() }
  try { $o = $txt | ConvertFrom-Json } catch { throw "index query returned non-JSON: $txt" }
  if ($o.truncated) {
    # The 200-row cap is SILENT in the row list -- a truncated answer looks like
    # a small one. Callers that would render a short chart as if it were whole
    # pass -FailOnTruncate and get a hard stop instead.
    if ($FailOnTruncate) {
      throw "$FailOnTruncate hit the sql row cap ($($o.row_cap)); the answer would be silently short -- narrow the query"
    }
    Write-Host "  NOTE: result truncated at row_cap $($o.row_cap)"
  }
  $names = @($o.columns | ForEach-Object { $_.name })
  $out = New-Object System.Collections.ArrayList
  foreach ($row in @($o.rows)) {
    $vals = @($row)
    $h = [ordered]@{}
    for ($i = 0; $i -lt $names.Count; $i++) {
      $h[$names[$i]] = $(if ($i -lt $vals.Count) { $vals[$i] } else { $null })
    }
    [void]$out.Add([pscustomobject]$h)
  }
  # CONTRACT: the unary comma keeps a 0- or 1-row result an ARRAY through the
  # pipeline. It also means callers must assign the result DIRECTLY --
  #     $rows = Invoke-IndexQuery $sql          correct
  #     $rows = @(Invoke-IndexQuery $sql)       WRONG: nests it one level deep
  # The wrong form is quiet rather than fatal: Count reads 1, and member access
  # on the single wrapper element enumerates to the right value whenever there
  # is exactly one row, so it only misbehaves once a query returns two.
  , $out.ToArray()
}

function ConvertTo-SqlText([string] $s) { $s.Replace("'", "''") }

# Every row of a population query, PAGED past the silent 200-row cap. $Sql must
# NOT carry its own ORDER BY / LIMIT; $OrderKey must be a TOTAL order (end it in
# a unique column), or a page boundary can skip or repeat a row.
#
# Emit-Architecture carries a local Get-AllRows with the same body; this is the
# shared copy for the helpers below. Assign the result directly (see the
# Invoke-IndexQuery contract): `@(Get-AllIndexRows ...)` nests.
function Get-AllIndexRows([string] $Sql, [string] $OrderKey) {
  $out = New-Object System.Collections.ArrayList
  $off = 0
  while ($true) {
    $page = Invoke-IndexQuery "$Sql ORDER BY $OrderKey LIMIT 180 OFFSET $off"
    if ($page.Count -eq 0) { break }
    foreach ($r in $page) { [void]$out.Add($r) }
    if ($page.Count -lt 180) { break }
    $off += 180
  }
  , $out.ToArray()
}

# "'a','b','c'" for an IN-list. Callers use this to BOUND a query that would
# otherwise run past the 200-row cap -- Blueprint4.dfm alone has 516 dfm-type
# rows, so an unbounded component query there returns a silently short answer.
function ConvertTo-SqlInList([string[]] $Values) {
  ($Values | ForEach-Object { "'" + (ConvertTo-SqlText $_) + "'" }) -join ','
}

# Callers want the BODY, so prefer impl_start_line over the interface decl line.
function Get-SymbolLocation([string] $Qname) {
  $q = ConvertTo-SqlText $Qname
  $rows = Invoke-IndexQuery @"
SELECT s.id AS id, s.kind AS kind, s.start_line AS start_line,
       s.impl_start_line AS impl_start_line, s.impl_end_line AS impl_end_line,
       f.path AS path
  FROM symbols s JOIN files f ON f.id = s.file_id
 WHERE s.qualified_name = '$q'
"@
  if ($rows.Count -eq 0) { throw "$Qname is not in this index" }
  if ($rows.Count -gt 1) {
    Write-Host "  NOTE: $Qname resolves to $($rows.Count) symbols; using the first (id $($rows[0].id))"
  }
  $r = $rows[0]
  $focus = if ($r.impl_start_line) { [int]$r.impl_start_line } else { [int]$r.start_line }
  [pscustomobject]@{
    Id = [int]$r.id; Kind = [string]$r.kind; Path = [string]$r.path
    DeclLine = [int]$r.start_line
    ImplStart = $(if ($r.impl_start_line) { [int]$r.impl_start_line } else { 0 })
    ImplEnd   = $(if ($r.impl_end_line)   { [int]$r.impl_end_line }   else { 0 })
    FocusLine = $focus
  }
}

# ---- member selection -------------------------------------------------------

# Collapse FORWARD DECLARATIONS onto the real declaration they announce.
#
# A Delphi interface section routinely declares a type twice -- `IDataService =
# interface;` up front, then the body further down -- and the index stores both,
# with the SAME qualified_name. Counting them as separate types makes a chart
# report an ambiguity that does not exist.
#
# The key is (qualified_name, generic_params), NOT qualified_name alone, because
# a generic and a non-generic type can legitimately share a name and this corpus
# has exactly that case: IuMicObject.pas declares `IDataService` and
# `IDataService<I: IMicObject>`, each with its own forward declaration -- FOUR
# rows, TWO real types. Collapsing on the name alone would merge two different
# types; collapsing on the pair does not.
#
# MEASURED 2026-09-23, CLIENT: 857 (qualified_name, generic_params) groups and
# ZERO of them span more than one file. So every group really is one type's
# declarations in one unit, and the widest line span is its body.
function Select-DeclarationRows($Rows) {
  $out = New-Object System.Collections.ArrayList
  foreach ($g in @($Rows | Group-Object { "$([string]$_.qualified_name)|$([string]$_.generic_params)" })) {
    $best = @($g.Group | Sort-Object `
                @{ E = { [int]$_.end_line - [int]$_.start_line }; Descending = $true }, `
                @{ E = { [int]$_.start_line }; Descending = $false })[0]
    [void]$out.Add($best)
  }
  , $out.ToArray()
}

# Resolve a FIELD or PROPERTY selection, REFUSING an ambiguous name rather than
# taking the first match the way Get-SymbolLocation does.
#
# MEASURED 2026-09-23 on BOTH ORM3 indexes, and the two halves disagree sharply:
#
#   form        CLIENT                      SERVER
#   qualified   13,131 names / 0 ambiguous   9,095 names / 0 ambiguous
#   bare         6,849 names / 2,716 (40%)   3,592 names / 2,136 (59%)
#
# So a QUALIFIED field/property name is a safe key -- not one of the 22,226
# measured is ambiguous -- while a BARE one is a coin toss, worst case `ID` at
# 154 distinct symbols. A bare name is therefore accepted only when it happens
# to be unique, and an ambiguous one is refused WITH its candidates.
#
# Refusing is the whole point: this chart is about ONE member, so resolving to
# the wrong one does not mislabel a row, it mislabels every row in the picture.
# `FConnected` resolving uniquely here is luck, not a rule.
# -AllowMissing returns $null instead of throwing when NOTHING matches, while
# still refusing an ambiguous name. The two outcomes are different questions:
# "I cannot tell WHICH one you mean" is always fatal, but "this index does not
# declare it" is a legitimate answer for a type whose DESCENDANTS live here even
# though its declaration does not -- TInterfacedObject has 145 descendants on
# CLIENT and no declaration in it, because it is RTL.
#
# -Hint is the advice appended when the symbol exists but is the WRONG KIND.
# It differs per emitter -- who-calls is the right redirect for a method asked
# of who-writes, and the wrong one for a unit asked of class-surface.
function Resolve-MemberSelection([string] $Qname, [string[]] $Kinds, [switch] $AllowMissing,
                                 [string] $Hint = 'ask who-calls instead') {
  $q = ConvertTo-SqlText $Qname
  $rows = Invoke-IndexQuery @"
SELECT s.id AS id, s.kind AS kind, s.qualified_name AS qualified_name,
       s.name AS name, s.start_line AS start_line, s.end_line AS end_line,
       s.impl_start_line AS impl_start_line, s.impl_end_line AS impl_end_line,
       s.prop_access AS prop_access, s.generic_params AS generic_params,
       f.path AS path
  FROM symbols s JOIN files f ON f.id = s.file_id
 WHERE s.qualified_name = '$q' OR s.name = '$q'
 ORDER BY s.qualified_name
"@
  if ($rows.Count -eq 0) {
    if ($AllowMissing) { return $null }
    throw "$Qname is not in this index"
  }
  # Forward declarations are not alternatives to choose between.
  $rows = Select-DeclarationRows $rows

  # An exact QUALIFIED hit wins outright: `R` as a qualified name and `R` as a
  # bare name are different questions, and the caller asked the precise one.
  $exact = @($rows | Where-Object { [string]$_.qualified_name -eq $Qname })
  $cand  = if ($exact.Count) { $exact } else { $rows }

  # Narrow a BARE name to the kinds actually asked for before judging ambiguity.
  # `ID` matches 170 symbols on CLIENT but only 4 are fields -- refusing on the
  # 150 properties and 16 params/locals would reject a selection that is not
  # ambiguous among the things this chart can even draw. Only narrow when it
  # leaves something: otherwise fall through to the kind error below, which
  # says what the symbol IS rather than that it is ambiguous.
  if (-not $exact.Count -and $Kinds) {
    $ofKind = @($cand | Where-Object { $Kinds -contains [string]$_.kind })
    if ($ofKind.Count) { $cand = $ofKind }
  }

  if ($cand.Count -gt 1) {
    # Name what actually TELLS THEM APART. Advising "qualify it" is useless when
    # the candidates already share a qualified name, which happens for a generic
    # and a non-generic type of the same name (IuMicObject.IDataService and
    # IDataService<I: IMicObject>) -- there the generic parameters are the
    # difference, and for everything else it is the unit.
    $sameQ = @($cand | Group-Object { [string]$_.qualified_name }).Count -eq 1
    $head = ($cand | Select-Object -First 6 | ForEach-Object {
      $g = [string]$_.generic_params
      "$([string]$_.qualified_name)$(if ($g) { "<$g>" }) at $([IO.Path]::GetFileName([string]$_.path)):$($_.start_line)"
    }) -join '; '
    $tail = if ($cand.Count -gt 6) { "; +$($cand.Count - 6) more" } else { '' }
    $advice = if ($sameQ) {
      'They share a qualified name, so qualifying will not separate them -- they differ by generic parameters.'
    } else {
      'Pass a fully qualified name.'
    }
    throw "$Qname is ambiguous -- $($cand.Count) symbols share that name: $head$tail. $advice"
  }

  $r = $cand[0]
  if ($Kinds -and ($Kinds -notcontains [string]$r.kind)) {
    throw "$($r.qualified_name) is a $($r.kind), not a $($Kinds -join ' or ') -- $Hint"
  }
  $focus = if ($r.impl_start_line) { [int]$r.impl_start_line } else { [int]$r.start_line }
  [pscustomobject]@{
    Id = [int]$r.id; Kind = [string]$r.kind; Path = [string]$r.path
    Qname = [string]$r.qualified_name; Name = [string]$r.name
    PropAccess = [string]$r.prop_access
    DeclLine = [int]$r.start_line
    ImplStart = $(if ($r.impl_start_line) { [int]$r.impl_start_line } else { 0 })
    ImplEnd   = $(if ($r.impl_end_line)   { [int]$r.impl_end_line }   else { 0 })
    FocusLine = $focus
  }
}

# ---- source zones -------------------------------------------------------------

# A "zone" is a source DIRECTORY relative to the project's common root, and it is
# the only layering signal this corpus actually carries.
#
# MEASURED on the CLIENT clone 2026-09-23, after testing the alternatives:
#   namespace prefix   512 of 563 units have NO DOT            -- unusable
#   dotted suffix      ViewModel 36, Interfaces 4, Model 2     -- 9% coverage
#   SOURCE DIRECTORY   CLIENT 268, COMMON/OBJECTS 268, COMMON 27 -- 100%
#
# Shared rather than copied because three charts now zone the same paths
# (architecture, protocol-trace, crosses-boundary) and two of them compare zones
# ACROSS indexes. If they computed the root differently, "CLIENT" in one chart
# and "CLIENT" in the next would silently mean different directories.
function Get-CommonRootLen([string[]] $Dirs) {
  $uniq = @($Dirs | Where-Object { $_ } | Sort-Object -Unique)
  if ($uniq.Count -eq 0) { return 0 }
  $split = @($uniq | ForEach-Object { , ($_ -split '\\') })
  $common = @($split[0])
  foreach ($s in $split) {
    $n = [Math]::Min($common.Count, $s.Count)
    $keep = 0
    while ($keep -lt $n -and $common[$keep] -eq $s[$keep]) { $keep++ }
    if ($keep -eq 0) { return 0 }
    $common = @($common[0..($keep - 1)])
  }
  $common.Count
}

function Get-PathZone([string] $Path, [int] $RootLen) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return '(unknown)' }
  $parts = @([IO.Path]::GetDirectoryName($Path) -split '\\')
  if ($RootLen -le 0 -or $parts.Count -le $RootLen) { return '(root)' }
  ($parts[$RootLen..($parts.Count - 1)]) -join '/'
}

# ---- index health ---------------------------------------------------------------

# Files that hold plenty of CALL references and NO call edges at all.
#
# WHY THIS EXISTS, AND WHY IT IS NOT A VERSION STORY
# ---------------------------------------------------
# For a day this project believed the 1.6.0 resolver "bound strictly less" and
# that interface-dispatch edges had been lost wholesale. That was WRONG, and the
# engine team corrected it on 2026-09-23 with a mechanism we then verified
# independently on our own clone:
#
#   a whole-DB resolve calls ClearCallEdges, which clears UNCONDITIONALLY --
#   including rows belonging to files the stale prescan then WITHHOLDS -- while
#   the re-derivation is narrowed to SKIP stale files. A withheld file's
#   call_edges and member_accesses are cleared and never rebuilt.
#
# Measured on the CLIENT clone, and this is the whole of it:
#
#   uPipeClientConnection.pas   161 call refs   0 call_edges   0 member_accesses
#   Blueprint4.ViewModel.pas  1,847 call refs 656 call_edges
#   uMain.pas                   255 call refs  41 call_edges
#
# Every one of the suite's 9 red assertions traces to that ONE file:
# ExecuteCommand owns no outgoing edges, so the callee subtree below it is gone
# (9 nodes -> 4 is the SUBTREE, not the root -- SendDeltaOperation's two direct
# edges are intact and `certain`), and TPipeClientConnection.Connected lives in
# the same file, which is why its 602 rows lost accessor_symbol_id.
#
# So a chart that says "edges may be missing" should say WHICH FILES and let the
# reader judge, rather than blaming a version. This is detection, not a constant:
# after the recovering reindex it returns nothing and the disclosure disappears
# on its own.
#
# The threshold is deliberately conservative. A small unit whose calls all go to
# the RTL legitimately has zero edges -- on CLIENT, 22 files have some call refs
# and no edges, but only ONE has more than 35, and the next largest is 35. At 50
# the detector fires on exactly the file the engine team named and on nothing
# else. It is a heuristic and is described as one wherever it is printed.
function Get-EdgelessFiles([int] $MinCallRefs = 50) {
  $rows = Invoke-IndexQuery @"
SELECT p, n FROM (
  SELECT f.path AS p,
         (SELECT COUNT(*) FROM refs r WHERE r.file_id = f.id AND r.kind = 'call') AS n,
         (SELECT COUNT(*) FROM call_edges ce JOIN refs r2 ON r2.id = ce.ref_id
           WHERE r2.file_id = f.id) AS e
    FROM files f)
 WHERE n >= $MinCallRefs AND e = 0
 ORDER BY n DESC
"@
  , $rows
}

# The one sentence every chart uses for it, so two charts cannot describe the
# same index defect differently. Returns '' when the index is healthy.
# STATES THE OBSERVATION, NOT THE CAUSE -- which is the whole lesson of the note
# above. On CLIENT the single hit is a genuinely withheld file. On SERVER the
# single hit is `uContainerConfig.pas`, whose 137 call refs are Spring4D fluent
# registrations (`AsSingletonPerThread` x134) targeting code OUTSIDE the index,
# where zero edges is entirely correct. Two different causes, one signature, and
# this detector cannot tell them apart -- so it does not try.
#
# The practical consequence is the same either way, and that is the part worth
# printing: edges out of symbols in those files are not available here.
function Get-EdgelessDisclosure($Rows) {
  if ($null -eq $Rows -or $Rows.Count -eq 0) { return '' }
  $names = @($Rows | Select-Object -First 3 | ForEach-Object { [IO.Path]::GetFileName([string]$_.p) })
  $more = $(if ($Rows.Count -gt 3) { " +$($Rows.Count - 3) more" } else { '' })
  "$($Rows.Count) file(s) here have call references but NO call edges ($($names -join ', ')$more) -- either their calls all target code outside this index, or a partial resolve cleared them; either way, edges out of symbols in those files are missing"
}

# ---- ranking and disclosure -------------------------------------------------

# Maps a `refs` row to its enclosing routine, as the SQL fragments to splice in.
# One place, so the emitters that need a SITE anchor cannot drift apart on it.
#
# WHY A COLUMN AND NOT THE CONTAINMENT SUBQUERY THE PLAN SPECIFIED
# ----------------------------------------------------------------
# PLAN-next-five-questions.md finding 2 hand-rolls this as a correlated subquery
# over symbols.impl_start_line/impl_end_line with `ORDER BY impl_start_line DESC
# LIMIT 1` to make the INNERMOST routine win. That subquery is correct -- and
# unnecessary. `refs.enclosing_symbol_id` already holds the answer.
#
# MEASURED 2026-09-23, every member-access row on both indexes, both ways:
#
#   index    rows     stored NULL  subquery NULL  DISAGREE
#   CLIENT   9,311    0            0              0
#   SERVER  14,836    0            0              0
#
# Zero disagreements, so the stored column IS the innermost-enclosing answer,
# computed by the engine. Using it means the chart cannot drift from the
# engine's own notion of "enclosing" the way a reimplementation silently can --
# and it is a join instead of a per-row subquery.
#
# The plan's totals were right; only its method was doing work already done.
# Same lesson as its finding 1 in a new place: ask what the index already
# stores before writing SQL to recompute it.
#
# `find-callers --resolved` still cannot answer this -- its `line` is the
# caller's DECLARATION line -- which is why a site anchor needs SQL at all.
function Get-EnclosingRoutineSql([string] $RefAlias, [string] $JoinAlias = 'encl') {
  [pscustomobject]@{
    Join   = "LEFT JOIN symbols $JoinAlias ON $JoinAlias.id = $RefAlias.enclosing_symbol_id"
    Select = "$JoinAlias.qualified_name"
  }
}

# Take the top $Cap of an ALREADY-RANKED row list and report exactly what was
# left out, so every caller discloses in the same words. Ranking is the
# caller's job; this only cuts and counts.
#
# $SiteProperty names the per-row count that must ALSO be totalled, because a
# chart whose rows are routines hides two different quantities at once: the
# routines it dropped and the access sites inside them.
function Get-TopRanked($Rows, [int] $Cap, [string] $SiteProperty = 'Sites') {
  # Strip nulls rather than trusting the caller. `$x = if (...) { @() }` assigns
  # $null, not an empty array -- an empty array enumerates to NOTHING on the
  # output stream -- and `@($null)` is then a ONE-element array holding $null.
  # That produced a phantom cross-check finding against an empty wing
  # ("write: verb , sql 0") before this guard existed.
  $all = @($Rows | Where-Object { $null -ne $_ })
  $shown = $all
  $hiddenRows = 0
  $hiddenSites = 0
  if ($Cap -gt 0 -and $all.Count -gt $Cap) {
    $shown = @($all[0..($Cap - 1)])
    foreach ($h in @($all[$Cap..($all.Count - 1)])) {
      $hiddenRows++
      if ($h.PSObject.Properties.Name -contains $SiteProperty) { $hiddenSites += [int]$h.$SiteProperty }
    }
  }
  [pscustomobject]@{
    Shown = $shown; Total = $all.Count
    HiddenRows = $hiddenRows; HiddenSites = $hiddenSites
  }
}

# The ONE place the "not shown" wording is built, so two charts never disclose
# the same fact in two different sentences.
function Get-DisclosureText([int] $HiddenRows, [int] $HiddenSites, [string] $Noun = 'routines') {
  if ($HiddenRows -le 0) { return '' }
  $t = "+$HiddenRows more $Noun"
  if ($HiddenSites -gt 0) { $t += " (+$HiddenSites more sites)" }
  "$t not shown"
}

# Append a NON-ANCHORED row to a raw HTML-label table builder (the focus box).
# Deliberately carries no HREF: there is no line to go to, and a dead link is
# worse than no link. touches-tables' zero case built this inline; both use it
# now so the two cannot diverge.
function Add-DisclosureRow([System.Text.StringBuilder] $Table, [string] $Text,
                           [string] $Ink = '#8A94A6', [int] $PointSize = 12) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return }
  [void]$Table.Append("<TR><TD ALIGN=`"LEFT`"><FONT COLOR=`"$Ink`" POINT-SIZE=`"$PointSize`">$(ConvertTo-XmlText $Text)</FONT></TD></TR>")
}

# A row object for Add-RowCluster that carries NO Href, so the cluster renders
# it as a plain note line. Use it for disclosure and for "see also" notes.
function New-NoteRow([string] $Text) {
  [pscustomobject]@{ Label = $Text; Line = $null; Href = $null; Tip = $null; Note = $null }
}

# ---- source text: freshness and comment-stripped context ------------------------
#
# THE RULE (R11 of PLAN-last-four-verbs): nothing reads a source line BY COLUMN
# without first proving the file on disk is the file that was indexed. Measured
# 2026-09-23: on the pre-1.18 DL clone 18 of 128 files differed from disk, and a
# classifier then read lines that no longer held the ref's name at all (38
# `type_use` rows whose "token" was prose from a comment). On the current clones
# CLIENT has 1 differing file (uMain.ViewModel.pas) and DL 1 (TreeSitterLib.pas).
# The mechanism never goes away; only the exposure shrinks.
#
# -SourceOverride (controller ruling R4) maps an INDEXED path to a different
# file to read instead. It exists so a test can manufacture a stale file
# deterministically -- copy a source, change one line, pass the map -- without
# depending on the disk happening to differ and without writing to any database.
# Keys match case-insensitively (Windows paths).
function Resolve-SourceReadPath([string] $Path, [hashtable] $SourceOverride) {
  if ($SourceOverride) {
    foreach ($k in $SourceOverride.Keys) {
      if ([string]::Equals([string]$k, $Path, [StringComparison]::OrdinalIgnoreCase)) {
        return [string]$SourceOverride[$k]
      }
    }
  }
  $Path
}

# path -> sha256 for every file of $DbPath, loaded ONCE per database per run
# (paged: CLIENT has 625 files). A plain @{} is case-insensitive, like the paths.
function Get-IndexedFileShas {
  if (-not $script:DlFileShas) { $script:DlFileShas = @{} }
  if (-not $script:DlFileShas.ContainsKey($DbPath)) {
    $map = @{}
    $ids = @{}
    foreach ($r in (Get-AllIndexRows 'SELECT id, path, sha256 FROM files' 'id')) {
      $map[[string]$r.path] = [string]$r.sha256
      $ids[[string]$r.path] = [int]$r.id
    }
    if (-not $script:DlFileIds) { $script:DlFileIds = @{} }
    $script:DlFileIds[$DbPath] = $ids
    $script:DlFileShas[$DbPath] = $map
  }
  $script:DlFileShas[$DbPath]
}

# $true when the file that would be READ for $Path (the override target, or
# $Path itself) hashes to the sha256 the index recorded for $Path; $false when it
# differs or is missing. Throws when $Path is not a file of $DbPath at all --
# that is a caller bug, not a staleness verdict. Cached per run per read path,
# so a test must use a fresh scratch path for each manufactured variant.
function Test-SourceFresh([string] $Path, [hashtable] $SourceOverride) {
  $map = Get-IndexedFileShas
  if (-not $map.ContainsKey($Path)) { throw "Test-SourceFresh: $Path is not a file of this index ($DbPath)" }
  $read = Resolve-SourceReadPath $Path $SourceOverride
  if (-not (Test-Path -LiteralPath $read)) { return $false }
  if (-not $script:DlFreshCache) { $script:DlFreshCache = @{} }
  $key = "$DbPath|$Path|$read"
  if (-not $script:DlFreshCache.ContainsKey($key)) {
    $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $read).Hash
    $script:DlFreshCache[$key] = [string]::Equals($h, [string]$map[$Path], [StringComparison]::OrdinalIgnoreCase)
  }
  $script:DlFreshCache[$key]
}

# Pascal source with every comment, string and directive replaced by SPACES,
# newlines kept -- so line N and column C still address exactly what the index
# addressed. One regex over the WHOLE file, leftmost match wins, which is what
# makes `'{'` a string and `{ ' }` a comment without a state machine (a per-line
# state machine was tried first and was both slower and wrong across lines).
#   '...'        string      (a doubled '' is two adjacent strings; same result)
#   { ... }      comment, and {$...} directives (R13: blanked, not evaluated)
#   (* ... *)    comment
#   // ...       line comment
# Read as Latin-1 so one byte is one char: the corpus is 7-bit ASCII by rule,
# and a stray high byte must not shift every column after it on that line.
function Get-StrippedSourceLines([string] $ReadPath) {
  if (-not $script:DlStripped) { $script:DlStripped = @{} }
  if (-not $script:DlStripped.ContainsKey($ReadPath)) {
    $rx = [regex]"'[^'\r\n]*'|\{[^}]*\}|\(\*[\s\S]*?\*\)|//[^\r\n]*"
    $raw = [IO.File]::ReadAllText($ReadPath, [Text.Encoding]::GetEncoding(28591))
    $s = $rx.Replace($raw, {
      param($m)
      $v = $m.Value
      if ($v.IndexOf("`n") -lt 0) { ' ' * $v.Length } else { [regex]::Replace($v, '[^\r\n]', ' ') }
    })
    $script:DlStripped[$ReadPath] = [string[]]($s -split "\r?\n")
  }
  , $script:DlStripped[$ReadPath]
}

# The comment-stripped text around ONE ref, for classifying it by the tokens
# next to it. $Col is refs.start_col (1-based); $Len is end_col - start_col
# (end_col is exclusive -- P10).
#
# Returns: Path, Line, Stale, Before (text left of the ref, untrimmed), Token
# (the stripped text AT the ref -- blank means the ref sits inside a comment or
# string in this copy), After (text right of it), PrevLine / PrevLineNo (the
# previous non-blank stripped line, trimmed; '' / 0 when none), Following (the
# next -Following stripped lines, for a statement that continues).
#
# STALE IS A RESULT, NOT AN ERROR: when Test-SourceFresh fails, every text field
# is $null and Stale is $true. The caller renders `[stale source]` and must not
# classify -- returning no text makes that the only thing it CAN do.
function Get-SourceContext([string] $Path, [int] $Line, [int] $Col, [int] $Len,
                           [hashtable] $SourceOverride, [int] $Following = 0) {
  if (-not (Test-SourceFresh $Path $SourceOverride)) {
    return [pscustomobject]@{
      Path = $Path; Line = $Line; Stale = $true
      Before = $null; Token = $null; After = $null
      PrevLine = $null; PrevLineNo = 0; Following = $null
    }
  }
  $lines = Get-StrippedSourceLines (Resolve-SourceReadPath $Path $SourceOverride)
  if ($Line -lt 1 -or $Line -gt $lines.Count) {
    throw "Get-SourceContext: line $Line is outside $Path ($($lines.Count) lines) although the file is fresh"
  }
  $t  = $lines[$Line - 1]
  $c0 = [Math]::Min([Math]::Max($Col - 1, 0), $t.Length)
  $c1 = [Math]::Min($c0 + [Math]::Max($Len, 0), $t.Length)
  $prev = ''; $prevNo = 0
  for ($i = $Line - 2; $i -ge 0; $i--) {
    if ($lines[$i].Trim()) { $prev = $lines[$i].Trim(); $prevNo = $i + 1; break }
  }
  $fol = New-Object System.Collections.ArrayList
  for ($i = $Line; $i -lt [Math]::Min($Line + $Following, $lines.Count); $i++) { [void]$fol.Add($lines[$i]) }
  [pscustomobject]@{
    Path = $Path; Line = $Line; Stale = $false
    Before = $t.Substring(0, $c0); Token = $t.Substring($c0, $c1 - $c0); After = $t.Substring($c1)
    PrevLine = $prev; PrevLineNo = $prevNo; Following = $fol.ToArray()
  }
}

# ---- SQL script index: collapsed tables, trigger bodies, verb-table scan ----------
#
# THE SQL INDEX IS HISTORY, NOT SCHEMA (P15/R6). 252 sql_table rows are 135
# distinct names: 117 names are declared in BOTH MS1.SQL and MScript2.SQL.
# Counting rows is the trap this plan's own first pass fell into (`ID` "in 149
# tables"; by name it is 77).
#
# WHICH DECLARATION WINS -- A FINDING AGAINST THE PLAN TEXT (2026-09-23)
# ----------------------------------------------------------------------
# The plan said "prefer the LAST declaration in file order", assuming the
# scripts are numbered oldest-first. Measured, that picks the WRONG copy: every
# duplicate sits in MS1.SQL (file 1) and MScript2.SQL (file 12), and MScript2 is
# the OLD one --
#
#   file           mtime        FOLDERS cols  CAUSFAIL cols  DRA1 cols
#   MS1.SQL        2026-06-22        79             4           13
#   MScript2.SQL   2025-02-11        47             3            9
#
# Live Firebird has FOLDERS 79 and CAUSFAIL 4/4 (P16/P24), i.e. MS1. MScript2 is
# also the only home of OPERATION, the one index-only table (dropped live). So
# the winner is the declaration in the NEWEST file (files.mtime_unix), then the
# latest line -- a recorded fact of the index, not a guess from file names.
# Every declaration is still carried in .Declarations for disclosure.
function Get-SqlTableSet([string] $SqlDb) {
  $SqlDb = Get-CloneDb $SqlDb
  if (-not $script:DlSqlSets) { $script:DlSqlSets = @{} }
  if ($script:DlSqlSets.ContainsKey($SqlDb)) { return $script:DlSqlSets[$SqlDb] }

  # Shadow $DbPath: Invoke-IndexQuery resolves it dynamically, so every query
  # below runs against the SQL index, and the caller's $DbPath is untouched.
  $DbPath = $SqlDb

  $decl = Get-AllIndexRows @"
SELECT t.id AS id, t.name AS name, t.start_line AS line, f.path AS path, f.mtime_unix AS mtime
  FROM symbols t JOIN files f ON f.id = t.file_id
 WHERE t.kind = 'sql_table'
"@ 't.id'
  $cols = @{}
  foreach ($r in (Get-AllIndexRows @"
SELECT c.parent_id AS tid, GROUP_CONCAT(c.name, ',') AS cols
  FROM symbols c WHERE c.kind = 'sql_column' GROUP BY c.parent_id
"@ 'c.parent_id')) { $cols[[int]$r.tid] = @(([string]$r.cols) -split ',' | Where-Object { $_ }) }

  $tables = @{}
  $collapsed = 0
  foreach ($g in @($decl | Group-Object { ([string]$_.name).ToUpperInvariant() })) {
    $ordered = @($g.Group | Sort-Object @{ E = { [long]$_.mtime }; Descending = $true },
                                        @{ E = { [int]$_.line };  Descending = $true })
    $win = $ordered[0]
    if ($g.Count -gt 1) { $collapsed++ }
    $names = New-Object string[] 0
    if ($cols.ContainsKey([int]$win.id)) { $names = [string[]]$cols[[int]$win.id] }
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($c in $names) { [void]$set.Add($c) }
    $tables[[string]$win.name] = [pscustomobject]@{
      Name = [string]$win.name; Id = [int]$win.id; File = [string]$win.path; Line = [int]$win.line
      DeclCount = $g.Count
      Declarations = @($ordered | ForEach-Object {
        [pscustomobject]@{ Id = [int]$_.id; File = [string]$_.path; Line = [int]$_.line
                           Columns = $(if ($cols.ContainsKey([int]$_.id)) { $cols[[int]$_.id].Count } else { 0 }) } })
      Columns = $set; ColumnNames = $names
    }
  }

  $procs = Get-AllIndexRows "SELECT id, name FROM symbols WHERE kind = 'sql_procedure'" 'id'
  $pset = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($p in $procs) { [void]$pset.Add([string]$p.name) }

  $o = [pscustomobject]@{
    Db = $SqlDb
    Tables = $tables
    Names = [string[]]@($tables.Keys | Sort-Object)
    TableCount = $tables.Count
    DeclarationCount = $decl.Count
    CollapsedNames = $collapsed
    Procedures = $pset
    ProcedureCount = $pset.Count
    ProcedureDeclCount = $procs.Count
  }
  $script:DlSqlSets[$SqlDb] = $o
  $o
}

# The P23 scan, in ONE place: a table (or procedure) named IMMEDIATELY after an
# UPPER-CASE verb. Case-SENSITIVE on purpose -- `Cannot Load from CAUSFAIL` and
# `IS NOT DISTINCT FROM ta.OPERID` are text, not SQL uses -- and the name must
# be in the collapsed set, which drops `FROM RDB$DATABASE`, `FROM (`, `SERIAL`,
# `TRUE`, `USER`. DELETE FROM and EXECUTE PROCEDURE are tried before FROM so the
# verb is reported whole. A name matched here is a NAME match: render it
# `[inferred]`, never `[certain]`.
# Returns Verb, Name, Kind ('table' | 'procedure') and Index (char offset).
function Get-SqlVerbTables([string] $Text, $SqlSet) {
  $out = New-Object System.Collections.ArrayList
  if ([string]::IsNullOrEmpty($Text)) { return , $out.ToArray() }
  $rx = [regex]'(?<![A-Za-z0-9_$.])(DELETE\s+FROM|EXECUTE\s+PROCEDURE|FROM|JOIN|INTO|UPDATE)\s+([A-Z][A-Z0-9_$]*)(?![A-Za-z0-9_$])'
  foreach ($m in $rx.Matches($Text)) {
    $verb = $m.Groups[1].Value -replace '\s+', ' '
    $name = $m.Groups[2].Value
    if ($verb -eq 'EXECUTE PROCEDURE') {
      if ($SqlSet.Procedures.Contains($name)) {
        [void]$out.Add([pscustomobject]@{ Verb = $verb; Name = $name; Kind = 'procedure'; Index = $m.Index })
      }
    } elseif ($SqlSet.Tables.ContainsKey($name)) {
      [void]$out.Add([pscustomobject]@{ Verb = $verb; Name = $name; Kind = 'table'; Index = $m.Index })
    }
  }
  , $out.ToArray()
}

# SQL text with strings and comments blanked, line-preserving (same contract as
# Get-StrippedSourceLines): '...' strings, /* ... */ and -- line comments.
function Get-StrippedSqlLines([string] $ReadPath) {
  if (-not $script:DlStrippedSql) { $script:DlStrippedSql = @{} }
  if (-not $script:DlStrippedSql.ContainsKey($ReadPath)) {
    $rx = [regex]"'[^']*'|/\*[\s\S]*?\*/|--[^\r\n]*"
    $raw = [IO.File]::ReadAllText($ReadPath, [Text.Encoding]::GetEncoding(28591))
    $s = $rx.Replace($raw, {
      param($m)
      $v = $m.Value
      if ($v.IndexOf("`n") -lt 0) { ' ' * $v.Length } else { [regex]::Replace($v, '[^\r\n]', ' ') }
    })
    $script:DlStrippedSql[$ReadPath] = [string[]]($s -split "\r?\n")
  }
  , $script:DlStrippedSql[$ReadPath]
}

# A TRIGGER body read from the .SQL source, because the index stores none: every
# trigger and procedure symbol has start_line == end_line (P18). Scans from the
# declaration line to the next line that is exactly `^` (after comments are
# blanked and trailing blanks trimmed) -- 183/183 triggers terminate that way.
# PROCEDURES DO NOT (P20: 1 of 168; MS1/MS5 use a SET TERM layout) -- that
# scanner is Task 2's, so this is for triggers only.
# $DbPath must be the SQL index (freshness is checked against it).
# Returns Stale, Found, StartLine, EndLine (the `^` line, 0 when not found) and
# Text (the stripped body, declaration line included, `^` excluded).
function Get-SqlBodyText([string] $Path, [int] $Line, [hashtable] $SourceOverride, [int] $MaxLines = 400) {
  if (-not (Test-SourceFresh $Path $SourceOverride)) {
    return [pscustomobject]@{ Stale = $true; Found = $false; StartLine = $Line; EndLine = 0; Text = $null }
  }
  $lines = Get-StrippedSqlLines (Resolve-SourceReadPath $Path $SourceOverride)
  $last = [Math]::Min($lines.Count, $Line - 1 + $MaxLines)
  for ($j = $Line - 1; $j -lt $last; $j++) {
    if ($lines[$j].TrimEnd() -eq '^') {
      $body = if ($j -gt $Line - 1) { $lines[($Line - 1)..($j - 1)] -join "`n" } else { '' }
      return [pscustomobject]@{ Stale = $false; Found = $true; StartLine = $Line; EndLine = $j + 1; Text = $body }
    }
  }
  [pscustomobject]@{ Stale = $false; Found = $false; StartLine = $Line; EndLine = 0; Text = $null }
}

# Every trigger with its table and scanned body, cached per SQL index per run.
# The table is the sql_table_ref the engine emits ON the CREATE TRIGGER line
# (P17: the only refs the SQL index has); the body is read from source.
# Per trigger: Id, Name, File, Line, EndLine, Table, TableKnown (in the collapsed
# set), Stale, Found, Columns (distinct NEW./OLD. column names, upper-case) and
# OtherTables (tables the body names after an upper-case verb, own table excluded).
function Get-SqlTriggerSet([string] $SqlDb, [hashtable] $SourceOverride) {
  $set = Get-SqlTableSet $SqlDb
  $SqlDb = $set.Db
  if (-not $script:DlTrigSets) { $script:DlTrigSets = @{} }
  if (-not $SourceOverride -and $script:DlTrigSets.ContainsKey($SqlDb)) { return $script:DlTrigSets[$SqlDb] }
  $DbPath = $SqlDb   # see Get-SqlTableSet

  $rows = Get-AllIndexRows @"
SELECT s.id AS id, s.name AS name, s.start_line AS line, f.path AS path,
       (SELECT r.name_text FROM refs r
         WHERE r.file_id = s.file_id AND r.start_line = s.start_line AND r.kind = 'sql_table_ref'
         LIMIT 1) AS tbl
  FROM symbols s JOIN files f ON f.id = s.file_id
 WHERE s.kind = 'sql_trigger'
"@ 's.id'
  $out = New-Object System.Collections.ArrayList
  foreach ($r in $rows) {
    $b = Get-SqlBodyText ([string]$r.path) ([int]$r.line) $SourceOverride
    $tbl = [string]$r.tbl
    $colList = @(); $other = @()
    if ($b.Found) {
      $colList = @([regex]::Matches($b.Text, '\b(?:NEW|OLD)\.([A-Za-z_][A-Za-z0-9_$]*)') |
                   ForEach-Object { $_.Groups[1].Value.ToUpperInvariant() } | Sort-Object -Unique)
      $other = @((Get-SqlVerbTables $b.Text $set) | Where-Object { $_.Kind -eq 'table' -and $_.Name -ne $tbl } |
                 ForEach-Object { $_.Name } | Sort-Object -Unique)
    }
    [void]$out.Add([pscustomobject]@{
      Id = [int]$r.id; Name = [string]$r.name; File = [string]$r.path; Line = [int]$r.line
      EndLine = $b.EndLine; Table = $tbl; TableKnown = ($tbl -and $set.Tables.ContainsKey($tbl))
      Stale = $b.Stale; Found = $b.Found; Columns = $colList; OtherTables = $other
    })
  }
  $all = $out.ToArray()
  $o = [pscustomobject]@{
    Triggers        = $all
    Count           = $all.Count
    BodiesFound     = @($all | Where-Object { $_.Found }).Count
    Stale           = @($all | Where-Object { $_.Stale }).Count
    ForKnownTable   = @($all | Where-Object { $_.TableKnown }).Count
    WithNewOld      = @($all | Where-Object { $_.Columns.Count -gt 0 }).Count
    WithOtherTables = @($all | Where-Object { $_.OtherTables.Count -gt 0 }).Count
  }
  if (-not $SourceOverride) { $script:DlTrigSets[$SqlDb] = $o }
  $o
}

# ---- the datasource chain (feeds-from and lands-where share it) ------------------
#
# control --DataSource--> TDataSource --DataSet--> memtable --owner--> view model
#         --literal--> table
#
# ONE function, so feeds-from and lands-where cannot disagree on what a control
# feeds from. Every hop is graded, and the first hop that cannot be taken says
# WHY in StopReason, so a chart renders "chain stops here: <reason>" without
# re-querying. MEASURED on CLIENT 2026-09-23 (P27-P33, re-measured for Task 0):
#
#   * The datasource resolves in the SAME DFM only. A name-only lookup "finds"
#     `dsrFtrs` in three forms -- a collision, not a resolution (P28).
#   * A module-prefixed name (`dmlSystem2.dsrFolder`) whose module exists nowhere
#     in the index is DANGLING. All 65 such rows are; 63 of their controls are
#     re-pointed in code. Only 21 of those are visible through receiver_text:
#     `edtF2        .DataBinding   .DataSource:= DS` (whitespace before the dot)
#     stores receiver_text '.DataBinding' with the control lost (P29). The
#     control is recovered from the comment-stripped SOURCE of that line, and the
#     row says so (ControlFrom = 'source').
#   * The dataset is wired in the DFM for 5 of 54 datasources and in CODE for
#     49: `dsrX.DataSet := FViewModel.MemTable`, read from source (10 of the 53
#     assignments continue on the next line, hence -Following).
#   * The table comes from string literals in the unit that declares the RHS
#     root's type, matched against the collapsed SQL table set. 22 datasources
#     resolve to exactly one table, 17 to many, 9 to none.
#   * Bound column names break a many-table tie ONLY when the survivors are
#     exactly one (P33); a column name alone never picks a table (P34).
#
# Parameters: $Form is the DFM path as indexed, or the form's name. $DsName is
# the text a binding carries (possibly `Module.Name`). $SqlSet is the object from
# Get-SqlTableSet. $DbPath is the Delphi index.
#
# Returns (grades are the chart vocabulary: certain / inferred / by name /
# dangling / unresolved / stale source):
#   Form, FormFile, PasFile, DsName, Module, Dangling
#   DataSource      $null | Id, Name, Qname, Type, File, Line
#   Controls[]      Control, ControlType, ControlId, Prop, File, Line, IsLookup
#   RePointedAt[]   Control, ControlFrom ('receiver'|'source'), Receiver, File,
#                   Line, Routine, Rhs, Stale
#   DataSetSites[]  Kind ('dfm'|'assign'|'read'|'stale'), File, Line, Routine, Rhs
#   RhsType         $null | Rhs, Root, RootKind, TypeName, TypeKind, TypeFile, TypeLine
#   CandidateTables[], BoundColumns[], ColumnMatch[], MissingColumns[]
#   ResolvedTable   string | $null
#   Grade           one-table | by-columns | many | none | no-type | no-assignment
#                   | dfm-dataset | dangling | no-datasource | stale source
#   Hops[]          Hop, Grade, Label, File, Line, Reason  (in chain order)
#   StopReason      '' when a table was resolved
function Get-DataSourceChain([string] $Form, [string] $DsName, $SqlSet, [hashtable] $SourceOverride) {
  $shas = Get-IndexedFileShas

  # ---- the form's DFM and its sibling .pas -------------------------------------
  if ($Form -match '\.dfm$') {
    $dfmPath = @($shas.Keys | Where-Object { [string]::Equals($_, $Form, [StringComparison]::OrdinalIgnoreCase) })
    if ($dfmPath.Count -ne 1) { throw "Get-DataSourceChain: $Form is not a DFM of this index" }
    $dfmPath = $dfmPath[0]
  } else {
    $qf = ConvertTo-SqlText $Form
    $fr = Invoke-IndexQuery @"
SELECT f.path AS path FROM symbols s JOIN files f ON f.id = s.file_id
 WHERE s.kind = 'form' AND (s.qualified_name = '$qf' OR s.name = '$qf')
"@
    if ($fr.Count -eq 0) { throw "Get-DataSourceChain: no form or data module named $Form in this index" }
    if ($fr.Count -gt 1) {
      throw "Get-DataSourceChain: $Form names $($fr.Count) forms ($(($fr | ForEach-Object { [IO.Path]::GetFileName([string]$_.path) }) -join ', ')) -- pass the DFM path"
    }
    $dfmPath = [string]$fr[0].path
  }
  $fileIds = $script:DlFileIds[$DbPath]
  $dfmId = $fileIds[$dfmPath]
  $pasGuess = [IO.Path]::ChangeExtension($dfmPath, '.pas')
  $pasPath = @($shas.Keys | Where-Object { [string]::Equals($_, $pasGuess, [StringComparison]::OrdinalIgnoreCase) })
  $pasPath = if ($pasPath.Count) { [string]$pasPath[0] } else { $null }
  $pasId = if ($pasPath) { $fileIds[$pasPath] } else { 0 }

  $hops = New-Object System.Collections.ArrayList
  function Add-Hop($h, $g, $l, $f, $n, $why) {
    [void]$hops.Add([pscustomobject]@{ Hop = $h; Grade = $g; Label = $l; File = $f; Line = $n; Reason = $why })
  }

  # ---- the controls that name this datasource in THIS DFM ----------------------
  $dsq = ConvertTo-SqlText $DsName
  $ctlRows = Invoke-IndexQuery @"
SELECT sl.owner_name AS prop, sl.start_line AS line, c.id AS cid, c.name AS ctl, c.signature AS ctype
  FROM string_literals sl LEFT JOIN symbols c ON c.id = sl.symbol_id
 WHERE sl.kind = 'dfm-prop' AND sl.file_id = $dfmId
   AND sl.owner_name IN ('DataSource','DataBinding.DataSource','DataController.DataSource','ListSource','Properties.ListSource')
   AND UPPER(sl.text) = UPPER('$dsq')
 ORDER BY sl.start_line
"@ 'Get-DataSourceChain (controls)'
  $controls = @($ctlRows | ForEach-Object {
    [pscustomobject]@{
      Control = [string]$_.ctl; ControlType = [string]$_.ctype
      ControlId = $(if ($_.cid) { [int]$_.cid } else { 0 })
      Prop = [string]$_.prop; File = $dfmPath; Line = [int]$_.line
      IsLookup = ([string]$_.prop -like '*ListSource')
    } })

  # ---- re-pointing in code: <control>[.DataBinding|.DataController].DataSource := ...
  $repoint = New-Object System.Collections.ArrayList
  $names = @($controls | Where-Object { $_.Control } | ForEach-Object { $_.Control } | Sort-Object -Unique)
  if ($pasId -and $names.Count) {
    $sites = Invoke-IndexQuery @"
SELECT r.receiver_text AS rt, r.start_line AS line, r.start_col AS col, r.end_col AS ecol,
       encl.qualified_name AS routine
  FROM refs r LEFT JOIN symbols encl ON encl.id = r.enclosing_symbol_id
 WHERE r.file_id = $pasId AND r.kind = 'member-access' AND r.name_text IN ('DataSource','ListSource')
 ORDER BY r.start_line, r.start_col
"@ 'Get-DataSourceChain (re-pointing)'
    foreach ($s in $sites) {
      $rt = [string]$s.rt
      $fromRecv = ($rt -and -not $rt.StartsWith('.'))
      $ctx = Get-SourceContext $pasPath ([int]$s.line) ([int]$s.col) ([int]$s.ecol - [int]$s.col) $SourceOverride
      $ctl = ''; $from = ''
      if ($fromRecv) { $ctl = ($rt -split '\.')[0]; $from = 'receiver' }
      elseif (-not $ctx.Stale) {
        $bef = $ctx.Before -replace '\s', ''
        if ($bef -match '(?:^|[^A-Za-z0-9_.])([A-Za-z_][A-Za-z0-9_]*)\.(?:DataBinding|DataController|Properties)\.$') {
          $ctl = $Matches[1]; $from = 'source'
        }
      }
      if (-not $ctl -or ($names -notcontains $ctl)) { continue }
      $rhs = ''
      if (-not $ctx.Stale) {
        if ($ctx.After -notmatch '^\s*:=') { continue }   # a read of .DataSource is not a re-pointing
        $rhs = (($ctx.After -replace '^\s*:=', '') -split ';')[0].Trim()
      }
      [void]$repoint.Add([pscustomobject]@{
        Control = $ctl; ControlFrom = $from; Receiver = $rt; File = $pasPath; Line = [int]$s.line
        Routine = [string]$s.routine; Rhs = $rhs; Stale = $ctx.Stale
      })
    }
  }

  $o = [ordered]@{
    Form = $Form; FormFile = $dfmPath; PasFile = $pasPath; DsName = $DsName
    Module = ''; Dangling = $false; DataSource = $null
    Controls = $controls; RePointedAt = $repoint.ToArray()
    DataSetSites = @(); RhsType = $null
    CandidateTables = @(); BoundColumns = @(); ColumnMatch = @(); MissingColumns = @()
    ResolvedTable = $null; Grade = ''; Hops = $null; StopReason = ''
  }
  function Complete([string] $grade, [string] $stop) {
    $o.Grade = $grade; $o.StopReason = $stop; $o.Hops = $hops.ToArray()
    [pscustomobject]$o
  }

  # ---- hop 1: the datasource component -----------------------------------------
  $local = $DsName
  if ($DsName.Contains('.')) {
    $o.Module = $DsName.Substring(0, $DsName.LastIndexOf('.'))
    $local = $DsName.Substring($DsName.LastIndexOf('.') + 1)
    $mq = ConvertTo-SqlText $o.Module
    $mod = Invoke-IndexQuery "SELECT COUNT(*) AS n FROM symbols WHERE UPPER(name) = UPPER('$mq')"
    if ([int]$mod[0].n -eq 0) {
      $o.Dangling = $true
      $why = "module $($o.Module) is declared nowhere in this index (no form, var or symbol) -- a dangling designer reference"
      Add-Hop 'datasource' 'dangling' $DsName $dfmPath $(if ($controls.Count) { $controls[0].Line } else { 0 }) $why
      return (Complete 'dangling' $why)
    }
    $ds = Invoke-IndexQuery @"
SELECT c.id AS id, c.name AS name, c.qualified_name AS q, c.signature AS sig, c.start_line AS line, f.path AS path, c.file_id AS fid
  FROM symbols c JOIN files f ON f.id = c.file_id
 WHERE c.kind = 'component' AND UPPER(c.name) = UPPER('$(ConvertTo-SqlText $local)')
   AND c.file_id IN (SELECT r.file_id FROM symbols r WHERE r.kind = 'form' AND UPPER(r.name) = UPPER('$mq'))
"@
  } else {
    $ds = Invoke-IndexQuery @"
SELECT c.id AS id, c.name AS name, c.qualified_name AS q, c.signature AS sig, c.start_line AS line, f.path AS path, c.file_id AS fid
  FROM symbols c JOIN files f ON f.id = c.file_id
 WHERE c.kind = 'component' AND c.file_id = $dfmId AND UPPER(c.name) = UPPER('$dsq')
"@
  }
  if ($ds.Count -ne 1) {
    $why = if ($ds.Count -eq 0) { "no component named $local in $(if ($o.Module) { "module $($o.Module)" } else { [IO.Path]::GetFileName($dfmPath) })" }
           else { "$($ds.Count) components named $local -- cannot tell which" }
    Add-Hop 'datasource' 'unresolved' $DsName $dfmPath 0 $why
    return (Complete 'no-datasource' $why)
  }
  $d = $ds[0]
  $o.DataSource = [pscustomobject]@{ Id = [int]$d.id; Name = [string]$d.name; Qname = [string]$d.q
                                     Type = [string]$d.sig; File = [string]$d.path; Line = [int]$d.line }
  Add-Hop 'datasource' 'certain' "$($d.name): $($d.sig)" ([string]$d.path) ([int]$d.line) ''
  $dsFile = [string]$d.path
  $dsPas = if ([int]$d.fid -eq $dfmId) { $pasPath } else {
    $g = [IO.Path]::ChangeExtension($dsFile, '.pas')
    $h = @($shas.Keys | Where-Object { [string]::Equals($_, $g, [StringComparison]::OrdinalIgnoreCase) })
    if ($h.Count) { [string]$h[0] } else { $null }
  }

  # ---- bound columns (checked against candidates later) ------------------------
  $bindIds = @($controls | Where-Object { -not $_.IsLookup -and $_.ControlId } | ForEach-Object { $_.ControlId } | Sort-Object -Unique)
  if ($bindIds.Count) {
    $in = $bindIds -join ','
    $bc = Invoke-IndexQuery @"
SELECT DISTINCT UPPER(sl.text) AS col
  FROM string_literals sl JOIN symbols c ON c.id = sl.symbol_id
 WHERE sl.kind = 'dfm-prop'
   AND sl.owner_name IN ('DataBinding.FieldName','DataBinding.DataField','FieldName','DataField')
   AND (c.id IN ($in) OR c.parent_id IN ($in))
"@ 'Get-DataSourceChain (bound columns)'
    $o.BoundColumns = @($bc | ForEach-Object { [string]$_.col } | Where-Object { $_ } | Sort-Object)
  }

  # ---- hop 2: where the datasource gets its dataset ------------------------------
  $sites = New-Object System.Collections.ArrayList
  $dfmSet = Invoke-IndexQuery @"
SELECT sl.text AS t, sl.start_line AS line FROM string_literals sl
 WHERE sl.kind = 'dfm-prop' AND sl.owner_name = 'DataSet' AND sl.symbol_id = $([int]$d.id)
"@
  foreach ($x in $dfmSet) {
    [void]$sites.Add([pscustomobject]@{ Kind = 'dfm'; File = $dsFile; Line = [int]$x.line; Routine = ''; Rhs = [string]$x.t })
  }
  if ($dsPas) {
    $pid2 = $fileIds[$dsPas]
    $lq = ConvertTo-SqlText $local
    $code = Invoke-IndexQuery @"
SELECT r.start_line AS line, r.start_col AS col, r.end_col AS ecol, r.enclosing_symbol_id AS eid,
       encl.qualified_name AS routine
  FROM refs r LEFT JOIN symbols encl ON encl.id = r.enclosing_symbol_id
 WHERE r.file_id = $pid2 AND r.kind = 'member-access' AND r.name_text = 'DataSet'
   AND (UPPER(r.receiver_text) = UPPER('$lq') OR UPPER(r.receiver_text) LIKE UPPER('%.$lq'))
 ORDER BY r.start_line, r.start_col
"@ 'Get-DataSourceChain (dataset sites)'
    foreach ($x in $code) {
      $ctx = Get-SourceContext $dsPas ([int]$x.line) ([int]$x.col) ([int]$x.ecol - [int]$x.col) $SourceOverride -Following 5
      if ($ctx.Stale) {
        [void]$sites.Add([pscustomobject]@{ Kind = 'stale'; File = $dsPas; Line = [int]$x.line; Routine = [string]$x.routine; Rhs = ''; Eid = [int]$x.eid })
        continue
      }
      if ($ctx.After -match '^\s*:=') {
        $buf = $ctx.After -replace '^\s*:=', ''
        foreach ($f in $ctx.Following) { if ($buf -match ';') { break }; $buf += ' ' + $f }
        $rhs = (($buf -split ';')[0].Trim()) -replace '\s+', ''
        [void]$sites.Add([pscustomobject]@{ Kind = 'assign'; File = $dsPas; Line = [int]$x.line; Routine = [string]$x.routine; Rhs = $rhs; Eid = [int]$x.eid })
      } else {
        [void]$sites.Add([pscustomobject]@{ Kind = 'read'; File = $dsPas; Line = [int]$x.line; Routine = [string]$x.routine; Rhs = ''; Eid = [int]$x.eid })
      }
    }
  }
  $o.DataSetSites = $sites.ToArray()

  $staleSites = @($sites | Where-Object { $_.Kind -eq 'stale' })
  $assigns = @($sites | Where-Object { $_.Kind -eq 'assign' -and $_.Rhs -ne 'nil' })
  if ($staleSites.Count -and -not $assigns.Count) {
    $why = "$([IO.Path]::GetFileName($dsPas)) differs from the indexed copy -- its $($staleSites.Count) DataSet site(s) are not read"
    Add-Hop 'dataset' 'stale source' "$local.DataSet" $dsPas $staleSites[0].Line $why
    return (Complete 'stale source' $why)
  }
  if (-not $assigns.Count) {
    $dfmSite = @($sites | Where-Object { $_.Kind -eq 'dfm' })
    if ($dfmSite.Count) {
      $why = "the dataset $($dfmSite[0].Rhs) is set in the DFM; a designer dataset names no table this index can follow"
      Add-Hop 'dataset' 'certain' "DataSet = $($dfmSite[0].Rhs)" $dsFile $dfmSite[0].Line $why
      return (Complete 'dfm-dataset' $why)
    }
    $why = if ($sites.Count) { "$($sites.Count) DataSet site(s) in code, none assigns a dataset" }
           else { 'no DataSet assignment in the DFM or in the form unit' }
    Add-Hop 'dataset' 'unresolved' "$local.DataSet" $(if ($dsPas) { $dsPas } else { $dsFile }) 0 $why
    return (Complete 'no-assignment' $why)
  }
  $a0 = $assigns[0]
  Add-Hop 'dataset' 'inferred' "$local.DataSet := $($a0.Rhs)" $a0.File $a0.Line $(if ($staleSites.Count) { "$($staleSites.Count) other site(s) in a stale file not read" } else { '' })

  # ---- hop 3: the declared type of the RHS root ----------------------------------
  $root = ($a0.Rhs -replace '^Self\.', '' -split '[.\[(^]')[0]
  $rq = ConvertTo-SqlText $root
  $decl = Invoke-IndexQuery @"
SELECT s.kind AS kind, s.signature AS sig, s.parent_id AS pid
  FROM symbols s
 WHERE s.file_id = $pid2 AND UPPER(s.name) = UPPER('$rq')
   AND s.kind IN ('field','property','param','local_var','var','const')
"@
  $pick = @($decl | Where-Object { $_.pid -and [int]$_.pid -eq $a0.Eid })
  if (-not $pick.Count) { $pick = @($decl | Where-Object { $_.kind -in 'field', 'property' }) }
  if (-not $pick.Count) { $pick = @($decl) }
  if (-not $pick.Count) {
    $why = "$root is not declared in $([IO.Path]::GetFileName($dsPas))"
    Add-Hop 'rhs-type' 'unresolved' $root $dsPas $a0.Line $why
    return (Complete 'no-type' $why)
  }
  $typeName = (([string]$pick[0].sig) -replace '<.*$', '').Trim()
  $tq = ConvertTo-SqlText $typeName
  $ts = Invoke-IndexQuery @"
SELECT s.kind AS kind, s.start_line AS line, f.path AS path, s.file_id AS fid
  FROM symbols s JOIN files f ON f.id = s.file_id
 WHERE UPPER(s.name) = UPPER('$tq') AND s.kind IN ('class','interface','record')
"@
  $o.RhsType = [pscustomobject]@{ Rhs = $a0.Rhs; Root = $root; RootKind = [string]$pick[0].kind; TypeName = $typeName
                                  TypeKind = ''; TypeFile = $null; TypeLine = 0 }
  if ($ts.Count -ne 1) {
    $why = if ($ts.Count -eq 0) { "$root is a $typeName, which is not declared in this index (library type)" }
           else { "$typeName names $($ts.Count) types in this index -- cannot tell which" }
    Add-Hop 'rhs-type' 'unresolved' "${root}: $typeName" $dsPas $a0.Line $why
    return (Complete 'no-type' $why)
  }
  $o.RhsType.TypeKind = [string]$ts[0].kind; $o.RhsType.TypeFile = [string]$ts[0].path; $o.RhsType.TypeLine = [int]$ts[0].line
  Add-Hop 'rhs-type' 'by name' "${root}: $typeName" ([string]$ts[0].path) ([int]$ts[0].line) ''

  # ---- hop 4: table-name literals in the unit that declares that type ------------
  $inNames = ConvertTo-SqlInList $SqlSet.Names
  $lit = Invoke-IndexQuery @"
SELECT DISTINCT sl.text AS t FROM string_literals sl
 WHERE sl.file_id = $([int]$ts[0].fid) AND sl.kind IN ('literal','const') AND sl.text IN ($inNames)
"@ 'Get-DataSourceChain (table literals)'
  $o.CandidateTables = @($lit | ForEach-Object { [string]$_.t } | Sort-Object -Unique)
  $unit = [IO.Path]::GetFileName([string]$ts[0].path)
  $cand = $o.CandidateTables

  if ($cand.Count -eq 0) {
    $why = "$unit holds no string literal naming a table$(if ($o.RhsType.TypeKind -eq 'interface') { " ($typeName is an interface; its implementation is not followed)" })"
    Add-Hop 'table' 'unresolved' $typeName ([string]$ts[0].path) ([int]$ts[0].line) $why
    return (Complete 'none' $why)
  }
  $fits = @($cand | Where-Object { $t = $SqlSet.Tables[$_]; -not @($o.BoundColumns | Where-Object { -not $t.Columns.Contains($_) }).Count })
  if ($cand.Count -eq 1) {
    $o.ResolvedTable = $cand[0]
    $o.MissingColumns = @($o.BoundColumns | Where-Object { -not $SqlSet.Tables[$cand[0]].Columns.Contains($_) })
    Add-Hop 'table' 'inferred' $cand[0] ([string]$ts[0].path) ([int]$ts[0].line) "the only table-name literal in $unit"
    return (Complete 'one-table' '')
  }
  $o.ColumnMatch = $fits
  if ($o.BoundColumns.Count -and $fits.Count -eq 1) {
    $o.ResolvedTable = $fits[0]
    Add-Hop 'table' 'inferred' $fits[0] ([string]$ts[0].path) ([int]$ts[0].line) "$($cand.Count) tables named in $unit; only $($fits[0]) holds all $($o.BoundColumns.Count) bound column(s)"
    return (Complete 'by-columns' '')
  }
  $why = if (-not $o.BoundColumns.Count) { "$unit names $($cand.Count) tables and no column is bound through $local to tell them apart" }
         else { "$unit names $($cand.Count) tables; $($fits.Count) of them hold all $($o.BoundColumns.Count) bound column(s)" }
  Add-Hop 'table' 'unresolved' "$($cand.Count) candidates" ([string]$ts[0].path) ([int]$ts[0].line) $why
  Complete 'many' $why
}

# ---- exception paths: the ref classifier and the source-only scan -----------------
#
# THE KIND IS THE PRE-FILTER, THE SOURCE TOKEN IS THE CLASSIFIER (plan R1).
# `raise EFoo.Create(...)` emits a `read` on EFoo and `on E: EFoo do` a `type_use`
# -- but so do `EFoo.ClassName`, `EFoo(E).Code` and `var X: EFoo`. So a ref is a
# RAISE only when the stripped text before it ends in `raise` AND the text after
# it is `.Create...` (Create, CreateFmt, CreateRes, CreateHelp ...), and a HANDLE
# only when the text before it ends in `on` or `on <id>:`. Everything else is
# 'other': a declaration, an `is`/`as` test, a cast -- dropped from the picture
# and counted by the caller.
#
# `raise E;` (re-raising the caught OBJECT) also emits a `read` after `raise`,
# but on a VARIABLE: the text after it is `;`, not `.Create`, so it is 'other'
# here and is drawn by the source scan below as `raise <var>` -- a statement whose
# raised TYPE is not a fact of the index.
#
# A qualifier between the keyword and the name (`raise SysUtils.Exception.Create`)
# is skipped. When nothing precedes the ref on its line -- or only the handler
# variable, `E:` -- the clause began on the previous line, and that line's tail is
# read in front of it: `except on` / `E: EFoo do` is a handler (R12, and fix round 1
# finding 4: the earlier fallback fired only on an EMPTY prefix, so the split
# `on` / `E: T` form was missed). Measured 0 multi-line clauses on CLIENT.
#
# $Ctx is a Get-SourceContext result; a stale one returns 'stale' and is never
# classified (R11).
function Get-ExceptionRefClass($Ctx, [string] $Kind) {
  if ($Ctx.Stale) { return 'stale' }
  if ([string]::IsNullOrWhiteSpace([string]$Ctx.Token)) { return 'other' }
  $b = [regex]::Replace([string]$Ctx.Before, '(?:[A-Za-z_]\w*\s*\.\s*)+$', '')
  if ($b.Trim() -eq '' -or $b.Trim() -match '^[A-Za-z_]\w*\s*:$') { $b = [string]$Ctx.PrevLine + ' ' + $b.Trim() }
  if ($Kind -eq 'read' -and $b -match '\braise\s*$' -and [string]$Ctx.After -match '^\s*\.\s*Create\w*\b') {
    return 'raise'
  }
  if ($Kind -eq 'type_use' -and $b -match '\bon(\s+[A-Za-z_]\w*\s*:)?\s*$') { return 'handle' }
  'other'
}

# The SOURCE-ONLY exception rows of one line range (plan R2 / P9): statements
# that carry no identifier and therefore no ref -- they can only be found by
# reading source, so every row returned here is `[inferred]`:
#
#   bare-except   `except` whose next token (same or next non-blank line) is not `on`
#   on-except     `except` followed by `on` (counted, not drawn: its `on` clauses
#                 are ref-anchored HANDLE rows)
#   reraise       `raise;`, or `raise` followed by `else`/`end`/... or nothing
#   raise-var     `raise <ident>` NOT followed by `.` or `(` -- re-raises an object
#   raise-create  `raise X.Create...` (counted for the ref-vs-source comparison;
#                 the ref-anchored RAISE row is what is drawn)
#   raise-other   anything else after `raise` (`raise MakeError(...)`)
#
# Read over the comment/string/directive-STRIPPED text (Get-StrippedSourceLines),
# so a `raise` in a `{ ... }` block is not found -- P6's 7 commented-out raises.
# Directive STATE is not evaluated: code in an inactive `{$IFDEF}` branch inside
# the range is scanned like live code, and every drawn row says so.
#
# $Skip holds [int[]] line pairs (from, to) to leave out -- the bodies of nested
# routines, whose statements belong to THEM. A stale file returns Stale = $true
# and no rows (R11).
function Get-ExceptionSourceRows([string] $Path, [int] $From, [int] $To,
                                 [hashtable] $SourceOverride, $Skip) {
  if (-not (Test-SourceFresh $Path $SourceOverride)) {
    return [pscustomobject]@{ Path = $Path; Stale = $true; Rows = @() }
  }
  $lines = Get-StrippedSourceLines (Resolve-SourceReadPath $Path $SourceOverride)
  [pscustomobject]@{ Path = $Path; Stale = $false; Rows = (Get-ExceptionSourceRowsIn $lines $From $To $Skip) }
}

# The scan itself, over already-STRIPPED lines -- so a check can hand it a
# synthetic body. Get-ExceptionSourceRows is the fresh-file wrapper.
function Get-ExceptionSourceRowsIn([string[]] $lines, [int] $From, [int] $To, $Skip) {
  $rows = New-Object System.Collections.ArrayList
  $hi = [Math]::Min($To, $lines.Count)
  for ($ln = [Math]::Max($From, 1); $ln -le $hi; $ln++) {
    $skipIt = $false
    foreach ($s in @($Skip)) { if ($s -and $ln -ge $s[0] -and $ln -le $s[1]) { $skipIt = $true; break } }
    if ($skipIt) { continue }
    $t = $lines[$ln - 1]
    if ($t -notmatch '(?i)\b(except|raise)\b') { continue }
    foreach ($m in [regex]::Matches($t, '(?i)\b(except|raise)\b')) {
      $rest = $t.Substring($m.Index + $m.Length)
      if (-not $rest.Trim()) {
        $rest = ''
        for ($k = $ln; $k -lt $lines.Count; $k++) { if ($lines[$k].Trim()) { $rest = $lines[$k]; break } }
      }
      if ($m.Groups[1].Value -ieq 'except') {
        $kind = $(if ($rest -match '^\s*on\b') { 'on-except' } else { 'bare-except' })
        $what = 'except'
      } elseif ($rest -match '^\s*;' -or -not $rest.Trim() -or
                $rest -match '^\s*(else|end|until|except|finally)\b') {
        $kind = 'reraise'; $what = 'raise'
      } elseif ($rest -match '^\s*[A-Za-z_][\w\s\.]*?\.\s*Create\w*\b') {
        $kind = 'raise-create'; $what = 'raise'
      } elseif ($rest -match '^\s*([A-Za-z_]\w*)(?>\s*)(?![\.\(\w])') {
        # atomic whitespace: `raise Foo (x)` must not backtrack into a match
        $kind = 'raise-var'; $what = "raise $($Matches[1])"
      } else {
        $kind = 'raise-other'; $what = 'raise'
      }
      [void]$rows.Add([pscustomobject]@{ Kind = $kind; Line = $ln; Col = $m.Index + 1; Text = $what })
    }
  }
  , $rows.ToArray()
}

# THE EXCEPTION-TYPE NAME FILTER, in one place. It decides only what is COUNTED
# as a reference to an exception type -- the index-wide line on the focus box
# and the per-body "declarations or tests" disclosure. It never decides a RAISE
# or a HANDLE row: those come from the source token (R1), over EVERY read and
# type_use in the body, so `raise EdxException.Create` is not lost to it.
#
# A name qualifies when it is `E<Capital>...` with at least one lower-case letter,
# or `Exception` (plan P2), and this index does not declare it ONLY as something
# other than a class (P5):
#   * the lower-case letter keeps out the all-capitals Windows constants
#     (`ERROR_SUCCESS`, `EM_SETSEL`) and DB-column properties (`EDTLL1`) --
#     without it the CLIENT set is 1,109 refs, not 430 (measured 2026-09-23);
#   * the declared-kind rule drops `EOPart` (local), `EWclassconv` (const) and
#     `ET` (local x9) on CLIENT, and SERVER's `ERollback` -- the VARIABLE of
#     `on ERollback: Exception do`, 798 rows. A name with at least one class
#     declaration stays.
# Get-ExceptionNameSql is the SQL pre-filter; Test-ExceptionTypeName the full test.
function Get-ExceptionNameSql([string] $Column) {
  "($Column GLOB 'E[A-Z]*[a-z]*' OR $Column = 'Exception')"
}
function Test-ExceptionTypeName([string] $Name) {
  if ($Name -cnotmatch '^(E[A-Z]\w*[a-z]\w*|Exception)$') { return $false }
  if (-not $script:DlExcNonClass) { $script:DlExcNonClass = @{} }
  if (-not $script:DlExcNonClass.ContainsKey($DbPath)) {
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($r in (Get-AllIndexRows @"
SELECT name AS name FROM symbols
 WHERE $(Get-ExceptionNameSql 'name')
 GROUP BY name HAVING SUM(kind = 'class') = 0
"@ 'name')) { [void]$set.Add([string]$r.name) }
    $script:DlExcNonClass[$DbPath] = $set
  }
  -not $script:DlExcNonClass[$DbPath].Contains($Name)
}

# The try-blocks of one routine span, from a NESTING scan of the comment-stripped
# lines (controller ruling R10, fix round 1). A caller's handler catches an
# exception from a call only when the call sits between that block's `try` and
# its `except` -- a handler elsewhere in the body guards something else. Measured
# 2026-09-23: both `on E: EDatabaseError` handlers above BuildSchema guard only
# LoadFromStream, and BuildSchema is called outside their try.
#
# $Lines are STRIPPED lines (Get-StrippedSourceLines), so a keyword inside a
# comment or a string is already blank. Tokens: begin / case / record / asm /
# try push; end pops; except / finally mark the innermost open `try`; `on`
# directly in an except part is a handler clause. A `case` inside a `record` is
# the variant part and has no `end` of its own. Inside `asm` only `end` counts.
# A token after `.` or `&` is an identifier, not a keyword.
#
# NOT DECIDED is a result, not an error: an `end` with nothing open, an
# `except`/`finally` whose innermost open block is not a `try`, or anything left
# open at the end of the span (a local `class` type -- its `end` has no opener
# here -- does exactly that). The caller then may not claim containment either
# way, and draws the handler as unverified.
#
# Positions are line * 100000 + column, so one integer compares both.
# Returns Decided, Reason, Blocks[] { Try, Except (0 = none), Finally (0), End,
# On[] (positions of the `on` clauses in the except part) }.
function Get-TryBlocks([string[]] $Lines, [int] $From, [int] $To) {
  $rx = [regex]'(?i)(?<![\w&\.])(begin|end|case|record|asm|try|except|finally|on)\b'
  $stack = New-Object System.Collections.ArrayList
  $blocks = New-Object System.Collections.ArrayList
  $hi = [Math]::Min($To, $Lines.Count)
  $fail = $null
  for ($ln = [Math]::Max($From, 1); $ln -le $hi -and -not $fail; $ln++) {
    foreach ($m in $rx.Matches($Lines[$ln - 1])) {
      $w = $m.Groups[1].Value.ToLowerInvariant()
      $pos = $ln * 100000 + $m.Index + 1
      $top = $(if ($stack.Count) { $stack[$stack.Count - 1] } else { $null })
      if ($top -and $top.Kind -eq 'asm' -and $w -ne 'end') { continue }
      switch ($w) {
        'end' {
          if (-not $top) { $fail = "an ``end`` at line $ln closes nothing"; break }
          $stack.RemoveAt($stack.Count - 1)
          if ($top.Kind -eq 'try') {
            [void]$blocks.Add([pscustomobject]@{
              Try = $top.Pos; Except = $top.Except; Finally = $top.Finally; End = $pos; On = $top.On.ToArray() })
          }
        }
        { $_ -in 'except', 'finally' } {
          if (-not $top -or $top.Kind -ne 'try' -or $top.Except -or $top.Finally) {
            $fail = "``$w`` at line $ln has no open try"; break
          }
          if ($w -eq 'except') { $top.Except = $pos } else { $top.Finally = $pos }
        }
        'on' {
          if ($top -and $top.Kind -eq 'try' -and $top.Except) { [void]$top.On.Add($pos) }
        }
        'case' {
          if (-not ($top -and $top.Kind -eq 'record')) {
            [void]$stack.Add([pscustomobject]@{ Kind = 'case'; Pos = $pos })
          }
        }
        default {
          [void]$stack.Add([pscustomobject]@{
            Kind = $w; Pos = $pos; Except = 0; Finally = 0; On = (New-Object System.Collections.ArrayList) })
        }
      }
      if ($fail) { break }
    }
  }
  if (-not $fail -and $stack.Count) { $fail = "$($stack.Count) block(s) still open at the end of the span" }
  [pscustomobject]@{ Decided = (-not $fail); Reason = $fail; Blocks = $(if ($fail) { @() } else { $blocks.ToArray() }) }
}

# The innermost try-block whose EXCEPT part holds position $Pos.
function Find-HandlerBlock($Tb, [int] $Pos) {
  $best = $null
  foreach ($b in $Tb.Blocks) {
    if ($b.Except -and $b.Except -le $Pos -and $Pos -lt $b.End) {
      if (-not $best -or $b.Except -gt $best.Except) { $best = $b }
    }
  }
  $best
}

# Does the handler at $Pos re-raise what it caught (ruling R10)? $Blk is the
# Get-TryBlocks block whose except part holds it; $Bare means $Pos is that
# block's bare `except`. The handler body runs from its `on` to the next `on` of
# the same except part (or the block's `end`); a bare except's is the whole
# except part. Re-raise = `raise;` (or `raise` before else/end), or `raise V`
# where V is the handler's own variable (`on V: T do`). Raising a NEW exception
# is not a re-raise: the caught one stopped there. Line-granular: two `on`
# clauses sharing one line share one body.
function Test-HandlerReraises([string[]] $Lines, $Blk, [int] $Pos, [bool] $Bare) {
  $var = $null
  if ($Bare) {
    $a = [int][Math]::Floor($Blk.Except / 100000); $b = [int][Math]::Floor($Blk.End / 100000)
  } else {
    $on = @($Blk.On | Where-Object { $_ -le $Pos } | Sort-Object)
    if (-not $on.Count) { return $false }
    $on = $on[-1]
    $nx = @($Blk.On | Where-Object { $_ -gt $Pos } | Sort-Object)
    $a = [int][Math]::Floor($on / 100000)
    $b = $(if ($nx.Count) { [int][Math]::Max($a, [Math]::Floor($nx[0] / 100000) - 1) } else { [int][Math]::Floor($Blk.End / 100000) })
    $txt = $Lines[$a - 1].Substring(($on % 100000) - 1)
    if ($txt -match '(?i)^on\s+([A-Za-z_]\w*)\s*:') { $var = $Matches[1] }
  }
  $rows = Get-ExceptionSourceRowsIn $Lines $a $b $null
  @($rows | Where-Object {
      $_.Kind -eq 'reraise' -or ($var -and $_.Kind -eq 'raise-var' -and $_.Text -ieq "raise $var") }).Count -gt 0
}

# The INDEX-WIDE exception candidates of $DbPath, classified -- the pre-check and
# the "approximately N raise sites / M handlers" line on the exception-paths
# focus. Candidates are the refs of ANY kind passing Test-ExceptionTypeName;
# each is classified by Get-ExceptionRefClass (a `call` or `member-access` cast
# is therefore always 'other' -- dropped and counted).
#
# Returns Candidates, Raise, Handle, Dropped, Stale, RaiseRoutines,
# HandleRoutines, Files, FreshFiles. Cached per DB per override per run
# (CLIENT: 425 source contexts, ~3 s).
function Get-ExceptionIndexStats([hashtable] $SourceOverride) {
  if (-not $script:DlExcStats) { $script:DlExcStats = @{} }
  $key = "$DbPath|$(if ($SourceOverride) { (@($SourceOverride.Keys | ForEach-Object { "$_=$($SourceOverride[$_])" }) | Sort-Object) -join ';' })"
  if ($script:DlExcStats.ContainsKey($key)) { return $script:DlExcStats[$key] }
  $cand = Get-AllIndexRows @"
SELECT r.id AS id, r.kind AS kind, r.name_text AS name, r.start_line AS line,
       r.start_col AS col, r.end_col AS ecol, r.enclosing_symbol_id AS encl, f.path AS path
  FROM refs r JOIN files f ON f.id = r.file_id
 WHERE $(Get-ExceptionNameSql 'r.name_text')
"@ 'r.id'
  $cand = @($cand | Where-Object { Test-ExceptionTypeName ([string]$_.name) })
  $n = @{ raise = 0; handle = 0; other = 0; stale = 0 }
  $rr = @{}; $hr = @{}; $files = @{}
  foreach ($r in $cand) {
    $p = [string]$r.path
    if (-not $files.ContainsKey($p)) { $files[$p] = Test-SourceFresh $p $SourceOverride }
    $c = Get-SourceContext $p ([int]$r.line) ([int]$r.col) ([int]$r.ecol - [int]$r.col) $SourceOverride
    $cls = Get-ExceptionRefClass $c ([string]$r.kind)
    $n[$cls]++
    if ($r.encl) {
      if ($cls -eq 'raise')  { $rr[[int]$r.encl] = $true }
      if ($cls -eq 'handle') { $hr[[int]$r.encl] = $true }
    }
  }
  $o = [pscustomobject]@{
    Candidates = $cand.Count; Raise = $n.raise; Handle = $n.handle
    Dropped = $n.other; Stale = $n.stale
    RaiseRoutines = $rr.Count; HandleRoutines = $hr.Count
    Files = $files.Count; FreshFiles = @($files.Values | Where-Object { $_ }).Count
  }
  $script:DlExcStats[$key] = $o
  $o
}

# ---- dot --------------------------------------------------------------------

# ONE layout run, four outputs -- so the geometry in .plain can never drift from
# the picture in .svg. Verified 2026-09-22.
function Invoke-DotLayout([string] $DotText, [string] $OutDir, [string] $Base) {
  New-Item -ItemType Directory -Force $OutDir | Out-Null
  $dotO = Join-Path $OutDir "$Base.dot"
  $svgO = Join-Path $OutDir "$Base.svg"
  $plnO = Join-Path $OutDir "$Base.plain"
  $pngO = Join-Path $OutDir "$Base.png"
  $pdfO = Join-Path $OutDir "$Base.pdf"
  foreach ($f in @($svgO, $plnO, $pngO, $pdfO)) { if (Test-Path $f) { Remove-Item $f -Force } }

  [IO.File]::WriteAllText($dotO, ($DotText -replace "`r`n", "`n" -replace "`n", "`r`n"),
                          (New-Object Text.UTF8Encoding($false)))

  & $Dot -Tsvg -o $svgO -Tplain -o $plnO -Tpng -Gdpi=110 -o $pngO -Tpdf -o $pdfO $dotO 2>&1 |
    Where-Object { $_ -notmatch 'Pango-WARNING' -and ([string]$_).Trim() -ne '' } |
    ForEach-Object { Write-Host "  dot: $_" }

  if (-not (Test-Path $svgO)) { throw 'dot produced no SVG' }
  $svg = [IO.File]::ReadAllText($svgO)

  [pscustomobject]@{
    Dot = $dotO; Svg = $svgO; Plain = $plnO; Png = $pngO; Pdf = $pdfO
    Anchors = ([regex]::Matches($svg, '<a[\s>]')).Count
  }
}

# Shared rounded-cluster builder. The cluster carries NO label -- Graphviz draws
# a cluster label inside the border and the rounded corner cuts through it; the
# title is a header ROW of the table instead.
#
# $Rows: objects with Label, Line, Href, Tip and optional Note (dimmed suffix).
# Returns the port id assigned to each row, IN ORDER, so callers can key the
# port map by ORDINAL. Keying by name is wrong: one method legitimately appears
# at two different call sites.
#
# -Title/-Subtitle/-Note take PLAIN TEXT and are escaped here. The middot
# separators are emitted OUTSIDE the escape on purpose: passing "a &#183; b" as
# a title would escape the ampersand and render the literal text "&#183;".
# -Style allows "rounded,filled,dashed" for a cluster whose rows are NOT facts
# of the same grade as the solid ones.
function Add-RowCluster {
  param(
    [System.Text.StringBuilder] $Sb, [string] $Cid, [string] $Nid,
    [string] $Title, [string] $Subtitle,
    $Rows, [string] $Border, [string] $Fill, [string] $Hdr,
    [string] $RowInk = '#1F2933', [string] $LineInk = '#8A94A6',
    [string] $FontSans = 'Segoe UI', [string] $Style = 'rounded,filled',
    [int] $PenWidth = 2
  )
  [void]$Sb.AppendLine("  subgraph $Cid {")
  [void]$Sb.AppendLine("    style=`"$Style`"; color=`"$Border`"; fillcolor=`"$Fill`"; penwidth=$PenWidth;")
  [void]$Sb.AppendLine('    label=""; margin=10;')

  $hdrText = ConvertTo-XmlText $Title
  if ($Subtitle) { $hdrText += ' &#183; ' + (ConvertTo-XmlText $Subtitle) }

  $tbl = New-Object System.Text.StringBuilder
  [void]$tbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="5">')
  [void]$tbl.Append("<TR><TD ALIGN=`"LEFT`" BGCOLOR=`"$Hdr`"><FONT COLOR=`"#FFFFFF`" FACE=`"$FontSans`" POINT-SIZE=`"14`"><B> $hdrText </B></FONT></TD></TR>")

  $ports = New-Object System.Collections.ArrayList
  $p = 0
  foreach ($r in $Rows) {
    # An empty row is always a dot SYNTAX ERROR ("<FONT ...></FONT>" in a TD)
    # and kills the whole layout. THROW rather than skip: the port map is keyed
    # by ORDINAL, so quietly dropping a row would shift every port after it and
    # mis-attach the edges -- a wrong picture instead of no picture. The usual
    # cause is nesting a `, $array` return inside @().
    if ($null -eq $r -or ([string]::IsNullOrWhiteSpace([string]$r.Label) -and
                          [string]::IsNullOrWhiteSpace([string]$r.Href))) {
      throw "Add-RowCluster ($Cid): row $($p + 1) is empty -- did a `, `$array` return get wrapped in @()?"
    }
    $p++
    # A row with NO Href is a note/disclosure line. It must carry neither HREF
    # nor TITLE: HREF="" still makes dot emit an <a>, which both inflates the
    # anchor count the emitters assert on and offers the reader a dead link.
    # It KEEPS its port, so the caller's ordinal port map stays aligned.
    if ([string]::IsNullOrWhiteSpace([string]$r.Href)) {
      [void]$tbl.Append("<TR><TD PORT=`"p$p`" ALIGN=`"LEFT`"><FONT COLOR=`"$LineInk`" POINT-SIZE=`"12`">$(ConvertTo-XmlText $r.Label)</FONT></TD></TR>")
      [void]$ports.Add("${Nid}:p$p")
      continue
    }
    [void]$tbl.Append("<TR><TD PORT=`"p$p`" ALIGN=`"LEFT`" HREF=`"$($r.Href)`" TITLE=`"$(ConvertTo-XmlText $r.Tip)`">")
    [void]$tbl.Append("<FONT COLOR=`"$RowInk`">$(ConvertTo-XmlText $r.Label)</FONT>")
    [void]$tbl.Append("  <FONT COLOR=`"$LineInk`" POINT-SIZE=`"12`">:$($r.Line)</FONT>")
    $note = $null
    if ($r.PSObject.Properties.Name -contains 'Note') { $note = [string]$r.Note }
    if ($note) {
      [void]$tbl.Append("  <FONT COLOR=`"$LineInk`" POINT-SIZE=`"11`">&#183; $(ConvertTo-XmlText $note)</FONT>")
    }
    [void]$tbl.Append('</TD></TR>')
    [void]$ports.Add("${Nid}:p$p")
  }
  [void]$tbl.Append('</TABLE>')
  [void]$Sb.AppendLine("    $Nid [label=<$($tbl.ToString())>];")
  [void]$Sb.AppendLine('  }')
  , $ports.ToArray()
}
