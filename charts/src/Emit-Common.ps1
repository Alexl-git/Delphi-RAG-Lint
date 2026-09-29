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
# v=1.17.0-alpha / r=1.6.0-alpha. The engine deployed in this worktree was
# 1.16.0-alpha with resolver 1.5.1-alpha -- OLDER on two axes -- and
# RefuseIfEngineOlderThanDb does not cover the resolver axis, so nothing
# refuses. The skew yields SMALLER CONFIDENT ANSWERS, never an error. Since
# 2026-09-27 the charts run the SHARED engine
# (C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe -- 1.18.x-1.19.x over the
# trace-core branch; reads on the r=1.9 clones measured byte-identical between them), and the clones under scratch\db were re-taken on
# 2026-09-28 18:17-18:18 (DL first) and carry v=1.20.0-alpha / r=1.11.0-alpha (schema_meta,
# checked at the resolver-1.11 re-baseline).
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
# holds HISTORY: `*.sqlite.pre-1.10`, `*.sqlite.pre-1.9`, `*.sqlite.pre-1.19`, `*.sqlite.pre-1.18` and
# `*.sqlite.pre-reindex-0530` are byte-for-byte older clones kept for comparison
# (`pre-1.10` = the v=1.19 / r=1.9 set, before the 2026-09-28 re-take;
# `pre-1.9` = the resolver-1.8 set, before the 2026-09-27 re-take), plus
# `DL-drag-lint.sqlite.withheld-2145` (a first DL copy whose resolver had
# withheld every call edge of the 20 units edited since their parse). They sit
# under the root, so the whitelist alone ACCEPTS them -- and a 562-file pre-1.18 CLIENT answers every
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
           'history copies (*.sqlite.pre-1.10, *.sqlite.pre-1.9, *.sqlite.pre-1.19, *.sqlite.pre-1.18, *.sqlite.pre-reindex-0530) beside the live clones, and ' +
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
         'A live DB can be re-indexed mid-run, so an asserted count would not be reproducible; ' +
         'the clones (v=1.20.0-alpha / r=1.11.0-alpha) freeze it. Set DRAGLINT_CHARTS_ALLOW_LIVE_DB=1 ' +
         'to override deliberately.')
}

# ---- engine -----------------------------------------------------------------

# ---- FAIL LOUDLY (controller ruling R19, 2026-09-23) ------------------------
# These wrappers used to merge stderr, DROP it, record $LASTEXITCODE and never
# check it, and return '' on an empty stdout -- which Invoke-IndexQuery turned
# into ZERO ROWS. So a failed query read as an empty answer. Reproduced: under
# 12 concurrent readers one sql call exited 3 with `FATAL: ... database is
# locked`; a time-cap hit exits 1 with `ERROR: stopped -- the query hit the
# 10000 ms time cap`; a bad table name exits 1 with `ERROR: ... no such table`.
# All three came back as rows=0. That is what graded one datasource
# `no-assignment` in a battery run that overlapped the gallery (48 vs 49).
#
# Now: stderr is KEPT; any non-zero exit THROWS, quoting the exit code and the
# engine's own messages. The one exception is a verb's documented NO-MATCH
# result (-AllowNoMatch): `query find-callers|ancestors|descendants` exit 1
# when nothing matches, with empty stdout or an empty JSON document. Measured
# 2026-09-23 on this engine: the no-match case writes NOTHING to stderr beyond
# the informational notes, while every failure writes an `ERROR:` / `FATAL:`
# line. So no-match is recognised by its stderr TEXT (only notes), never by the
# exit code alone.
#
# `database is locked` is retried, bounded: 3 attempts, 250/750 ms backoff, only
# for that exact text; the last failure still throws.

# stderr lines that are information, not failure
$script:EngineNoteRx = '^\(?loaded defaults|^drag-lint:|^\s+may be stale|^\s+drag-lint index |^\s*resolver:'

# Runs the engine; returns its stdout TEXT with the informational lines removed.
# Throws on any non-zero exit unless -AllowNoMatch and the exit is a no-match.
# $script:LastEngineExit keeps the exit code; $script:LastEngineNoMatch is set
# when the result was accepted as a no-match.
function Invoke-EngineRaw([string[]] $ArgList, [switch] $AllowNoMatch) {
  $delays = @(250, 750)
  for ($try = 1; ; $try++) {
    $out = New-Object System.Collections.ArrayList
    $err = New-Object System.Collections.ArrayList
    foreach ($item in (& $Engine @ArgList 2>&1)) {
      if ($item -is [System.Management.Automation.ErrorRecord]) { [void]$err.Add([string]$item.Exception.Message) }
      else { [void]$out.Add([string]$item) }
    }
    $exit = $LASTEXITCODE
    $script:LastEngineExit = $exit
    $script:LastEngineNoMatch = $false
    # the same notes can reach stdout when a host merges the streams
    $stdout = @($out | Where-Object { $_ -notmatch $script:EngineNoteRx })
    $stderr = @($err | Where-Object { $_.Trim() -ne '' -and $_ -notmatch $script:EngineNoteRx })
    if ($exit -eq 0) { return ($stdout -join "`n") }

    if ($AllowNoMatch -and $exit -eq 1 -and $stderr.Count -eq 0 -and
        -not (@($stdout) -match '^\s*(ERROR|FATAL)\b')) {
      $script:LastEngineNoMatch = $true
      return ($stdout -join "`n")
    }
    $msg = (@($stderr) + @($stdout | Where-Object { $_ -match '^\s*(ERROR|FATAL)\b' })) -join ' | '
    if ($msg -match 'database is locked' -and $try -le $delays.Count) {
      Write-Host "  NOTE: engine reported 'database is locked' (attempt $try of $($delays.Count + 1)); retrying"
      Start-Sleep -Milliseconds $delays[$try - 1]
      continue
    }
    # The phrase "engine returned nothing for" is kept when there is no document
    # at all: the N1 negative asserts it, and it is still true.
    $doc  = ($stdout -join ''); $what = if ($doc.IndexOf('{') -lt 0 -and $doc.IndexOf('[') -lt 0) { 'engine returned nothing for' } else { 'engine failed for' }
    throw "$what drag-lint $($ArgList -join ' ') (exit $exit): $(if ($msg) { $msg } else { '(no message)' })"
  }
}

# Runs the engine and returns ONLY the JSON document, or '' when there is none
# (a no-match under -AllowNoMatch, or a verb that printed no document).
function Get-EngineText([string[]] $ArgList, [switch] $AllowNoMatch) {
  $txt = Invoke-EngineRaw $ArgList -AllowNoMatch:$AllowNoMatch
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
  # R19: an EMPTY answer is never zero rows. A real zero-row result is a whole
  # sql/1 document with row_count 0; anything else is a failure, and says so.
  if ([string]::IsNullOrWhiteSpace($txt)) { throw "index query returned no document (exit $script:LastEngineExit): $sql" }
  try { $o = $txt | ConvertFrom-Json } catch { throw "index query returned non-JSON: $txt" }
  if ([string]$o.schema -ne 'sql/1') { throw "index query returned schema '$($o.schema)', expected sql/1: $sql" }
  if (@($o.rows).Count -ne [int]$o.row_count) {
    throw "index query returned $(@($o.rows).Count) row(s) but row_count $($o.row_count) -- a partial document: $sql"
  }
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
# `find-callers --resolved` answers only half of this. Up to engine 1.16 its
# `line` was the caller's DECLARATION line; since 1.18 (measured 2026-09-27)
# `line` is the CALL SITE and the declaration moved to `caller_line`. It still
# gives no COLUMN, and three accesses can share a line, which is why a site
# anchor needs SQL at all.
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
#
# $Text is PLAIN TEXT and is escaped here, with ONE exception: the '&#183;'
# middle-dot separator survives the escape. Nine call sites in seven emitters
# pass it, and until 2026-09-24 every one of them printed the six literal
# characters "&#183;" (Add-RowCluster's header comment warns of the same trap).
# Gate: E-ENTITY sweeps every .dot a test run writes.
function Add-DisclosureRow([System.Text.StringBuilder] $Table, [string] $Text,
                           [string] $Ink = '#8A94A6', [int] $PointSize = 12) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return }
  $body = (ConvertTo-XmlText $Text).Replace('&amp;#183;', '&#183;')
  [void]$Table.Append("<TR><TD ALIGN=`"LEFT`"><FONT COLOR=`"$Ink`" POINT-SIZE=`"$PointSize`">$body</FONT></TD></TR>")
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
#
# THE KNOWN GAP IN THAT RULE (Task 0 review, measured 2026-09-23): the winner is
# not a superset. On the 1.18 clone 12 column names across 10 tables were
# EXTRACTED only from the older MScript2.SQL copy -- OPTORID on 8 tables,
# GONOFF.OFF, MET1.NOTE, IPCHART.ACTION and IPCHART.OPTRID. At least one was
# LIVE: live Firebird IPCHART has 137 columns, the 1.18 winner had 136 extracted,
# and the missing one was ACTION -- which the newest MS1.SQL DOES declare, at
# :2243, as the QUOTED identifier "ACTION", which the 1.18 SQL extractor dropped
# (engine D19, INBOX-sql-index-drops-quoted-identifiers.md). Of the 12, only
# IPCHART.ACTION was quoted in the newest declaration; the other 11 are not in
# it at all. So "not extracted from the winning declaration" does NOT mean "not
# in the database". Each table carries such names in .OlderOnlyColumns, and
# Get-SqlColumnState below decides what a chart says about such a column.
# ENGINE D19 FIXED (extractor 1.19, re-baseline 2026-09-24): the extractor now
# emits a sql_column for a quoted name -- IPCHART.ACTION and FOLDERCOUNT.TABLE
# are extracted from MS1.SQL, so the newest IPCHART has 137 columns, matching
# live Firebird, and 11 older-only names remain (none quoted in the newest).
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
    # column name -> the first (newest) LOSING declaration that carries it, for
    # names the winner lacks (see THE KNOWN GAP above)
    $older = [ordered]@{}
    foreach ($d in @($ordered | Select-Object -Skip 1)) {
      if (-not $cols.ContainsKey([int]$d.id)) { continue }
      foreach ($c in $cols[[int]$d.id]) {
        if (-not $set.Contains($c) -and -not $older.Contains($c.ToUpperInvariant())) {
          $older[$c.ToUpperInvariant()] = [pscustomobject]@{ Column = $c; File = [string]$d.path; Line = [int]$d.line }
        }
      }
    }
    $tables[[string]$win.name] = [pscustomobject]@{
      Name = [string]$win.name; Id = [int]$win.id; File = [string]$win.path; Line = [int]$win.line
      DeclCount = $g.Count
      Declarations = @($ordered | ForEach-Object {
        [pscustomobject]@{ Id = [int]$_.id; File = [string]$_.path; Line = [int]$_.line
                           Columns = $(if ($cols.ContainsKey([int]$_.id)) { $cols[[int]$_.id].Count } else { 0 }) } })
      Columns = $set; ColumnNames = $names
      OlderOnlyColumns = $older
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

# ---- THE column state: ONE function for consumers, feeds-from and lands-where ------
#
# Whether COL is a column of T, and on what evidence, is decided HERE so the
# three verbs that ask it cannot disagree (final wave, item 1: consumers refused
# FOLDERCOUNT.TABLE while lands-where anchored it). What the SQL INDEX extracts
# is not everything the scripts declare: MS1.SQL declares FOLDERCOUNT."TABLE"
# (:3848) and IPCHART."ACTION" (:2243) as QUOTED identifiers, and the extractor
# emitted no sql_column for a quoted name (engine D19, FIXED in extractor 1.19:
# both are now extracted, so both are state `yes`). So a chart never says "not
# in the scripts": it says what was read -- "not extracted as a column by the
# SQL index" -- after the newest declaration's own source was scanned. The
# `quoted` state stays as a guard (R25): no real column reaches it on the 1.19
# clones, and the gate drives it with a hand-made table set (A-COLSTATE-QUOTED).
#
# THE `yes` ANCHOR IS THE ENGINE'S sql_column start_line -- since extractor 1.20
# the column's own declaring line (CAUSFAIL.REASON :1411, FOLDERCOUNT.TABLE
# :3848). On the 1.18 and 1.19 clones it was ONE LINE EARLY for a column on its
# own line (the node started right after the previous token: 1410:45, 3847:27);
# reported at the 1.19 re-baseline, fixed by the engine, re-pinned 2026-09-28.
#
# States, in precedence order:
#   yes         extracted as a column of the NEWEST declaration   [certain]
#   quoted      a quoted identifier in the newest declaration's fresh source
#               [inferred -- source scan]
#   older       extracted only from an OLDER declaration (THE KNOWN GAP above)
#   server-sql  none of those, but the caller's own SQL for T names it
#               (-ServerSqlHit: File, Line, Routine)                [inferred]
#   stale       none of those, and the newest declaration's script differs from
#               the indexed copy: the quoted scan was NOT run, so the answer is
#               UNKNOWN -- rendered [stale source], never as an absence (R11)
#   no          not extracted, not quoted in the newest declaration, and -- when
#               the caller names what it searched in -SqlSearched -- named by
#               none of that SQL
# quoted is tried BEFORE older: IPCHART.ACTION is extracted only from the older
# MScript2.SQL, but the newest MS1.SQL declares it (quoted) -- the newest is the
# declaration R8 trusts, so that is where the column is anchored.
#
# Returns Table, Column (upper case), State, IsColumn, File, Line (the anchor),
# Text (the quoted source line), Label (the grade and evidence every verb prints,
# so the three read the same), OlderFile / OlderLine (an older declaration that
# extracts it, when one does), QuotedScan ('hit' | 'none' | 'stale' | '' when not
# needed). $SqlSet is Get-SqlTableSet's object; T must be one of its tables.

# TEST HOOKS for the `quoted` state (R25, fix round 1). Extractor 1.19 extracts
# every quoted name, so no real column reaches `quoted` -- and a doctored copy of
# a script cannot stand in for it: it is stale by construction (R11) and renders
# [stale source], never quoted. So the gate takes the column back OUT of the
# newest declaration's extracted names -- the 1.18 extractor's shape -- and lets
# the real, FRESH script be scanned. A COPY is returned; the cached set is untouched.
# $Older, when given, restores an older-only extraction ({Column; File; Line}).
function Copy-SqlTableWithout($Tbl, [string] $Col, $Older) {
  $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($c in $Tbl.Columns) { if ($c -ne $Col) { [void]$set.Add($c) } }
  $old = [ordered]@{}; foreach ($k in $Tbl.OlderOnlyColumns.Keys) { $old[$k] = $Tbl.OlderOnlyColumns[$k] }
  if ($Older) { $old[$Col.ToUpperInvariant()] = $Older }
  [pscustomobject]@{ Name = $Tbl.Name; Id = $Tbl.Id; File = $Tbl.File; Line = $Tbl.Line; DeclCount = $Tbl.DeclCount
                     Declarations = $Tbl.Declarations; Columns = $set
                     ColumnNames = [string[]]@($Tbl.ColumnNames | Where-Object { $_ -ne $Col })
                     OlderOnlyColumns = $old }
}
# feeds-from's column-hop label: a quoted column keeps its quotes. Moved here
# (fix round 1) so the gate can drive the quoted branch: no field-bound control in
# this corpus names TABLE or ACTION (0 DFM DataField/FieldName literals), so no
# feeds-from chain can end on a quoted column, even with a column hidden.
function Get-ColumnHopLabel($ColumnState) {
  if ($ColumnState.State -eq 'quoted') { "column `"$($ColumnState.Column)`"" } else { "column $($ColumnState.Column)" }
}

# $TableColumns: 'TABLE.COLUMN' names to hide; throws on one the set does not extract.
function Hide-ExtractedColumns($SqlSet, [string[]] $TableColumns) {
  $o = $SqlSet.PSObject.Copy()
  $tabs = @{}; foreach ($k in $SqlSet.Tables.Keys) { $tabs[$k] = $SqlSet.Tables[$k] }
  foreach ($tc in $TableColumns) {
    $p = $tc.Split('.')
    if ($p.Count -ne 2 -or -not $tabs.ContainsKey($p[0]) -or -not $tabs[$p[0]].Columns.Contains($p[1])) {
      throw "Hide-ExtractedColumns: $tc is not an extracted column of the SQL index"
    }
    $tabs[$p[0]] = Copy-SqlTableWithout $tabs[$p[0]] $p[1] $null
  }
  $o.Tables = $tabs
  # DOCTORED (fix round 2): the copy keeps .Db, so a cache keyed on .Db would file
  # this set's answers under the REAL database -- Get-FieldBindingChains neither
  # reads nor writes its process-wide cache for a doctored set.
  $o | Add-Member -NotePropertyName Doctored -NotePropertyValue $true -Force
  $o
}

# The cheap test, no source read: extracted from the newest declaration, or from
# an older one. Get-FieldBindingChains and lands-where's convention count use it
# over thousands of names; anything it rejects goes to Get-SqlColumnState.
function Test-IsColumn($Tbl, [string] $Col) {
  $Tbl.Columns.Contains($Col) -or $Tbl.OlderOnlyColumns.Contains($Col.ToUpperInvariant())
}

# A QUOTED identifier `"COL"` opening a line of T's newest declaration, read from
# fresh source; $null when there is none; Stale when the script differs from the
# indexed copy (the scan is then NOT run).
function Find-QuotedColumn($SqlSet, $Tbl, [string] $Col, [hashtable] $SourceOverride) {
  $DbPath = $SqlSet.Db          # shadowed: freshness is checked against the SQL index
  if (-not (Test-SourceFresh $Tbl.File $SourceOverride)) { return [pscustomobject]@{ Stale = $true; Line = 0; Text = '' } }
  $lines = Get-StrippedSqlLines (Resolve-SourceReadPath $Tbl.File $SourceOverride)
  $end = Find-SqlBodyEnd $lines $Tbl.Line ';'
  $last = $(if ($end.Found) { $end.EndLine } else { [Math]::Min($lines.Count, $Tbl.Line + 400) })
  $rx = '^\s*"' + [regex]::Escape($Col) + '"\s'
  for ($i = $Tbl.Line + 1; $i -le $last; $i++) {
    $m = [regex]::Match($lines[$i - 1], $rx, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($m.Success) { return [pscustomobject]@{ Stale = $false; Line = $i; Text = $lines[$i - 1].Trim() } }
  }
  $null
}

function Get-SqlColumnState($SqlSet, [string] $Table, [string] $Col, [hashtable] $SourceOverride,
                            $ServerSqlHit, [string] $SqlSearched) {
  $tbl = $SqlSet.Tables[$Table]
  if (-not $tbl) { throw "Get-SqlColumnState: no table $Table in the SQL index -- the caller checks the table first" }
  $DbPath = $SqlSet.Db          # shadowed for the sql_column line lookups
  $cu = $Col.ToUpperInvariant()
  $nf = [IO.Path]::GetFileName($tbl.File)
  $newest = "$($tbl.ColumnNames.Count) columns extracted from the newest of $($tbl.DeclCount) declaration(s), ${nf}:$($tbl.Line)"
  $o = [ordered]@{ Table = $tbl.Name; Column = $cu; State = ''; IsColumn = $false; File = $tbl.File; Line = $tbl.Line
                   Text = ''; Label = ''; OlderFile = $null; OlderLine = 0; QuotedScan = '' }
  if ($tbl.Columns.Contains($Col)) {
    $cl = Invoke-IndexQuery "SELECT start_line AS line FROM symbols WHERE kind = 'sql_column' AND parent_id = $($tbl.Id) AND UPPER(name) = UPPER('$(ConvertTo-SqlText $Col)')"
    if ($cl.Count) { $o.Line = [int]$cl[0].line }
    $o.State = 'yes'; $o.IsColumn = $true
    $o.Label = "[certain] a column of the newest of $($tbl.DeclCount) declaration(s), $nf"
    return [pscustomobject]$o
  }
  # an older declaration that extracts it (THE KNOWN GAP), with its own column line
  if ($tbl.OlderOnlyColumns.Contains($cu)) {
    $oc = $tbl.OlderOnlyColumns[$cu]
    $o.OlderFile = $oc.File; $o.OlderLine = $oc.Line
    $od = @($tbl.Declarations | Where-Object { [string]::Equals($_.File, $oc.File, [StringComparison]::OrdinalIgnoreCase) -and $_.Line -eq $oc.Line })
    if ($od.Count) {
      $cl = Invoke-IndexQuery "SELECT start_line AS line FROM symbols WHERE kind = 'sql_column' AND parent_id = $($od[0].Id) AND UPPER(name) = UPPER('$(ConvertTo-SqlText $Col)')"
      if ($cl.Count) { $o.OlderLine = [int]$cl[0].line }
    }
  }
  $q = Find-QuotedColumn $SqlSet $tbl $cu $SourceOverride
  $o.QuotedScan = $(if (-not $q) { 'none' } elseif ($q.Stale) { 'stale' } else { 'hit' })
  $olderNote = $(if ($o.OlderFile) { "an older declaration ($([IO.Path]::GetFileName($o.OlderFile)):$($o.OlderLine)) extracts it unquoted" } else { '' })
  if ($o.QuotedScan -eq 'hit') {
    $o.State = 'quoted'; $o.IsColumn = $true; $o.Line = $q.Line; $o.Text = $q.Text
    $o.Label = "[inferred -- source scan] a QUOTED identifier in the newest declaration (${nf}:$($q.Line)) " +
               "that the SQL index did not extract as a column$(if ($olderNote) { "; $olderNote" })"
    return [pscustomobject]$o
  }
  $quotedPart = $(if ($o.QuotedScan -eq 'stale') { "$nf differs from the indexed copy, so it was not scanned for a quoted identifier [stale source]" }
                  else { 'nor a quoted identifier in that declaration' })
  if ($o.OlderFile) {
    $o.State = 'older'; $o.IsColumn = $true; $o.File = $o.OlderFile; $o.Line = $o.OlderLine
    $o.Label = "column extracted ONLY from an older declaration ($([IO.Path]::GetFileName($o.OlderFile)):$($o.OlderLine)); " +
               "not extracted from the newest ($newest); $quotedPart"
    return [pscustomobject]$o
  }
  if ($ServerSqlHit) {
    $o.State = 'server-sql'; $o.IsColumn = $true; $o.File = $ServerSqlHit.File; $o.Line = [int]$ServerSqlHit.Line
    $o.Label = "[inferred] not extracted as a column by the SQL index ($newest); $quotedPart -- but the SQL for $($tbl.Name) " +
               "in $($ServerSqlHit.Routine) names it: the scripts lag the schema"
    return [pscustomobject]$o
  }
  if ($o.QuotedScan -eq 'stale') {
    $o.State = 'stale'
    $o.Label = "[stale source] not extracted as a column by the SQL index ($newest); $nf differs from the indexed copy, so it was not " +
               "scanned for a quoted identifier -- whether $cu is a column of $($tbl.Name) is NOT known"
    return [pscustomobject]$o
  }
  $o.State = 'no'
  $o.Label = "not extracted as a column by the SQL index ($newest); $quotedPart" +
             $(if ($SqlSearched) { "; no SQL for $($tbl.Name) in $SqlSearched names it" } else { '' })
  [pscustomobject]$o
}

# consumers' reader / writer COUNTS (final wave, item 6). A consumers row key is
# a routine id (> 0) or MINUS a file id (< 0) for a verb literal outside every
# routine -- one "(unit level)" row per unit. The header said "reading routines"
# over both; now routines and units are counted apart. Pure over its inputs, so
# a check can drive it: no clone holds a unit-level SQL literal today (measured
# 2026-09-23: 0 on all eight Delphi clones).
# Returns Routines (distinct keys > 0) and Units (distinct keys < 0).
function Measure-ConsumerKeys($CertKeys, $LitKeys) {
  $all = @(@($CertKeys) + @($LitKeys) | Where-Object { $null -ne $_ } | ForEach-Object { [int]$_ } | Sort-Object -Unique)
  [pscustomobject]@{
    Routines = @($all | Where-Object { $_ -gt 0 }).Count
    Units    = @($all | Where-Object { $_ -lt 0 }).Count
  }
}

# ENGINE D12 detector for effects (see Emit-Effects.ps1): true when the stored
# `g` rests on a witness that names the routine ITSELF -- "writes <Name>
# (non-local)", a Result assignment through the function's own name. Pure over
# its inputs ($Effects: decoded rows with a .Kind), so the gate drives it on
# synthetic rows: engine 1.19 fixed D12 and no real row reaches it any more.
function Test-D12OwnNameWrite([string] $Name, [string] $Witness, $Effects) {
  [bool]($Name -and $Witness -and
         [string]::Equals($Witness, "writes $Name (non-local)", [StringComparison]::OrdinalIgnoreCase) -and
         @($Effects | Where-Object { $_.Kind -eq 'g' }).Count)
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
# declaration line to the first line that ENDS in `^` (after comments are
# blanked and trailing blanks trimmed). Procedures have their own scanner
# (Get-SqlProcBodyText) because they need the SET TERM state.
# $DbPath must be the SQL index (freshness is checked against it).
# Returns Stale, Found, StartLine, EndLine (the `^` line, 0 when not found),
# Text (the stripped body, declaration line included, `^` excluded) and Reason
# ('' when found).
#
# A body that reaches the NEXT statement before its `^` is NOT FOUND (Task 0
# review): a trigger missing its terminator must not run on into the following
# trigger's body and inherit its tables and NEW./OLD. columns. Find-SqlBodyEnd
# stops at a line that starts a new DDL statement (CREATE / RECREATE / ALTER) or
# a SET TERM, and says so in Reason.
#
# FINDING, 2026-09-23 (Task 2): the Task 0 rule "the next line that is EXACTLY
# `^`" reported 183/183 bodies, but 3 of them were WRONG. GINSP_BIU5 (MS5.SQL:400),
# STATIONS_BIU5 (MS5.SQL:1118) and DEFCTRPL_BIU0 (MS6.SQL:171) end in `END^` on
# the body's last line, so the bare-`^` scan ran on through the NEXT trigger and
# gave each one its neighbour's NEW./OLD. columns. The CREATE stop exposed them
# (180/183 found); ending the scan at a line that ENDS in `^` -- the procedure
# rule -- finds all 183, each ending at its own terminator.
function Get-SqlBodyText([string] $Path, [int] $Line, [hashtable] $SourceOverride, [int] $MaxLines = 400) {
  if (-not (Test-SourceFresh $Path $SourceOverride)) {
    return [pscustomobject]@{ Stale = $true; Found = $false; StartLine = $Line; EndLine = 0; Text = $null; Reason = 'stale source' }
  }
  $lines = Get-StrippedSqlLines (Resolve-SourceReadPath $Path $SourceOverride)
  $end = Find-SqlBodyEnd $lines $Line '^' -MaxLines $MaxLines
  if (-not $end.Found) {
    return [pscustomobject]@{ Stale = $false; Found = $false; StartLine = $Line; EndLine = 0; Text = $null; Reason = $end.Reason }
  }
  $j = $end.EndLine - 1
  $body = if ($j -gt $Line - 1) { $lines[($Line - 1)..($j - 1)] -join "`n" } else { '' }
  [pscustomobject]@{ Stale = $false; Found = $true; StartLine = $Line; EndLine = $end.EndLine; Text = $body; Reason = '' }
}

# The ONE body-end scanner, over already-stripped lines, so it can be tested on
# synthetic text (a manufactured .SQL copy is always stale, and a stale file is
# never scanned). From 1-based $Line, find the terminator:
#   -BareTerm   a line that is exactly $Term      (triggers: `^` on its own line)
#   otherwise   a line that ENDS in $Term         (procedures: `END^`, `END ^`)
# A line after the first that starts a new statement -- CREATE, RECREATE, ALTER,
# or SET TERM -- ends the search NOT FOUND. PSQL cannot contain DDL (only inside
# EXECUTE STATEMENT strings, which are blanked), so such a line means the
# terminator is missing, and running on would attribute the next object's body
# to this one. Returns Found, EndLine (1-based terminator line, 0 when not found)
# and Reason.
function Find-SqlBodyEnd([string[]] $Lines, [int] $Line, [string] $Term, [switch] $BareTerm, [int] $MaxLines = 400) {
  $last = [Math]::Min($Lines.Count, $Line - 1 + $MaxLines)
  for ($j = $Line - 1; $j -lt $last; $j++) {
    $t = $Lines[$j].Trim()
    if ($j -gt $Line - 1 -and $t -match '^(CREATE|RECREATE|ALTER)\s|^SET\s+TERM\b') {
      return [pscustomobject]@{ Found = $false; EndLine = 0
                                Reason = "reached the next statement at line $($j + 1) before a $Term terminator" }
    }
    $hit = $(if ($BareTerm) { $t -eq $Term } else { $t.EndsWith($Term) })
    if ($hit) { return [pscustomobject]@{ Found = $true; EndLine = $j + 1; Reason = '' } }
  }
  [pscustomobject]@{ Found = $false; EndLine = 0; Reason = "no $Term terminator within $MaxLines lines" }
}

# The statement terminator in force at 1-based $Line: the last `SET TERM x`
# above it, else `;`. `SET TERM ^ ;` and `SET TERM ^;` both switch to `^`, and
# `SET TERM ; ^` / `SET TERM ;^` back to `;` -- the NEW terminator is the first
# character after TERM (every terminator in these scripts is one character).
function Get-SqlTermAt([string[]] $Lines, [int] $Line) {
  $term = ';'
  for ($j = 0; $j -lt [Math]::Min($Line - 1, $Lines.Count); $j++) {
    $m = [regex]::Match($Lines[$j], '^\s*SET\s+TERM\s*(\S)')
    if ($m.Success) { $term = $m.Groups[1].Value }
  }
  $term
}

# A PROCEDURE body read from the .SQL source (plan P20, controller ruling R2:
# Task 2's scanner, time-boxed). The trigger rule does not fit procedures: only
# 1 of 168 ends at a bare `^` line, because MS1 and MS5 write `END^` / `END ^`
# on the last line of the body inside a `SET TERM ^ ;` block. So: find the
# terminator in force at the declaration (Get-SqlTermAt), refuse to scan when it
# is still `;` (a `;`-terminated scan would stop at the first statement inside
# the body), and scan to the first line that ENDS in it (Find-SqlBodyEnd).
# Same contract as Get-SqlBodyText, plus Term.
function Get-SqlProcBodyText([string] $Path, [int] $Line, [hashtable] $SourceOverride, [int] $MaxLines = 400) {
  if (-not (Test-SourceFresh $Path $SourceOverride)) {
    return [pscustomobject]@{ Stale = $true; Found = $false; StartLine = $Line; EndLine = 0; Text = $null; Term = ''; Reason = 'stale source' }
  }
  $lines = Get-StrippedSqlLines (Resolve-SourceReadPath $Path $SourceOverride)
  $term = Get-SqlTermAt $lines $Line
  if ($term -eq ';') {
    return [pscustomobject]@{ Stale = $false; Found = $false; StartLine = $Line; EndLine = 0; Text = $null; Term = $term
                              Reason = 'no SET TERM in force at the declaration' }
  }
  $end = Find-SqlBodyEnd $lines $Line $term -MaxLines $MaxLines
  if (-not $end.Found) {
    return [pscustomobject]@{ Stale = $false; Found = $false; StartLine = $Line; EndLine = 0; Text = $null; Term = $term; Reason = $end.Reason }
  }
  $body = $lines[($Line - 1)..($end.EndLine - 1)] -join "`n"
  $body = $body.Substring(0, $body.LastIndexOf($term))      # the terminator itself is not body text
  [pscustomobject]@{ Stale = $false; Found = $true; StartLine = $Line; EndLine = $end.EndLine; Text = $body; Term = $term; Reason = '' }
}

# Every procedure declaration with its scanned body, cached per SQL index per
# run. 168 declarations are 90 names: MS1.SQL declares 89 of them as STUBS
# (`BEGIN SUSPEND; END^` -- forward declarations so the real bodies can refer to
# each other) and MS5.SQL carries the real bodies. So the NEWEST-file rule that
# picks a table's columns would pick the empty stub here; a procedure instead
# names a table when ANY of its declarations' bodies does, and the row anchors
# on that declaration.
# Per declaration: Id, Name, File, Line, EndLine, Stale, Found, Reason, Tables
# (tables named after an upper-case verb, Get-SqlVerbTables) and Procs (procedures
# after EXECUTE PROCEDURE). The body text is kept for column matching.
function Get-SqlProcedureSet([string] $SqlDb, [hashtable] $SourceOverride) {
  $set = Get-SqlTableSet $SqlDb
  $SqlDb = $set.Db
  if (-not $script:DlProcSets) { $script:DlProcSets = @{} }
  if (-not $SourceOverride -and $script:DlProcSets.ContainsKey($SqlDb)) { return $script:DlProcSets[$SqlDb] }
  $DbPath = $SqlDb   # see Get-SqlTableSet

  $rows = Get-AllIndexRows @"
SELECT s.id AS id, s.name AS name, s.start_line AS line, f.path AS path
  FROM symbols s JOIN files f ON f.id = s.file_id
 WHERE s.kind = 'sql_procedure'
"@ 's.id'
  $out = New-Object System.Collections.ArrayList
  foreach ($r in $rows) {
    $b = Get-SqlProcBodyText ([string]$r.path) ([int]$r.line) $SourceOverride
    $tabs = @(); $procs = @()
    if ($b.Found) {
      $hits = Get-SqlVerbTables $b.Text $set
      $tabs  = @($hits | Where-Object { $_.Kind -eq 'table' }     | ForEach-Object { $_.Name } | Sort-Object -Unique)
      $procs = @($hits | Where-Object { $_.Kind -eq 'procedure' } | ForEach-Object { $_.Name } | Sort-Object -Unique)
    }
    [void]$out.Add([pscustomobject]@{
      Id = [int]$r.id; Name = [string]$r.name; File = [string]$r.path; Line = [int]$r.line
      EndLine = $b.EndLine; Stale = $b.Stale; Found = $b.Found; Reason = $b.Reason
      Tables = $tabs; Procs = $procs; Text = $b.Text
    })
  }
  $all = $out.ToArray()
  $o = [pscustomobject]@{
    Declarations = $all
    Count        = $all.Count
    Names        = @($all | ForEach-Object { $_.Name.ToUpperInvariant() } | Sort-Object -Unique).Count
    BodiesFound  = @($all | Where-Object { $_.Found }).Count
    Stale        = @($all | Where-Object { $_.Stale }).Count
    WithTables   = @($all | Where-Object { $_.Tables.Count -gt 0 }).Count
  }
  if (-not $SourceOverride) { $script:DlProcSets[$SqlDb] = $o }
  $o
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

# ---- small pieces of the datasource chain, shared and separately checked ----------
#
# Each of these was a defect inside Get-DataSourceChain found by the Task 0
# review (routed to Task 3); they are functions now so Test-FeedsFromHelpers.ps1
# can check them on synthetic input that the corpus happens not to contain.

# SQL predicate: $ReceiverSql (a column or a quoted literal) IS $Name, bare or
# as the last segment of a qualified receiver (`Self.dsrX`, `frm.dsrX`),
# case-insensitively. An exact suffix comparison, NOT `LIKE '%.name'`: `_` is a
# LIKE wildcard, so `dsr_A` matched `Self.dsrXA` (Task 0 review, fix b).
function Get-ReceiverMatchSql([string] $ReceiverSql, [string] $Name) {
  $n = ConvertTo-SqlText $Name
  $k = $Name.Length + 1
  "(UPPER($ReceiverSql) = UPPER('$n') OR (LENGTH($ReceiverSql) > $k AND UPPER(SUBSTR($ReceiverSql, -$k)) = UPPER('.$n')))"
}

# The control a `<ctl>[.DataBinding|.DataController|.Properties].<Prop> :=` names.
# From receiver_text when it has one (a leading `Self.` is skipped -- it used to
# yield the control `Self`, fix c); otherwise from the comment-stripped text
# BEFORE the ref, because `edtF2   .DataBinding   .DataSource:=` stores
# receiver_text '.DataBinding' with the control lost (P29).
# Returns Control ('' when none) and From ('receiver' | 'source' | '').
function Get-RePointControl([string] $ReceiverText, [string] $Before) {
  if ($ReceiverText -and -not $ReceiverText.StartsWith('.')) {
    $segs = @($ReceiverText -split '\.' | ForEach-Object { $_.Trim() })
    $ctl = $(if ($segs[0] -eq 'Self' -and $segs.Count -gt 1) { $segs[1] } else { $segs[0] })
    return [pscustomobject]@{ Control = $ctl; From = 'receiver' }
  }
  if ($null -ne $Before) {
    $bef = $Before -replace '\s', ''
    if ($bef -match '(?:^|[^A-Za-z0-9_.])(?:Self\.)?([A-Za-z_][A-Za-z0-9_]*)\.(?:DataBinding|DataController|Properties)\.$') {
      return [pscustomobject]@{ Control = $Matches[1]; From = 'source' }
    }
  }
  [pscustomobject]@{ Control = ''; From = '' }
}

# The identifier whose DECLARED TYPE the chain follows from an RHS such as
# `FViewModel.MemTable`. A leading `Self.` is skipped. An RHS that starts with a
# parenthesis (`(VM as IFoo).MemTable`) or a call / hard cast (`TFoo(X)`,
# `GetTable(1).MT`) has no declared root: Root is '' and Reason is a sentence
# the chart can print after "chain stops here:" (it used to be an empty root and
# a malformed `no-type` reason, fix c).
function Get-RhsRoot([string] $Rhs) {
  $r = ([string]$Rhs).Trim() -replace '^Self\s*\.\s*', ''
  if (-not $r) { return [pscustomobject]@{ Root = ''; Reason = 'RHS is empty -- nothing to follow' } }
  if ($r.StartsWith('(')) {
    return [pscustomobject]@{ Root = ''; Reason = "RHS $Rhs is a cast expression -- its type is not followed" }
  }
  if ($r -match '^([A-Za-z_][A-Za-z0-9_]*)\s*\(') {
    return [pscustomobject]@{ Root = ''; Reason = "RHS $Rhs starts with a call or hard cast ($($Matches[1])(...)) -- its result type is not followed" }
  }
  if ($r -match '^([A-Za-z_][A-Za-z0-9_]*)') { return [pscustomobject]@{ Root = $Matches[1]; Reason = '' } }
  [pscustomobject]@{ Root = ''; Reason = "RHS $Rhs has no identifier root -- nothing to follow" }
}

# SQL scalar subquery: the datasource text that feeds the component $CtlAlias,
# whose DFM row is $SlAlias -- its OWN DataSource property, else its parent's,
# else its grandparent's (a grid column is fed through its view's
# DataController.DataSource). Nearest first. Measured 2026-09-23 on CLIENT: of
# 842 field-binding rows none has a datasource on more than one of the three, so
# nearest-first and consumers' earlier line-order rule agree on this corpus; the
# rule is written down once so consumers and feeds-from cannot drift.
# (A COALESCE of three lookups, because SQLite refuses an outer column inside a
# correlated subquery's ORDER BY -- "no such column: c.id".)
function Get-ControlDataSourceSql([string] $SlAlias = 'sl', [string] $CtlAlias = 'c') {
  $c = $CtlAlias
  $one = { param($who)
    "(SELECT d.text FROM string_literals d WHERE d.kind = 'dfm-prop' AND d.file_id = $SlAlias.file_id " +
    "AND d.owner_name IN ('DataSource','DataBinding.DataSource','DataController.DataSource') " +
    "AND d.symbol_id = $who ORDER BY d.start_line LIMIT 1)" }
  "COALESCE($(& $one "$c.id"), $(& $one "$c.parent_id"), " +
  "$(& $one "(SELECT g.parent_id FROM symbols g WHERE g.id = $c.parent_id)"))"
}

# Code ASSIGNMENTS to <control>[.DataBinding|...].<one of $Props> in $PasPath,
# for the controls in $Names. A READ of the property is not a re-pointing
# (ControlPlan2.pas:1689-1702 read `.DataController.DataSource.DataSet`). A row
# in a stale file is kept with Stale = $true and no RHS: the LINE is still a
# fact of the index, the text is not (R11). Used by the chain (DataSource /
# ListSource) and by feeds-from (DataField / FieldName re-binding).
function Get-RePointSites([string] $PasPath, [string[]] $Names, [string[]] $Props, [hashtable] $SourceOverride) {
  $out = New-Object System.Collections.ArrayList
  if (-not $PasPath -or -not @($Names).Count) { return , $out.ToArray() }
  [void](Get-IndexedFileShas)                       # loads the path -> file id map
  $fid = $script:DlFileIds[$DbPath][$PasPath]
  $sites = Invoke-IndexQuery @"
SELECT r.receiver_text AS rt, r.name_text AS prop, r.start_line AS line, r.start_col AS col, r.end_col AS ecol,
       encl.qualified_name AS routine
  FROM refs r LEFT JOIN symbols encl ON encl.id = r.enclosing_symbol_id
 WHERE r.file_id = $fid AND r.kind = 'member-access' AND r.name_text IN ($(ConvertTo-SqlInList $Props))
 ORDER BY r.start_line, r.start_col
"@ 'Get-RePointSites'
  foreach ($s in $sites) {
    $rt = [string]$s.rt
    $ctx = Get-SourceContext $PasPath ([int]$s.line) ([int]$s.col) ([int]$s.ecol - [int]$s.col) $SourceOverride
    $who = Get-RePointControl $rt $(if ($ctx.Stale) { $null } else { $ctx.Before })
    if (-not $who.Control -or ($Names -notcontains $who.Control)) { continue }
    $rhs = ''
    if (-not $ctx.Stale) {
      if ($ctx.After -notmatch '^\s*:=') { continue }   # a read is not a re-pointing
      $rhs = (($ctx.After -replace '^\s*:=', '') -split ';')[0].Trim()
    }
    [void]$out.Add([pscustomobject]@{
      Control = $who.Control; ControlFrom = $who.From; Receiver = $rt; Prop = [string]$s.prop
      File = $PasPath; Line = [int]$s.line; Routine = [string]$s.routine; Rhs = $rhs; Stale = $ctx.Stale
    })
  }
  , $out.ToArray()
}

# Where a datasource gets its dataset: 'dfm' rows from the DataSet property of
# component $DsId (0 = no component, a FIELD datasource), and 'assign' / 'read'
# / 'stale' rows from `<Local>.DataSet` member accesses in $DsPas, the RHS read
# from fresh source (-Following 5: 10 of 53 assignments wrap). Extracted from
# Get-DataSourceChain UNCHANGED so Get-RePointChain can ask the same question of
# a view-model field; the chain's pins (A-FF0-DS-CHART 54/5/49) guard it.
# Returns (, array) rows Kind ('dfm'|'assign'|'read'|'stale'), File, Line,
# Routine, Rhs, Eid (the enclosing routine's symbol id; 0 on a 'dfm' row).
function Get-DataSetSites([int] $DsId, [string] $DsFile, [string] $DsPas, [string] $Local, [hashtable] $SourceOverride) {
  $sites = New-Object System.Collections.ArrayList
  if ($DsId) {
    $dfmSet = Invoke-IndexQuery @"
SELECT sl.text AS t, sl.start_line AS line FROM string_literals sl
 WHERE sl.kind = 'dfm-prop' AND sl.owner_name = 'DataSet' AND sl.symbol_id = $DsId
"@
    foreach ($x in $dfmSet) {
      [void]$sites.Add([pscustomobject]@{ Kind = 'dfm'; File = $DsFile; Line = [int]$x.line; Routine = ''; Rhs = [string]$x.t; Eid = 0 })
    }
  }
  if ($DsPas) {
    [void](Get-IndexedFileShas)                       # loads the path -> file id map
    $pid2 = $script:DlFileIds[$DbPath][$DsPas]
    $code = Invoke-IndexQuery @"
SELECT r.start_line AS line, r.start_col AS col, r.end_col AS ecol, r.enclosing_symbol_id AS eid,
       encl.qualified_name AS routine
  FROM refs r LEFT JOIN symbols encl ON encl.id = r.enclosing_symbol_id
 WHERE r.file_id = $pid2 AND r.kind = 'member-access' AND r.name_text = 'DataSet'
   AND $(Get-ReceiverMatchSql 'r.receiver_text' $Local)
 ORDER BY r.start_line, r.start_col
"@ 'Get-DataSetSites'
    foreach ($x in $code) {
      $ctx = Get-SourceContext $DsPas ([int]$x.line) ([int]$x.col) ([int]$x.ecol - [int]$x.col) $SourceOverride -Following 5
      if ($ctx.Stale) {
        [void]$sites.Add([pscustomobject]@{ Kind = 'stale'; File = $DsPas; Line = [int]$x.line; Routine = [string]$x.routine; Rhs = ''; Eid = [int]$x.eid })
        continue
      }
      if ($ctx.After -match '^\s*:=') {
        $buf = $ctx.After -replace '^\s*:=', ''
        foreach ($f in $ctx.Following) { if ($buf -match ';') { break }; $buf += ' ' + $f }
        # whitespace is collapsed, not deleted: `(VM as IFoo)` must not read `(VMasIFoo)`
        $rhs = ((($buf -split ';')[0].Trim()) -replace '\s*\.\s*', '.') -replace '\s+', ' '
        [void]$sites.Add([pscustomobject]@{ Kind = 'assign'; File = $DsPas; Line = [int]$x.line; Routine = [string]$x.routine; Rhs = $rhs; Eid = [int]$x.eid })
      } else {
        [void]$sites.Add([pscustomobject]@{ Kind = 'read'; File = $DsPas; Line = [int]$x.line; Routine = [string]$x.routine; Rhs = ''; Eid = [int]$x.eid })
      }
    }
  }
  , $sites.ToArray()
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
#   DataSource      $null | Id, Name, Qname, Type, File, Line, SameFile
#                   (SameFile $false = reached through a module NAME: [by name])
#   Controls[]      Control, ControlType, ControlId, Prop, File, Line, IsLookup
#   RePointedAt[]   Control, ControlFrom ('receiver'|'source'), Receiver, Prop,
#                   File, Line, Routine, Rhs, Stale   (Get-RePointSites)
#   DataSetSites[]  Kind ('dfm'|'assign'|'read'|'stale'), File, Line, Routine, Rhs
#   RhsType         $null | Rhs, Root, RootKind, TypeName, TypeKind, TypeFile, TypeLine
#   CandidateTables[] (first-literal order, EXACT upper-case match), CandidateLines{table -> line},
#   BoundColumns[], ColumnMatch[], MissingColumns[]
#   CaseOnlyLiterals[] "'Text' :line" -- literals equal to a table name only
#                   case-insensitively; named on the hop, never taken (hop 4)
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
  $names = @($controls | Where-Object { $_.Control } | ForEach-Object { $_.Control } | Sort-Object -Unique)
  $repoint = $(if ($pasId) { Get-RePointSites $pasPath $names @('DataSource', 'ListSource') $SourceOverride } else { , @() })

  $o = [ordered]@{
    Form = $Form; FormFile = $dfmPath; PasFile = $pasPath; DsName = $DsName
    Module = ''; Dangling = $false; DataSource = $null
    Controls = $controls; RePointedAt = @($repoint)
    DataSetSites = @(); RhsType = $null
    CandidateTables = @(); CandidateLines = @{}; BoundColumns = @(); ColumnMatch = @(); MissingColumns = @()
    CaseOnlyLiterals = @()
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
  $sameFile = ([int]$d.fid -eq $dfmId)
  $o.DataSource = [pscustomobject]@{ Id = [int]$d.id; Name = [string]$d.name; Qname = [string]$d.q
                                     Type = [string]$d.sig; File = [string]$d.path; Line = [int]$d.line
                                     SameFile = $sameFile }
  # Only a SAME-FILE component is certain (P28). A module prefix naming ANOTHER
  # form's file is a match on the module's NAME -- `dsrFtrs` exists in three
  # forms -- so it is [by name] (plan R5; Task 0 review, fix a). Measured
  # 2026-09-23: no CLIENT binding takes this branch today (all 65 prefixed rows
  # are dangling); Test-FeedsFromHelpers.ps1 exercises it on real components.
  if ($sameFile) {
    Add-Hop 'datasource' 'certain' "$($d.name): $($d.sig)" ([string]$d.path) ([int]$d.line) ''
  } else {
    Add-Hop 'datasource' 'by name' "$($d.name): $($d.sig)" ([string]$d.path) ([int]$d.line) `
      "resolved through the module NAME $($o.Module) to $([IO.Path]::GetFileName([string]$d.path)), not declared in $([IO.Path]::GetFileName($dfmPath))"
  }
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
  # (hop 3 below reads $pid2: the declaring file of the RHS root is the datasource's unit)
  $pid2 = $(if ($dsPas) { $fileIds[$dsPas] } else { 0 })
  $sites = New-Object System.Collections.ArrayList
  foreach ($x in (Get-DataSetSites ([int]$d.id) $dsFile $dsPas $local $SourceOverride)) { [void]$sites.Add($x) }
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
  # The assignment LINE is a fact read from fresh source, so the hop is certain
  # -- when it is the only story. EVERY site was scanned (dsrFolder's first site
  # is a CodeSite.Send read); if the non-nil assignments disagree on the RHS, or
  # a stale file hides some sites, following the first one is a choice: inferred.
  $rhsSet = @($assigns | ForEach-Object { $_.Rhs.ToUpperInvariant() } | Sort-Object -Unique)
  $dsWhy = @()
  if ($rhsSet.Count -gt 1) { $dsWhy += "$($assigns.Count) assignments with $($rhsSet.Count) different right-hand sides; following the first" }
  if ($staleSites.Count) { $dsWhy += "$($staleSites.Count) other site(s) in a stale file not read" }
  Add-Hop 'dataset' $(if ($dsWhy.Count) { 'inferred' } else { 'certain' }) "$local.DataSet := $($a0.Rhs)" $a0.File $a0.Line ($dsWhy -join '; ')

  # ---- hop 3: the declared type of the RHS root ----------------------------------
  $rr = Get-RhsRoot $a0.Rhs
  $root = $rr.Root
  if (-not $root) {
    Add-Hop 'rhs-type' 'unresolved' $a0.Rhs $dsPas $a0.Line $rr.Reason
    return (Complete 'no-type' $rr.Reason)
  }
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
    $why = "$root is not declared as a field, property, parameter or variable in $([IO.Path]::GetFileName($dsPas))"
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
SELECT sl.text AS t, MIN(sl.start_line) AS line FROM string_literals sl
 WHERE sl.file_id = $([int]$ts[0].fid) AND sl.kind IN ('literal','const') AND sl.text IN ($inNames)
 GROUP BY sl.text ORDER BY MIN(sl.start_line), sl.text
"@ 'Get-DataSourceChain (table literals)'
  # In FIRST-LITERAL order, not alphabetical: the order the view model names its
  # tables is how a reader finds them (uMachineList.ViewModel.pas: MACHINES :42,
  # STATIONS :143, PLANT :144, DEPARTTBL :145). CandidateLines anchors each one.
  $o.CandidateTables = @($lit | ForEach-Object { [string]$_.t })
  foreach ($x in $lit) { $o.CandidateLines[[string]$x.t] = [int]$x.line }
  $typeFile = [string]$ts[0].path
  $unit = [IO.Path]::GetFileName([string]$ts[0].path)
  $cand = $o.CandidateTables

  # CASE (final wave, item 8 / R21). The match above is EXACT on purpose, and the
  # sentences below say "upper-case" because that is what was read. R21 asked for
  # UPPER(sl.text); measured on CLIENT 2026-09-23, every mixed-case literal equal
  # to a table name is NOT a table reference -- 'Folders' (uJobList.pas:552, a
  # ribbon tab caption), 'tools' (a folder name), 'memFolders' (a component
  # name), 'DueIN' / 'Duein' (computed-field names) -- and UPPER turned the
  # uJobList dsrFolder chain (73 controls, one-table FOLDERS) into `many`
  # [FOLDERS, DUEIN] while changing no `none` chain. So the case-insensitive
  # matches are NAMED on the hop instead: the chart says a literal exists that
  # it did not take, and why, rather than taking it or staying silent.
  $ci = Invoke-IndexQuery @"
SELECT sl.text AS t, MIN(sl.start_line) AS line FROM string_literals sl
 WHERE sl.file_id = $([int]$ts[0].fid) AND sl.kind IN ('literal','const') AND UPPER(sl.text) IN ($inNames) AND sl.text NOT IN ($inNames)
 GROUP BY sl.text ORDER BY MIN(sl.start_line), sl.text
"@ 'Get-DataSourceChain (case-only table literals)'
  $o.CaseOnlyLiterals = @($ci | ForEach-Object { "'$([string]$_.t)' :$([int]$_.line)" })
  $caseNote = $(if ($ci.Count) { "; $($ci.Count) literal(s) equal a table name only case-insensitively and are not taken as one: $($o.CaseOnlyLiterals -join ', ')" } else { '' })

  if ($cand.Count -eq 0) {
    $why = "$unit holds no upper-case string literal naming a table$(if ($o.RhsType.TypeKind -eq 'interface') { " ($typeName is an interface; its implementation is not followed)" })$caseNote"
    Add-Hop 'table' 'unresolved' $typeName ([string]$ts[0].path) ([int]$ts[0].line) $why
    return (Complete 'none' $why)
  }
  $fits = @($cand | Where-Object { $t = $SqlSet.Tables[$_]; -not @($o.BoundColumns | Where-Object { -not $t.Columns.Contains($_) }).Count })
  if ($cand.Count -eq 1) {
    $o.ResolvedTable = $cand[0]
    $o.MissingColumns = @($o.BoundColumns | Where-Object { -not $SqlSet.Tables[$cand[0]].Columns.Contains($_) })
    Add-Hop 'table' 'inferred' $cand[0] $typeFile $o.CandidateLines[$cand[0]] "the only upper-case table-name literal in $unit$caseNote"
    return (Complete 'one-table' '')
  }
  $o.ColumnMatch = $fits
  if ($o.BoundColumns.Count -and $fits.Count -eq 1) {
    $o.ResolvedTable = $fits[0]
    Add-Hop 'table' 'inferred' $fits[0] $typeFile $o.CandidateLines[$fits[0]] "$($cand.Count) tables named in upper case in $unit; only $($fits[0]) holds all $($o.BoundColumns.Count) bound column(s)$caseNote"
    return (Complete 'by-columns' '')
  }
  $why = if (-not $o.BoundColumns.Count) { "$unit names $($cand.Count) tables in upper case and no column is bound through $local to tell them apart$caseNote" }
         else { "$unit names $($cand.Count) tables in upper case; $($fits.Count) of them hold all $($o.BoundColumns.Count) bound column(s)$caseNote" }
  Add-Hop 'table' 'unresolved' "$($cand.Count) candidates" ([string]$ts[0].path) ([int]$ts[0].line) $why
  Complete 'many' $why
}

# ---- the hop feeds-from misses (spec 2026-09-27 section 3, AC-15) -------------------
# WHEN the designer datasource dangles and the control is re-pointed in code,
# follow the assignment's RIGHT-HAND SIDE: `X.Member` -> the member ref on that
# line, right of the re-pointed `.DataSource` ref (BOUND by the resolver:
# certain; else by name on the root's declared type) -> a property's `read`
# accessor, quoted from the fresh declaration line -> the accessor's ONE
# implementation, found by name in a class whose heritage names the interface
# ([by name]) -> the field the accessor body reads (an UNBOUND in-class read --
# INBOX-in-class-field-reads-unbound.md, so [by name]) -> `<field>.DataSet :=`
# through Get-DataSetSites (an assignment line read from fresh source: certain)
# -> the dataset field. A hop that cannot be made STOPS with its reason; a
# stale file on the way sets StaleFile so the caller can REFUSE (AC-14).
# Used by the round-trip trace ONLY (owner decision 3, 2026-09-27): feeds-from
# and lands-where still stop at the dangling datasource.
# $RePoint is ONE row of Get-RePointSites (the caller picks the control's row).
# Returns Hops[] {Hop, Grade, Label, File, Line, Routine, Reason, Ask}, DataSet
# ($null | Name, Id, ClassId, File, Fid, Line, Type), StopReason ('' when the
# dataset was reached), StaleFile ('' | the indexed path that differs).
function Get-RePointChain($RePoint, [hashtable] $SourceOverride) {
  $hops = New-Object System.Collections.ArrayList
  function Hop($h, $g, $l, $f, $n, $r, $why, $ask) {
    [void]$hops.Add([pscustomobject]@{ Hop = $h; Grade = $g; Label = $l; File = $f; Line = $n; Routine = $r; Reason = $why; Ask = $ask })
  }
  function Done([string] $stop, $ds, [string] $stale) { [pscustomobject]@{ Hops = $hops.ToArray(); DataSet = $ds; StopReason = $stop; StaleFile = $stale } }
  if ($RePoint.Stale) { return (Done "$([IO.Path]::GetFileName($RePoint.File)) differs from the indexed copy -- the re-point at :$($RePoint.Line) is not read" $null $RePoint.File) }
  $rn = (($RePoint.Routine -split '\.') | Select-Object -Last 1)
  Hop 're-point' 'certain' "$($RePoint.Control).$($RePoint.Prop) := $($RePoint.Rhs)" $RePoint.File $RePoint.Line $rn '' ''
  $rr = Get-RhsRoot $RePoint.Rhs
  if (-not $rr.Root) { return (Done $rr.Reason $null '') }
  $segs = @((($RePoint.Rhs.Trim() -replace '^Self\s*\.\s*', '') -replace '\s', '') -split '\.')
  if ($segs.Count -lt 2) { return (Done "RHS $($RePoint.Rhs) names no member of $($rr.Root) -- a bare datasource is the designer case Get-DataSourceChain already follows" $null '') }
  $member = $segs[1] -replace '\(.*$', ''
  [void](Get-IndexedFileShas)
  $fid = $script:DlFileIds[$DbPath][$RePoint.File]
  $mq = ConvertTo-SqlText $member
  # the member ref on the re-point line, RIGHT of the re-pointed property's own ref
  # (the Task 1 filter, T1-C2): the chain starts from this ONE assignment, never from
  # another site of the same member. BOUND when the resolver bound it.
  $mref = Invoke-IndexQuery @"
SELECT t.id AS tid, t.kind AS tkind, t.qualified_name AS tq, t.start_line AS tline, t.signature AS tsig, tf.path AS tpath, t.file_id AS tfid, t.parent_id AS tpid
  FROM refs r JOIN symbols t ON t.id = r.symbol_id JOIN files tf ON tf.id = t.file_id
 WHERE r.file_id = $fid AND r.start_line = $($RePoint.Line) AND r.kind = 'member-access' AND r.name_text = '$mq'
   AND EXISTS (SELECT 1 FROM refs d WHERE d.file_id = r.file_id AND d.start_line = r.start_line AND d.kind = 'member-access'
               AND d.name_text = '$(ConvertTo-SqlText $RePoint.Prop)' AND d.start_col < r.start_col)
 ORDER BY r.start_col
"@
  $grade = 'certain'
  if ($mref.Count -eq 0) {
    # unbound: the root's declared type, then its member by name
    $decl = Invoke-IndexQuery "SELECT s.signature AS sig FROM symbols s WHERE s.file_id = $fid AND UPPER(s.name) = UPPER('$(ConvertTo-SqlText $rr.Root)') AND s.kind IN ('field','property','var','param','local_var') ORDER BY s.start_line LIMIT 1"
    if ($decl.Count -eq 0) { return (Done "$($rr.Root) is not declared in $([IO.Path]::GetFileName($RePoint.File))" $null '') }
    $tn = ConvertTo-SqlText ((([string]$decl[0].sig) -replace '<.*$', '').Trim())
    $mref = Invoke-IndexQuery @"
SELECT t.id AS tid, t.kind AS tkind, t.qualified_name AS tq, t.start_line AS tline, t.signature AS tsig, tf.path AS tpath, t.file_id AS tfid, t.parent_id AS tpid
  FROM symbols t JOIN files tf ON tf.id = t.file_id
 WHERE UPPER(t.name) = UPPER('$mq') AND t.kind IN ('property','field')
   AND t.parent_id IN (SELECT c.id FROM symbols c WHERE c.kind IN ('class','interface') AND UPPER(c.name) = UPPER('$tn'))
"@
    if ($mref.Count -ne 1) { return (Done "$member is not a property or field of $(([string]$decl[0].sig).Trim()) in this index ($($mref.Count) matches)" $null '') }
    $grade = 'by name'
  }
  $m = $mref[0]
  Hop 'member' $grade "$member : $(([string]$m.tsig).Trim())" ([string]$m.tpath) ([int]$m.tline) (($([string]$m.tq) -split '\.')[-2]) $(if ($grade -eq 'by name') { "member found by name on the declared type of $($rr.Root)" } else { '' }) ''
  $fieldQ = 'SELECT s.id AS id, s.name AS name, s.signature AS sig, s.start_line AS line, f.path AS path, s.file_id AS fid, s.parent_id AS pid FROM symbols s JOIN files f ON f.id = s.file_id'
  $fieldRow = $null
  $fieldWhy = ''; $fieldAsk = ''
  if ([string]$m.tkind -eq 'property') {
    # the read accessor, quoted from the FRESH declaration line
    if (-not (Test-SourceFresh ([string]$m.tpath) $SourceOverride)) { return (Done "$([IO.Path]::GetFileName([string]$m.tpath)) differs from the indexed copy -- the property's read accessor is not read" $null ([string]$m.tpath)) }
    $lines = Get-StrippedSourceLines (Resolve-SourceReadPath ([string]$m.tpath) $SourceOverride)
    $pl = $lines[[int]$m.tline - 1]
    if ($pl -notmatch '\bread\s+([A-Za-z_][A-Za-z0-9_]*)') { return (Done "property $member at $([IO.Path]::GetFileName([string]$m.tpath)):$($m.tline) has no read accessor on its declaration line" $null '') }
    $acc = $Matches[1]
    $ownerName = (([string]$m.tq) -split '\.')[-2]
    # a field accessor (`read FX`) is the field itself, found by name in the property's class
    $fieldRow = Invoke-IndexQuery "$fieldQ WHERE s.parent_id = $([int]$m.tpid) AND s.name = '$(ConvertTo-SqlText $acc)' AND s.kind = 'field'"
    if ($fieldRow.Count) { $fieldWhy = "the read accessor of $member, by name in its class" }
    else {
      # the implementing class: the property's own class, or one whose heritage LISTS the
      # interface (an exact entry of the comma list, plain or unit-qualified -- LIKE '%X%'
      # would also take `IX2` and read `_` as a wildcard)
      $on = ConvertTo-SqlText $ownerName
      $impl = Invoke-IndexQuery @"
SELECT s.id AS id, s.qualified_name AS q, s.impl_start_line AS istart, s.impl_end_line AS iend, f.path AS path, s.file_id AS fid, s.parent_id AS pid
  FROM symbols s JOIN files f ON f.id = s.file_id
 WHERE s.name = '$(ConvertTo-SqlText $acc)' AND s.kind = 'method' AND s.impl_start_line > 0
   AND s.parent_id IN (SELECT c.id FROM symbols c WHERE c.kind = 'class' AND (c.id = $([int]$m.tpid)
        OR INSTR(',' || REPLACE(COALESCE(c.heritage, ''), ' ', '') || ',', ',$on,') > 0
        OR INSTR(',' || REPLACE(COALESCE(c.heritage, ''), ' ', '') || ',', '.$on,') > 0))
"@
      if ($impl.Count -ne 1) { return (Done "$acc has $($impl.Count) implementations in classes implementing $ownerName -- cannot tell which" $null '') }
      $i = $impl[0]
      Hop 'accessor' 'by name' "$acc" ([string]$i.path) ([int]$i.istart) (($([string]$i.q) -split '\.')[-2]) "the read accessor of $member, implemented once in a class whose heritage names $ownerName" 'in-class-field-reads'
      # the field the accessor body reads: an in-class read, unbound in this index
      $reads = Invoke-IndexQuery @"
SELECT DISTINCT r.name_text AS n FROM refs r
 WHERE r.file_id = $([int]$i.fid) AND r.start_line BETWEEN $([int]$i.istart) AND $([int]$i.iend) AND r.kind = 'read' AND r.name_text <> 'Result'
   AND r.name_text IN (SELECT s.name FROM symbols s WHERE s.parent_id = $([int]$i.pid) AND s.kind = 'field')
"@
      if ($reads.Count -ne 1) { return (Done "$acc reads $($reads.Count) fields of its class -- cannot tell which is the datasource" $null '') }
      $fieldRow = Invoke-IndexQuery "$fieldQ WHERE s.parent_id = $([int]$i.pid) AND s.name = '$(ConvertTo-SqlText ([string]$reads[0].n))' AND s.kind = 'field'"
      $fieldWhy = 'an in-class read, unbound in this index'; $fieldAsk = 'in-class-field-reads'
    }
    if ($fieldRow.Count -ne 1) { return (Done "the datasource field behind $member was not found" $null '') }
    $fr = $fieldRow[0]
    Hop 'field' 'by name' "$([string]$fr.name) : $(([string]$fr.sig).Trim())" ([string]$fr.path) ([int]$fr.line) '' $fieldWhy $fieldAsk
  } else {
    # the member IS the datasource field: the member hop above already stands on it
    $fr = [pscustomobject]@{ id = [int]$m.tid; name = $member; sig = [string]$m.tsig; line = [int]$m.tline
                             path = [string]$m.tpath; fid = [int]$m.tfid; pid = [int]$m.tpid }
  }
  # `<field>.DataSet :=` in the field's unit
  $sites = Get-DataSetSites 0 '' ([string]$fr.path) ([string]$fr.name) $SourceOverride
  $stale = @($sites | Where-Object { $_.Kind -eq 'stale' })
  $assigns = @($sites | Where-Object { $_.Kind -eq 'assign' -and $_.Rhs -ne 'nil' })
  if ($stale.Count -and -not $assigns.Count) { return (Done "$([IO.Path]::GetFileName([string]$fr.path)) differs from the indexed copy -- its $($stale.Count) DataSet site(s) are not read" $null ([string]$fr.path)) }
  if (-not $assigns.Count) { return (Done "$([string]$fr.name).DataSet is never assigned in $([IO.Path]::GetFileName([string]$fr.path)) ($($sites.Count) site(s) scanned)" $null '') }
  $a0 = $assigns[0]
  $dsName = (($a0.Rhs -replace '^Self\.', '') -split '\.')[-1]
  $dsRow = Invoke-IndexQuery "$fieldQ WHERE s.parent_id = $([int]$fr.pid) AND s.name = '$(ConvertTo-SqlText $dsName)' AND s.kind = 'field'"
  if ($dsRow.Count -ne 1) { return (Done "the dataset $($a0.Rhs) assigned at :$($a0.Line) is not a field of the same class ($($dsRow.Count) matches)" $null '') }
  # as in Get-DataSourceChain: certain when every non-nil assignment names the same RHS
  $rhsSet = @($assigns | ForEach-Object { $_.Rhs.ToUpperInvariant() } | Sort-Object -Unique)
  $why = $(if ($rhsSet.Count -gt 1) { "$($assigns.Count) assignments with $($rhsSet.Count) different right-hand sides, following the first" } else { '' })
  Hop 'dataset' $(if ($why) { 'inferred' } else { 'certain' }) "$([string]$fr.name).DataSet := $($a0.Rhs)" $a0.File $a0.Line (($a0.Routine -split '\.')[-1]) $why ''
  $d = $dsRow[0]
  Done '' ([pscustomobject]@{ Name = [string]$d.name; Id = [int]$d.id; ClassId = [int]$d.pid; File = [string]$d.path; Fid = [int]$d.fid; Line = [int]$d.line; Type = ([string]$d.sig).Trim() }) ''
}

# The cache key of one chain: the DFM path and the datasource TEXT, case-folded.
function Get-ChainKey([string] $Dfm, [string] $Ds) { "$Dfm|$Ds".ToUpperInvariant() }

# EVERY datasource chain in the index, and every DFM FIELD BINDING of a
# data-aware control classified by where its chain ends -- the population behind
# feeds-from's disclosure rows (and lands-where's DFM-field selection).
#
# Per DATASOURCE: every `TDataSource` component (54 on CLIENT).
# Per CONTROL (plan R9: the 41% is per datasource and must NOT be quoted): every
# `DataBinding.FieldName` / `DataBinding.DataField` / `DataField` row -- 808 on
# CLIENT. Plain `FieldName` is left out ON PURPOSE: measured 2026-09-23, all 34
# such rows are persistent TField definitions on a dataset (`TBLNAME:
# TStringField`), not controls. The datasource is the control's own, else its
# parent's, else its grandparent's (Get-ControlDataSourceSql). Outcome per row:
#   column       chain resolves to one table, and the table has the column
#                (Get-SqlColumnState: extracted, older-only, or quoted)
#   not-column   chain resolves to one table, and the column is not extracted
#                from it nor quoted in its newest declaration
#   ambiguous    several candidate tables survive (grade many)
#   dangling     the DFM datasource names a module this index does not hold
#   stops        the chain stops before a table (none / no-type / no-assignment /
#                dfm-dataset / no-datasource)
#   stale        a source file on the chain differs from the indexed copy -- or
#                the chain resolved (Table set) but the table's script is stale,
#                so whether the column is quoted there is not known
#   no-ds        no DataSource on the control or its two enclosing components
#
# COST AND CACHE: about 70 chains at ~7 engine calls each, ~60 s on CLIENT. The
# result is cached in $global:DlFeedChains for the life of the PowerShell
# process, keyed on both databases' size + mtime and this file's mtime, so the
# gate pays once. A -SourceOverride run is never cached (its answer is about a
# manufactured file), nor is a DOCTORED set's (-TestHideColumn). The cache does not see a source file edited mid-process
# -- start a new process after editing the corpus.
function Get-FieldBindingChains($SqlSet, [hashtable] $SourceOverride) {
  $key = $null
  # never cached for a -SourceOverride run (a manufactured file) or a DOCTORED set
  # (Hide-ExtractedColumns: same .Db, different columns) -- either would poison the
  # real key for every later chart in this process, and read it would hide the test
  if (-not $SourceOverride -and -not $SqlSet.Doctored) {
    $di = Get-Item -LiteralPath $DbPath; $si = Get-Item -LiteralPath $SqlSet.Db
    $ci = Get-Item -LiteralPath (Join-Path $PSScriptRoot 'Emit-Common.ps1')
    $key = "$($di.FullName)|$($di.Length)|$($di.LastWriteTimeUtc.Ticks)|$($si.FullName)|$($si.Length)|$($si.LastWriteTimeUtc.Ticks)|$($ci.LastWriteTimeUtc.Ticks)"
    if (-not $global:DlFeedChains) { $global:DlFeedChains = @{} }
    if ($global:DlFeedChains.ContainsKey($key)) { return $global:DlFeedChains[$key] }
  }

  $chains = @{}
  $dsRows = Get-AllIndexRows @"
SELECT c.id AS id, c.name AS name, f.path AS path
  FROM symbols c JOIN files f ON f.id = c.file_id
 WHERE c.kind = 'component' AND c.signature = 'TDataSource'
"@ 'c.id'
  $perDs = New-Object System.Collections.ArrayList
  foreach ($d in $dsRows) {
    $k = Get-ChainKey ([string]$d.path) ([string]$d.name)
    if (-not $chains.ContainsKey($k)) { $chains[$k] = Get-DataSourceChain ([string]$d.path) ([string]$d.name) $SqlSet $SourceOverride }
    [void]$perDs.Add($chains[$k])
  }

  $binds = Get-AllIndexRows @"
SELECT sl.id AS id, sl.start_line AS line, sl.owner_name AS prop, sl.text AS col, f.path AS dfm,
       c.id AS cid, c.name AS ctl, $(Get-ControlDataSourceSql 'sl' 'c') AS ds
  FROM string_literals sl JOIN files f ON f.id = sl.file_id LEFT JOIN symbols c ON c.id = sl.symbol_id
 WHERE sl.kind = 'dfm-prop' AND sl.owner_name IN ('DataBinding.FieldName','DataBinding.DataField','DataField')
"@ 'sl.id'
  $rows = New-Object System.Collections.ArrayList
  foreach ($b in $binds) {
    $ds = [string]$b.ds
    $outcome = 'no-ds'; $table = $null
    if ($ds) {
      $k = Get-ChainKey ([string]$b.dfm) $ds
      if (-not $chains.ContainsKey($k)) { $chains[$k] = Get-DataSourceChain ([string]$b.dfm) $ds $SqlSet $SourceOverride }
      $ch = $chains[$k]
      $table = $ch.ResolvedTable
      $outcome = if ($ch.Grade -eq 'stale source') { 'stale' }
                 elseif ($ch.Dangling) { 'dangling' }
                 elseif ($table) {
                   # the SHARED column test: cheap first, the source scan only for a miss
                   if (Test-IsColumn $SqlSet.Tables[$table] ([string]$b.col)) { 'column' }
                   else {
                     switch ((Get-SqlColumnState $SqlSet $table ([string]$b.col) $SourceOverride).State) {
                       'quoted' { 'column' }
                       'stale'  { 'stale' }
                       default  { 'not-column' }
                     }
                   }
                 }
                 elseif ($ch.Grade -eq 'many') { 'ambiguous' }
                 else { 'stops' }
    }
    [void]$rows.Add([pscustomobject]@{
      Id = [int]$b.id; Dfm = [string]$b.dfm; Line = [int]$b.line; Prop = [string]$b.prop; Column = [string]$b.col
      ControlId = $(if ($b.cid) { [int]$b.cid } else { 0 }); Control = [string]$b.ctl; Ds = $ds
      Outcome = $outcome; Table = $table
    })
  }

  $o = [pscustomobject]@{ Chains = $chains; DataSources = $perDs.ToArray(); Bindings = $rows.ToArray() }
  if ($key) { $global:DlFeedChains[$key] = $o }
  $o
}

# ---- path B detector: the engine's own ORM links (plan section 7, "Path B") -------
#
# `orm_links` is the engine's version of the hops lands-where and feeds-from
# DERIVE (Delphi symbol -> SQL table/column, with a confidence). It is filled
# only by `fb-snapshot`, which is not run this cycle (engine ruling 1), so it is
# 0 rows on every clone. ONE query, here, so every verb reads the same answer:
# the row count and the newest computed_at. The gate asserts the count it
# EXPECTS today (A-OL-ROWS = 0 on CLIENT and SERVER), so a snapshot landing in a
# clone is a FAILING assertion -- the signal to build the switch -- not a silent
# change of route. Nothing reads the rows yet (the owner rules on the snapshot
# first). Returns Db, Rows, ComputedAt ('' when there are none).
function Get-OrmLinksState([string] $Db) {
  $DbPath = Get-CloneDb $Db       # shadowed: the caller's $DbPath is untouched
  $r = Invoke-IndexQuery 'SELECT COUNT(*) AS n, MAX(computed_at) AS at FROM orm_links'
  [pscustomobject]@{ Db = $DbPath; Rows = [int]$r[0].n; ComputedAt = [string]$r[0].at }
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

# The upward walk of ONE raised type over the CALL EDGES of a caller graph
# (controller rulings R12/R13, fix rounds 2-3). Pure over its inputs, so a check
# can drive it with a synthetic graph.
#
# WHY EDGES, NOT NODES. Round 2 walked nodes with a visited set, and a node that
# CAUGHT the type on one call was never looked at again -- measured: uAutoTest's
# AutoTestSetupDefaults catches ReadBuffer's EReadError at :433 (inside the try
# at :411) but ALSO calls TSetupDefaultsViewModel.Save at :513/:561, a deeper
# callee that lets EReadError through, inside a try..FINALLY only. On that edge
# the exception leaves AutoTestSetupDefaults, and round 2 dropped the path.
#
# So: every incoming edge (caller X, callee C, its call sites) is evaluated on
# its own. X stops T on that edge only when $Evaluate says so (every site inside
# a matching, non-re-raising handler's try). X PASSES T upward when ANY of its
# incoming edges is not stopped, and a passing node's callers are expanded ONCE
# (the visited set holds nodes already PASSING T -- which is also what makes a
# cycle terminate). A node may therefore both catch on one edge and pass on
# another; the result carries both.
#
#   $CallersOf   callee id -> @( { Caller; Sites[] } )  (only walked edges)
#   $Fetched     node id -> $true when its callers were queried
#   $CappedOf    callee id -> @(caller ids NOT walked because of -MaxCallers)
#   $Evaluate    { param($Caller, $Callee, $Sites, $Type) } -> { Stopped; Events; NotGuarding; No; Stale }
#   $HasCallers  { param([int[]] $Ids) } -> hashtable of the ids that have a caller
#                (asked only for nodes at the depth bound whose callers were not queried)
#
# Returns Edges[] (every evaluated edge with its result), Passing[] (callers that
# pass T), Evaluated (distinct callers looked at), Escapes[] (passing nodes at
# the bound whose callers exist but were not walked), Ends[] (passing callers
# with no resolved caller at all), Capped[] (distinct capped callers of passing
# nodes -- NOT walked, never reported as "no caller"), FocusNoCaller, Levels.
function Invoke-ExceptionWalk([int] $FocusId, $CallersOf, $Fetched, $CappedOf, [int] $Depth,
                              [string] $Type, [scriptblock] $Evaluate, [scriptblock] $HasCallers) {
  $wPassing = @{ $FocusId = $true }
  $wEvaluated = @{}
  $wEdges = New-Object System.Collections.ArrayList
  $wEnds = New-Object System.Collections.ArrayList
  $wEsc = New-Object System.Collections.ArrayList
  $wCapped = @{}
  $wFocusNoCaller = $false
  $wFront = @($FocusId)
  $wLvl = 0
  while ($wFront.Count -and $wLvl -lt $Depth) {
    $wLvl++
    $wNext = New-Object System.Collections.ArrayList
    foreach ($wn in $wFront) {
      $wCs = $(if ($CallersOf.ContainsKey($wn)) { @($CallersOf[$wn]) } else { @() })
      $wCap = $(if ($CappedOf.ContainsKey($wn)) { @($CappedOf[$wn]) } else { @() })
      foreach ($wx in $wCap) { $wCapped[$wx] = $true }
      if (-not $wCs.Count) {
        if ($wCap.Count) { continue }                          # callers exist; the cap hid them
        if ($wn -eq $FocusId) { $wFocusNoCaller = $true }
        elseif ($Fetched.ContainsKey($wn)) { [void]$wEnds.Add($wn) } else { [void]$wEsc.Add($wn) }
        continue
      }
      foreach ($we in $wCs) {
        $wr = & $Evaluate $we.Caller $wn @($we.Sites) $Type
        $wEvaluated[$we.Caller] = $true
        [void]$wEdges.Add([pscustomobject]@{ Caller = $we.Caller; Callee = $wn; Sites = @($we.Sites); Result = $wr })
        if (-not $wr.Stopped -and -not $wPassing.ContainsKey($we.Caller)) {
          $wPassing[$we.Caller] = $true
          [void]$wNext.Add($we.Caller)
        }
      }
    }
    $wFront = @($wNext.ToArray())
  }
  # the depth bound: nodes still carrying T whose callers were not expanded
  if ($wFront.Count) {
    $wUnq = @($wFront | Where-Object { -not $Fetched.ContainsKey($_) })
    $wHas = $(if ($wUnq.Count) { & $HasCallers $wUnq } else { @{} })
    foreach ($wn in $wFront) {
      $wKnown = $(if ($CallersOf.ContainsKey($wn)) { @($CallersOf[$wn]).Count } else { 0 })
      $wCap = $(if ($CappedOf.ContainsKey($wn)) { @($CappedOf[$wn]) } else { @() })
      foreach ($wx in $wCap) { $wCapped[$wx] = $true }
      if ($Fetched.ContainsKey($wn)) {
        if ($wKnown) { [void]$wEsc.Add($wn) }
        elseif (-not $wCap.Count) { [void]$wEnds.Add($wn) }
      } elseif ($wHas.ContainsKey($wn)) { [void]$wEsc.Add($wn) }
      else { [void]$wEnds.Add($wn) }
    }
  }
  [pscustomobject]@{
    Type = $Type; Edges = $wEdges.ToArray()
    Passing = @($wPassing.Keys | Where-Object { $_ -ne $FocusId } | Sort-Object)
    Evaluated = $wEvaluated.Count
    Escapes = @($wEsc | Sort-Object -Unique); Ends = @($wEnds | Sort-Object -Unique)
    Capped = @($wCapped.Keys | Sort-Object); FocusNoCaller = $wFocusNoCaller; Levels = $wLvl
  }
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

# The ONE place dot.exe runs (Invoke-DotLayout, Emit-Butterfly, Emit-Deps).
#
# MAX_PATH (Task 1, 2026-09-23): dot.exe is not long-path aware. .NET is (the
# machine sets LongPathsEnabled), so the .dot file WRITES fine under a deep
# OutRoot, and then dot cannot open its outputs and writes no SVG. The old check
# said only "dot produced no SVG", which names neither the cause nor the path.
# So the lengths are checked BEFORE dot runs, and a missing SVG afterwards
# throws with dot's own messages attached.
#
# Stale outputs are REMOVED first: Emit-Butterfly and Emit-Deps used to test
# for the SVG without clearing it, so a failed re-run over an earlier run's
# folder found the OLD picture and reported success.
$script:DotMaxPath = 259   # MAX_PATH less the NUL; measured 2026-09-23 on dot 16.1: 259 writes, 260 "Could not open"
function Invoke-DotRun([string] $DotFile, [string] $Svg, [string] $Plain, [string] $Png, [string] $Pdf) {
  foreach ($p in @($DotFile, $Svg, $Plain, $Png, $Pdf)) {
    $full = [IO.Path]::GetFullPath($p)
    if ($full.Length -gt $script:DotMaxPath) {
      throw ("output path is $($full.Length) characters, over the $($script:DotMaxPath) that dot.exe can open " +
             "(it is not long-path aware, so it would write NO SVG): $full -- use a shorter -OutDir/-OutRoot.")
    }
  }
  foreach ($p in @($Svg, $Plain, $Png, $Pdf)) { if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force } }
  $msgs = @(& $Dot -Tsvg -o $Svg -Tplain -o $Plain -Tpng -Gdpi=110 -o $Png -Tpdf -o $Pdf $DotFile 2>&1 |
            Where-Object { $_ -notmatch 'Pango-WARNING' -and ([string]$_).Trim() -ne '' } |
            ForEach-Object { [string]$_ })
  $dotExit = $LASTEXITCODE
  foreach ($m in $msgs) { Write-Host "  dot: $m" }
  $why = if ($msgs.Count) { ' dot said: ' + ($msgs -join ' | ') } else { ' dot printed nothing.' }
  if (-not (Test-Path -LiteralPath $Svg)) { throw "dot produced no SVG at $Svg (exit $dotExit).$why" }
  # An SVG can exist and still be half a run (the PNG or PDF failed, or dot
  # wrote a partial SVG before erroring), so a non-zero exit fails on its own.
  if ($dotExit -ne 0) { throw "dot exited $dotExit for $DotFile.$why" }
}
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

  Invoke-DotRun $dotO $svgO $plnO $pngO $pdfO
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
