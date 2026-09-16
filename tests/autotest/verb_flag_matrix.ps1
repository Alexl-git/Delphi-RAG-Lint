<#
  verb_flag_matrix.ps1 -- the per-verb flag MATRIX, derived from SOURCE.

  WHAT THIS ANSWERS. CLAUDE.md's DOCS-IN-SYNC table promises that `--help`
  lists "every flag a verb accepts ... on that verb's line". Check 9 of
  run_docs_sync_guard.ps1 enforces flags as SETS only, because ParseArgs is
  verb-agnostic: it fills one TArgs record for every verb, so the parser does
  not know which verb accepts which flag -- the Do<Verb> routine that READS
  the TArgs field does. This script builds the missing map:

      flag  --ParseArgs-->  TArgs field  --Do<Verb> body-->  verb

  and compares each verb's accepted set against the flags named on that
  verb's own lines of the banner.

  WHY SOURCE AND NOT THE INDEX. docs\PLAN-flag-docs-and-guard.md section 10
  recorded this as blocked on INBOX-property-refs-never-resolve.md: the
  index never binds a FIELD reference to a symbol id (only kind='call' refs
  enter the resolve pass), so "who reads TArgs.Force32" answered from refs
  would be a ghost measurement. None of that is needed here, because three
  facts make the whole reader graph a single-file question:
    * TArgs is declared in the IMPLEMENTATION section of DRagLint.CLI.pas
      (`query --name TArgs --exact` -> `[impl-only]`), so no other unit can
      take one;
    * every reader receives it as a PARAMETER (`const AArgs: TArgs`) or copies
      it into a LOCAL of type TArgs, so the receiver names are declared in the
      routine's own header/var block;
    * there is no `with AArgs do` anywhere (asserted), so every field read is
      spelled `<name>.<Field>`.
  A text scan of one unit can therefore be exact PROVIDED it cannot read
  comments, string literals or inactive {$IFDEF} branches -- the repo's own
  warning. Strip-Pascal below blanks all three before any pattern runs, and
  the CONTROLS section plants one of each and requires it to be invisible.

  WHAT IT DERIVES, and the bound on each step.
    1. ParseArgs: split the arg loop into its `else if` chain pieces (the
       chain is at one indentation level; nested ifs are deeper). The flags
       in a piece's CONDITION bind to the Result.<Field> assignments in its
       BODY. `--unit` and `--root` route by Result.Command inside the body,
       so they bind to every field they can route to; the reader side then
       decides. ASSERTED: every `A = '--x'` literal in ParseArgs lands in a
       condition (or repeats its own piece's flag), and > 100 pieces parsed.
    2. Readers: every column-0 routine whose header names a TArgs parameter
       or whose var block declares a TArgs local. Reads are `<name>.<Field>`
       not followed by `:=`. Whole-record uses (`Foo(AArgs)`) become EDGES to
       the callee; the verb's accepted set is the closure over those edges.
       A RECORD COPY (`IndexArgs := AArgs; ... DoIndex(IndexArgs)`) is NOT
       followed: the copy is the callee's own record and its flags are the
       callee's verb's flags. The three sites today are all document-*
       verbs re-running `index`; they are counted and named in the output.
    3. Roots: the dispatch chain in Run. Each `Args.Command = '<verb>'` piece
       contributes its own direct `Args.<Field>` reads (index's mode check,
       lsp's proxy block, serve's size guard) plus the closure of the Do
       routines it calls. Pre-dispatch code in Run (the --project db default,
       ShowHelp/ShowVersion) is deliberately NOT attributed to any verb.
    4. Banner: a line `  drag-lint <verb> ...` opens that verb's block; the
       indented lines that follow belong to it until the next verb line or a
       column-0 section header. COMMON QUESTIONS rows name their verb inline
       and are credited the same way. `--db` is credited to every verb
       because the Databases section says so in as many words (asserted).
       This is GENEROUS on purpose: continuation prose that names another
       verb's flag over-credits, which can only hide a gap, never invent one.

  OUTPUT. The matrix (verb -> accepted / documented / missing), the total
  number of missing (verb, flag) cells, and the flags ranked by how many
  verbs miss them -- the number the owner needs to decide whether closing the
  gap is a --help edit or a "global flags" line.

  Exit code: 0 unless a STRUCTURAL assertion or a CONTROL fails (the scan
  itself broke). The gap count is REPORTED, not asserted, until the owner
  scopes it -- see docs\PLAN-flag-docs-and-guard.md section 10.

  Usage: pwsh -NoProfile -File tests\autotest\verb_flag_matrix.ps1 [-Json]
#>
[CmdletBinding()]
param(
  [string] $Exe  = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string] $Repo = "$PSScriptRoot\..\..",
  [switch] $Json,
  [switch] $Quiet
)

$ErrorActionPreference = 'Stop'
$script:Failed = $false

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $status = if ($Ok) { 'PASS' } else { 'FAIL' }
  $color  = if ($Ok) { 'Green' } else { 'Red' }
  if (-not $Quiet -or -not $Ok) { Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color }
  if (-not $Ok) { $script:Failed = $true }
}
function Note([string]$Msg) { if (-not $Quiet) { Write-Host "      [NOTE] $Msg" -ForegroundColor DarkGray } }

$Repo = (Resolve-Path $Repo).Path
$Exe  = (Resolve-Path $Exe).Path
$FlagRx = '--[A-Za-z][A-Za-z0-9-]*'

# ---------------------------------------------------------------------------
# Strip-Pascal -- blank comments, string literals and inactive conditional
# branches, preserving every line break so line numbers survive.
# Returns two views: Code (strings KEPT -- the flag and verb literals live in
# them) and CodeNoStr (strings blanked -- the view every FIELD-READ scan uses).
# ---------------------------------------------------------------------------
function Strip-Pascal([string]$Text, [string[]]$Defined) {
  $tokRx = [regex]'(?s)//[^\r\n]*|\{\$[^}]*\}|\{[^}]*\}|\(\*\$.*?\*\)|\(\*.*?\*\)|''(?:[^''\r\n]|'''')*'''
  $sbCode  = New-Object System.Text.StringBuilder($Text.Length)
  $sbNoStr = New-Object System.Text.StringBuilder($Text.Length)
  $blank = [regex]'[^\r\n]'
  $stack = New-Object System.Collections.Generic.Stack[object]
  $active = $true; $taken = $true; $parent = $true
  $unknownIf = 0
  $pos = 0
  $defs = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
  foreach ($d in $Defined) { [void]$defs.Add($d) }
  $evalIf = {
    param([string]$expr)
    # Supports Defined(X) / not Defined(X) / IFDEF X shapes only; anything
    # else is UNKNOWN and treated as active (conservative: keep the code).
    if ($expr -match '^(?i)\s*not\s+defined\s*\(\s*(\w+)\s*\)\s*$') { return @{ Known = $true; Value = -not $defs.Contains($Matches[1]) } }
    if ($expr -match '^(?i)\s*defined\s*\(\s*(\w+)\s*\)\s*$')       { return @{ Known = $true; Value = $defs.Contains($Matches[1]) } }
    return @{ Known = $false; Value = $true }
  }
  foreach ($m in $tokRx.Matches($Text)) {
    $code = $Text.Substring($pos, $m.Index - $pos)
    if (-not $active) { $code = $blank.Replace($code, ' ') }
    [void]$sbCode.Append($code); [void]$sbNoStr.Append($code)
    $tok = $m.Value
    if ($tok.StartsWith('{$') -or $tok.StartsWith('(*$')) {
      $body = if ($tok.StartsWith('{$')) { $tok.Substring(2, $tok.Length - 3) } else { $tok.Substring(3, $tok.Length - 5) }
      $body = $body.Trim()
      if ($body -match '^(?i)IFDEF\s+(\w+)') {
        $stack.Push(@{ Parent = $parent; Taken = $taken; Active = $active })
        $parent = $active; $taken = $defs.Contains($Matches[1]); $active = $parent -and $taken
      } elseif ($body -match '^(?i)IFNDEF\s+(\w+)') {
        $stack.Push(@{ Parent = $parent; Taken = $taken; Active = $active })
        $parent = $active; $taken = -not $defs.Contains($Matches[1]); $active = $parent -and $taken
      } elseif ($body -match '^(?i)IF\s+(.*)$') {
        $stack.Push(@{ Parent = $parent; Taken = $taken; Active = $active })
        $r = & $evalIf $Matches[1]
        if (-not $r.Known) { $unknownIf++ }
        $parent = $active; $taken = $r.Value; $active = $parent -and $taken
      } elseif ($body -match '^(?i)ELSEIF\s+(.*)$') {
        if ($taken) { $active = $false }
        else { $r = & $evalIf $Matches[1]; if (-not $r.Known) { $unknownIf++ }; $taken = $r.Value; $active = $parent -and $taken }
      } elseif ($body -match '^(?i)ELSE\b') {
        $active = $parent -and (-not $taken); $taken = $true
      } elseif ($body -match '^(?i)(ENDIF|IFEND)\b') {
        if ($stack.Count -gt 0) { $f = $stack.Pop(); $parent = $f.Parent; $taken = $f.Taken; $active = $f.Active }
      }
      # every directive is blanked in both views
      $b = $blank.Replace($tok, ' '); [void]$sbCode.Append($b); [void]$sbNoStr.Append($b)
    } elseif ($tok.StartsWith("'")) {
      if ($active) { [void]$sbCode.Append($tok) } else { [void]$sbCode.Append($blank.Replace($tok, ' ')) }
      [void]$sbNoStr.Append($blank.Replace($tok, ' '))
    } else {
      $b = $blank.Replace($tok, ' '); [void]$sbCode.Append($b); [void]$sbNoStr.Append($b)
    }
    $pos = $m.Index + $m.Length
  }
  $tail = $Text.Substring($pos)
  if (-not $active) { $tail = $blank.Replace($tail, ' ') }
  [void]$sbCode.Append($tail); [void]$sbNoStr.Append($tail)
  return @{ Code = $sbCode.ToString(); CodeNoStr = $sbNoStr.ToString(); UnknownIf = $unknownIf; Unbalanced = $stack.Count }
}

# Split a text into column-0 routine spans. Returns ordered list of
# @{Name; Last; Start; End; Header; Code; NoStr}. Forward declarations produce
# a body-less span; the caller merges by name.
function Get-RoutineSpans([string]$Code, [string]$NoStr) {
  $hdrRx = [regex]'(?m)^(function|procedure|constructor|destructor)\s+([A-Za-z_][\w.]*)'
  $hs = @($hdrRx.Matches($Code))
  $spans = New-Object System.Collections.Generic.List[object]
  for ($k = 0; $k -lt $hs.Count; $k++) {
    $s = $hs[$k].Index
    $e = if ($k + 1 -lt $hs.Count) { $hs[$k + 1].Index } else { $Code.Length }
    $seg = $Code.Substring($s, $e - $s)
    # header = up to the closing paren of the first '(' (or the first ';')
    $hdrEnd = $seg.IndexOf(';')
    $po = $seg.IndexOf('('); if ($po -ge 0 -and $po -lt $hdrEnd) { $pc = $seg.IndexOf(')', $po); if ($pc -gt 0) { $hdrEnd = $seg.IndexOf(';', $pc) } }
    if ($hdrEnd -lt 0) { $hdrEnd = [Math]::Min($seg.Length, 200) }
    $name = $hs[$k].Groups[2].Value
    $spans.Add(@{ Name = $name; Last = ($name -split '\.')[-1]; Start = $s; End = $e
                  Header = $seg.Substring(0, $hdrEnd); Code = $seg; NoStr = $NoStr.Substring($s, $e - $s) })
  }
  return ,$spans
}

# TArgs receiver names visible inside a span: parameters typed TArgs plus
# locals typed TArgs (var block or inline `var X: TArgs :=`).
function Get-ArgNames($Span) {
  $names = New-Object System.Collections.Generic.HashSet[string]
  foreach ($m in [regex]::Matches($Span.Header, '(?:\b(?:const|var|out)\s+)?([\w\s,]+?)\s*:\s*TArgs\b')) {
    foreach ($n in ($m.Groups[1].Value -split ',')) { $n = $n.Trim() -replace '^(const|var|out)\s+', ''; if ($n -match '^\w+$') { [void]$names.Add($n) } }
  }
  foreach ($m in [regex]::Matches($Span.NoStr, '(?m)^\s+(?:var\s+)?(\w+)\s*:\s*TArgs\s*(?:;|:=)')) { [void]$names.Add($m.Groups[1].Value) }
  return ,$names
}

# Field reads and whole-record uses of the given receiver names in a span.
# A whole-record use inside a call `Callee(..., name, ...)` becomes an edge to
# the LAST identifier segment before the call's open paren. A use that is the
# RHS of `X := name` is a COPY and is recorded separately, not followed.
function Get-SpanUses($Span, $Names) {
  $reads = New-Object System.Collections.Generic.HashSet[string]
  $edges = New-Object System.Collections.Generic.HashSet[string]
  $copyEdges = New-Object System.Collections.Generic.HashSet[string]
  $copies = New-Object System.Collections.Generic.List[string]
  $other  = New-Object System.Collections.Generic.List[string]
  if ($Names.Count -eq 0) { return @{ Reads = $reads; Edges = $edges; CopyEdges = $copyEdges; Copies = $copies; Other = $other } }
  $alt = ($Names | ForEach-Object { [regex]::Escape($_) }) -join '|'
  $t = $Span.NoStr
  # A local that is ASSIGNED from a receiver is a COPY: its own field reads
  # count (they are reads of the same values), but passing the copy onward is
  # a nested invocation with a record the callee owns -- recorded, not followed.
  $copyNames = New-Object System.Collections.Generic.HashSet[string]
  foreach ($m in [regex]::Matches($t, "\b(\w+)\s*(?::\s*TArgs\s*)?:=\s*(?:$alt)\s*;")) { [void]$copyNames.Add($m.Groups[1].Value); $copies.Add($m.Groups[1].Value) }
  foreach ($m in [regex]::Matches($t, "\b(?:$alt)\.(\w+)\b(?!\s*:=)")) { [void]$reads.Add($m.Groups[1].Value) }
  foreach ($m in [regex]::Matches($t, "\b(?:$alt)\b(?!\s*[.:])")) {
    # skip the header (declaration) region
    if ($m.Index -lt $Span.Header.Length) { continue }
    # RHS of a copy?
    $before = $t.Substring([Math]::Max(0, $m.Index - 120), [Math]::Min(120, $m.Index))
    if ($before -match '(\w+)\s*(?::\s*TArgs\s*)?:=\s*$') { continue }
    $isCopy = $copyNames.Contains($m.Value)
    # backward paren scan to find the enclosing call
    $depth = 0; $j = $m.Index - 1; $found = -1
    while ($j -ge 0) {
      $c = $t[$j]
      if ($c -eq ')') { $depth++ }
      elseif ($c -eq '(') { if ($depth -eq 0) { $found = $j; break } else { $depth-- } }
      elseif ($c -eq ';' -and $depth -eq 0) { break }
      $j--
    }
    if ($found -lt 0) { $other.Add($t.Substring([Math]::Max(0, $m.Index - 40), [Math]::Min(60, $t.Length - [Math]::Max(0, $m.Index - 40))).Trim()); continue }
    $lhs = $t.Substring([Math]::Max(0, $found - 200), $found - [Math]::Max(0, $found - 200))
    if ($lhs -match '([\w.]+)\s*$') {
      $callee = ($Matches[1] -split '\.')[-1]
      if ($isCopy) { [void]$copyEdges.Add($callee) } else { [void]$edges.Add($callee) }
    }
    else { $other.Add($t.Substring([Math]::Max(0, $m.Index - 40), 60).Trim()) }
  }
  return @{ Reads = $reads; Edges = $edges; CopyEdges = $copyEdges; Copies = $copies; Other = $other }
}

# Split a routine body into its `if / else if / else` chain pieces at the
# given indentation depths. Each piece = @{Cond; Body; Start}.
function Split-Chain([string]$Text, [int]$MinIndent, [int]$MaxIndent) {
  $rx = [regex]("(?m)^[ ]{$MinIndent,$MaxIndent}(?:else\s+if|if|else)\b")
  $ms = @($rx.Matches($Text))
  $pieces = New-Object System.Collections.Generic.List[object]
  for ($k = 0; $k -lt $ms.Count; $k++) {
    $s = $ms[$k].Index
    $e = if ($k + 1 -lt $ms.Count) { $ms[$k + 1].Index } else { $Text.Length }
    $seg = $Text.Substring($s, $e - $s)
    $tm = [regex]::Match($seg, '(?s)^(.*?)\bthen\b')
    if ($tm.Success) { $pieces.Add(@{ Cond = $tm.Groups[1].Value; Body = $seg.Substring($tm.Length); Start = $s }) }
    else { $pieces.Add(@{ Cond = ''; Body = $seg; Start = $s }) }
  }
  return ,$pieces
}

# ---------------------------------------------------------------------------
# 0. inputs
# ---------------------------------------------------------------------------
if (-not $Quiet) { Write-Host '== per-verb flag matrix (source-derived) ==' -ForegroundColor Cyan }
$cliPas = Join-Path $Repo 'src\cli\DRagLint.CLI.pas'
Check 'CLI source present' (Test-Path -LiteralPath $cliPas) $cliPas
Check 'engine exe present'  (Test-Path -LiteralPath $Exe) $Exe
if ($script:Failed) { Write-Host 'VERB FLAG MATRIX: FAIL' -ForegroundColor Red; exit 1 }
$raw = [IO.File]::ReadAllText($cliPas, [Text.Encoding]::ASCII)
# The deployed engine is Win64; WIN64 is the only conditional symbol this unit tests.
$Defines = @('WIN64', 'MSWINDOWS', 'CPUX64')

function Build-Matrix([string]$Src, [string]$HelpText) {
  $st = Strip-Pascal $Src $Defines
  $out = @{ Strip = $st }
  Check 'strip: conditional directives balanced' ($st.Unbalanced -eq 0) "$($st.Unbalanced) unclosed {`$IF} at EOF"
  if ($st.UnknownIf -gt 0) { Note "$($st.UnknownIf) {`$IF expr} could not be evaluated and were kept ACTIVE" }
  Check 'strip: no `with AArgs do` in the unit (field reads are always qualified)' `
    (-not [regex]::IsMatch($st.CodeNoStr, '\bwith\s+\w*Args\b')) 'a with-statement makes field reads bare; the scan cannot see them'

  $spans = Get-RoutineSpans $st.Code $st.CodeNoStr
  $byName = @{}
  foreach ($sp in $spans) { if (-not $byName.ContainsKey($sp.Last)) { $byName[$sp.Last] = New-Object System.Collections.Generic.List[object] }; $byName[$sp.Last].Add($sp) }
  Check 'routine spans located' ($spans.Count -gt 200) "($($spans.Count) column-0 routine header(s))"

  # --- 1. ParseArgs: flag -> fields --------------------------------------------
  $pa = $byName['ParseArgs']
  Check 'ParseArgs span located' ($null -ne $pa -and $pa.Count -ge 1) ''
  $flagFields = [ordered]@{}   # flag -> HashSet[field]
  $paLiterals = 0; $paLost = @()
  if ($pa) {
    $paCode = ($pa | Where-Object { $_.Code.Length -gt 400 } | Select-Object -First 1).Code
    $pieces = Split-Chain $paCode 2 4
    $flagPieces = 0
    foreach ($p in $pieces) {
      $fl = @([regex]::Matches($p.Cond, "\bA\s*=\s*'($FlagRx)'") | ForEach-Object { $_.Groups[1].Value }) +
            @([regex]::Matches($p.Cond, "A\.StartsWith\('($FlagRx)'") | ForEach-Object { $_.Groups[1].Value })
      if ($fl.Count -eq 0) { continue }
      $flagPieces++
      $fields = New-Object System.Collections.Generic.HashSet[string]
      foreach ($m in [regex]::Matches($p.Body, 'Result\.(\w+)\s*(?:\[[^\]]*\])?\s*:=')) { [void]$fields.Add($m.Groups[1].Value) }
      foreach ($m in [regex]::Matches($p.Body, 'SetLength\(Result\.(\w+)')) { [void]$fields.Add($m.Groups[1].Value) }
      foreach ($f in ($fl | Sort-Object -Unique)) {
        if (-not $flagFields.Contains($f)) { $flagFields[$f] = New-Object System.Collections.Generic.HashSet[string] }
        foreach ($x in $fields) { [void]$flagFields[$f].Add($x) }
      }
      # a flag literal in a BODY must be the piece's own flag (nested re-test), else the split is wrong
      foreach ($m in [regex]::Matches($p.Body, "\bA\s*=\s*'($FlagRx)'")) { if ($fl -notcontains $m.Groups[1].Value) { $paLost += $m.Groups[1].Value } }
    }
    $paLiterals = ([regex]::Matches($paCode, "\bA\s*=\s*'$FlagRx'")).Count
    Check 'ParseArgs: chain pieces with a flag parsed' ($flagPieces -gt 100) "($flagPieces piece(s), $paLiterals flag literal(s))"
    Check 'ParseArgs: every flag literal sits in a chain CONDITION' ($paLost.Count -eq 0) ("literal(s) found in a piece BODY -- the chain split is wrong: " + (($paLost | Sort-Object -Unique) -join ' '))
  }
  $out.FlagFields = $flagFields
  $fieldFlags = @{}
  foreach ($f in $flagFields.Keys) { foreach ($x in $flagFields[$f]) { if (-not $fieldFlags.ContainsKey($x)) { $fieldFlags[$x] = New-Object System.Collections.Generic.HashSet[string] }; [void]$fieldFlags[$x].Add($f) } }
  $out.FieldFlags = $fieldFlags
  $out.FieldlessFlags = @($flagFields.Keys | Where-Object { $flagFields[$_].Count -eq 0 })

  # --- 2. readers: routine -> reads / edges --------------------------------------
  $readers = @{}
  $copySites = New-Object System.Collections.Generic.List[string]
  $otherUses = New-Object System.Collections.Generic.List[string]
  foreach ($sp in $spans) {
    if ($sp.Last -eq 'ParseArgs' -or $sp.Last -eq 'LoadConfigDefaults') { continue }  # writers, not readers
    $names = Get-ArgNames $sp
    if ($names.Count -eq 0) { continue }
    $u = Get-SpanUses $sp $names
    if (-not $readers.ContainsKey($sp.Last)) { $readers[$sp.Last] = @{ Reads = (New-Object System.Collections.Generic.HashSet[string]); Edges = (New-Object System.Collections.Generic.HashSet[string]) } }
    foreach ($r in $u.Reads) { [void]$readers[$sp.Last].Reads.Add($r) }
    foreach ($e in $u.Edges) { [void]$readers[$sp.Last].Edges.Add($e) }
    foreach ($c in $u.Copies) { $copySites.Add("$($sp.Name) copies the record into $c" + $(if ($u.CopyEdges.Count -gt 0) { " and passes it to " + (($u.CopyEdges | Sort-Object) -join ', ') })) }
    foreach ($o in $u.Other)  { $otherUses.Add("$($sp.Name): $o") }
  }
  $out.Readers = $readers; $out.CopySites = $copySites; $out.OtherUses = $otherUses
  Check 'readers: TArgs-taking routines found' ($readers.Count -gt 100) "($($readers.Count))"
  $unknownEdges = @()
  foreach ($k in $readers.Keys) { foreach ($e in $readers[$k].Edges) { if (-not $readers.ContainsKey($e)) { $unknownEdges += "$k -> $e" } } }
  $out.UnknownEdges = $unknownEdges

  # closure: field -> the set of routines (reachable from Name) that read it.
  # Knowing WHO reads a field is what lets a missing cell be labelled "direct"
  # (the verb's own routine) or "via <helper>" (shared plumbing).
  $closure = @{}
  function Get-Closure([string]$Name, $Readers, $Memo) {
    if ($Memo.ContainsKey($Name)) { return $Memo[$Name] }
    $acc = @{}
    $Memo[$Name] = $acc   # cycle guard
    if ($Readers.ContainsKey($Name)) {
      foreach ($r in $Readers[$Name].Reads) { if (-not $acc.ContainsKey($r)) { $acc[$r] = New-Object System.Collections.Generic.HashSet[string] }; [void]$acc[$r].Add($Name) }
      foreach ($e in $Readers[$Name].Edges) {
        $sub = Get-Closure $e $Readers $Memo
        foreach ($r in $sub.Keys) { if (-not $acc.ContainsKey($r)) { $acc[$r] = New-Object System.Collections.Generic.HashSet[string] }; foreach ($w in $sub[$r]) { [void]$acc[$r].Add($w) } }
      }
    }
    return $acc
  }

  # --- 3. roots: Run's dispatch chain -> verb ------------------------------------
  $run = $byName['Run']
  Check 'Run span located' ($null -ne $run) ''
  $verbFields = [ordered]@{}
  $verbRoots  = [ordered]@{}
  if ($run) {
    # `Run` is DECLARED in the interface (column 0, no body) and IMPLEMENTED
    # later; the implementation is the span that carries the dispatch chain.
    $rs = ($run | Sort-Object { ([regex]::Matches($_.Code, "Args\.Command\s*=\s*'")).Count } -Descending | Select-Object -First 1)
    $pieces = Split-Chain $rs.Code 2 4
    foreach ($p in $pieces) {
      $vs = @([regex]::Matches($p.Cond, "Args\.Command\s*=\s*'([a-z][a-z0-9-]*)'") | ForEach-Object { $_.Groups[1].Value })
      if ($vs.Count -eq 0) { continue }
      $acc = @{}     # field -> HashSet[reader routine]; 'Run' stands for the dispatch branch itself
      $roots = New-Object System.Collections.Generic.HashSet[string]
      # direct reads in the branch body (strings blanked view of the same offsets)
      $bodyNoStr = $rs.NoStr.Substring($p.Start + ($p.Cond.Length + 4), [Math]::Min($p.Body.Length, $rs.NoStr.Length - $p.Start - $p.Cond.Length - 4))
      foreach ($m in [regex]::Matches($bodyNoStr, '\bArgs\.(\w+)\b(?!\s*:=)')) {
        $f = $m.Groups[1].Value
        if ($f -eq 'Command') { continue }
        if (-not $acc.ContainsKey($f)) { $acc[$f] = New-Object System.Collections.Generic.HashSet[string] }; [void]$acc[$f].Add('Run')
      }
      foreach ($m in [regex]::Matches($bodyNoStr, '\b(\w+)\s*\(\s*Args\s*[,)]')) {
        $c = $m.Groups[1].Value; [void]$roots.Add($c)
        $sub = Get-Closure $c $readers $closure
        foreach ($f in $sub.Keys) { if (-not $acc.ContainsKey($f)) { $acc[$f] = New-Object System.Collections.Generic.HashSet[string] }; foreach ($w in $sub[$f]) { [void]$acc[$f].Add($w) } }
      }
      foreach ($v in $vs) { $verbFields[$v] = $acc; $verbRoots[$v] = $roots }
    }
  }
  Check 'Run: verbs attributed from the dispatch chain' ($verbFields.Count -gt 50) "($($verbFields.Count) verb(s))"
  $out.VerbFields = $verbFields; $out.VerbRoots = $verbRoots

  # accepted flags per verb, each with the routines through which it arrives
  $accepted = [ordered]@{}   # verb -> HashSet[flag]
  $channel  = [ordered]@{}   # verb -> @{ flag -> HashSet[routine] }
  foreach ($v in $verbFields.Keys) {
    $s = New-Object System.Collections.Generic.HashSet[string]
    $ch = @{}
    foreach ($f in $verbFields[$v].Keys) {
      if (-not $fieldFlags.ContainsKey($f)) { continue }
      foreach ($x in $fieldFlags[$f]) {
        [void]$s.Add($x)
        if (-not $ch.ContainsKey($x)) { $ch[$x] = New-Object System.Collections.Generic.HashSet[string] }
        foreach ($w in $verbFields[$v][$f]) { [void]$ch[$x].Add($w) }
      }
    }
    $accepted[$v] = $s; $channel[$v] = $ch
  }
  $out.Accepted = $accepted; $out.Channel = $channel
  # aliases: flags that bind exactly the same field set (--in/--file, --out/--output,
  # --seealso/--no-seealso ...). Documenting one documents the other.
  $sig = @{}
  foreach ($f in $flagFields.Keys) { $k = (($flagFields[$f] | Sort-Object) -join ','); if ($k -eq '') { continue }; if (-not $sig.ContainsKey($k)) { $sig[$k] = New-Object System.Collections.Generic.List[string] }; $sig[$k].Add($f) }
  $aliases = @{}
  foreach ($k in $sig.Keys) { foreach ($f in $sig[$k]) { $aliases[$f] = @($sig[$k] | Where-Object { $_ -ne $f }) } }
  $out.Aliases = $aliases

  # --- 4. banner: verb -> documented flags ----------------------------------------
  $documented = [ordered]@{}
  $knownVerbs = New-Object System.Collections.Generic.HashSet[string]
  foreach ($v in $verbFields.Keys) { [void]$knownVerbs.Add($v) }
  $cur = ''; $blockVerbs = @(); $blockName = ''; $blocks = [ordered]@{}
  foreach ($l in ($HelpText -split "`r?`n")) {
    if ($l -match '^\S') { $cur = ''; $blockVerbs = @(); continue }
    # A NAMED BLOCK -- `  Output/CI (lint, lint-all, check-ast):` -- credits its
    # flags to exactly the verbs it names, and ends at the next verb line.
    $bm = [regex]::Match($l, '^\s{2}([A-Za-z][A-Za-z/ ]*)\s*\(([a-z0-9, -]+)\):\s*$')
    if ($bm.Success) { $blockName = $bm.Groups[1].Value.Trim(); $blockVerbs = @($bm.Groups[2].Value -split ',\s*' | ForEach-Object { $_.Trim() } | Where-Object { $_ }); $cur = ''; $blocks[$blockName] = $blockVerbs; continue }
    # A block OPENER is a usage line (`  drag-lint <verb> ...`) or a COMMON
    # QUESTIONS row (question, 2+ spaces, `drag-lint <verb>`). A backticked
    # mention inside continuation prose (`see `drag-lint shutdown``) is NOT an
    # opener -- measured: it re-attributed lsp's --proxy line to shutdown.
    $vm = [regex]::Match($l, '^\s{2}(?:[^`]*?\s{2,})?drag-lint\s+([a-z][a-z0-9-]*)\b')
    if ($vm.Success -and $knownVerbs.Contains($vm.Groups[1].Value)) { $cur = $vm.Groups[1].Value; $blockVerbs = @() }
    $targets = if ($cur -ne '') { @($cur) } else { $blockVerbs }
    # A section sentence that names verbs in parentheses -- `[--size-guard-mb N]
    # [--force32] apply wherever a db is OPENED (index, query, lsp, serve)` --
    # credits ITS OWN flags to exactly those verbs.
    if ($cur -eq '') {
      $lm = [regex]::Match($l, '\(([a-z][a-z0-9-]*(?:,\s*[a-z][a-z0-9-]*)+)\)')
      if ($lm.Success) { $lv = @($lm.Groups[1].Value -split ',\s*'); if (@($lv | Where-Object { -not $knownVerbs.Contains($_) }).Count -eq 0) { $targets = @($targets) + $lv } }
    }
    foreach ($tv in $targets) {
      if (-not $documented.Contains($tv)) { $documented[$tv] = New-Object System.Collections.Generic.HashSet[string] }
      foreach ($m in [regex]::Matches($l, $FlagRx)) { [void]$documented[$tv].Add($m.Value) }
    }
  }
  $out.Documented = $documented; $out.Blocks = $blocks
  Check 'banner: verb blocks parsed' ($documented.Count -gt 50) "($($documented.Count) verb(s) with a block)"
  Check 'banner: the Output/CI block names its verbs' ($blocks.Contains('Output/CI') -and $blocks['Output/CI'].Count -ge 3) 'the `Output/CI (lint, lint-all, check-ast):` header changed shape'
  $dbGlobal = [regex]::IsMatch($HelpText, '--db is repeatable, on every verb that takes it')
  Check 'banner: --db is declared global in the Databases section' $dbGlobal 'the sentence that credits --db to every verb is gone; re-derive $GlobalInHelp'
  $out.GlobalInHelp = @(if ($dbGlobal) { '--db' })
  return $out
}

$helpText = (& $Exe --help 2>&1 | Out-String)
$M = Build-Matrix $raw $helpText

# ---------------------------------------------------------------------------
# exemptions -- read from the docs-sync guard so there is ONE list, not two
# ---------------------------------------------------------------------------
$guardPath = Join-Path $PSScriptRoot 'run_docs_sync_guard.ps1'
$guardText = Get-Content -LiteralPath $guardPath -Raw
function Read-OrderedTable([string]$Text, [string]$VarName) {
  $m = [regex]::Match($Text, "(?s)\`$$VarName\s*=\s*(\[ordered\]@\{.*?\r?\n\})")
  if (-not $m.Success) { return $null }
  return (Invoke-Expression $m.Groups[1].Value)
}
$UndocVerbs = Read-OrderedTable $guardText 'UndocumentedOnPurpose'
$UndocFlags = Read-OrderedTable $guardText 'FlagUndocumentedOnPurpose'
Check 'exemptions: $UndocumentedOnPurpose read from the docs-sync guard' ($null -ne $UndocVerbs -and $UndocVerbs.Count -gt 3) ''
Check 'exemptions: $FlagUndocumentedOnPurpose read from the docs-sync guard' ($null -ne $UndocFlags -and $UndocFlags.Count -gt 3) ''
# Flags that bind to NO TArgs field cannot be attributed to a verb by this
# map. Each is named with the reason; a new one fails loudly rather than
# vanishing from the matrix.
$FieldlessOnPurpose = [ordered]@{
  '--case-sensitive'  = 'sets DRagLint.Storage.SQLite.CaseSensitiveLookups (process-wide), documented on query'
  '--stdio'           = 'accepted no-op LSP transport token, documented on lsp'
  '--clientProcessId' = 'accepted no-op LSP client token, documented on lsp'
}
$fieldless = @($M.FieldlessFlags | Where-Object { -not $FieldlessOnPurpose.Contains($_) })
Check 'ParseArgs: every field-less flag is named in $FieldlessOnPurpose' ($fieldless.Count -eq 0) ("unattributable flag(s): " + ($fieldless -join ' '))
$flStale = @($FieldlessOnPurpose.Keys | Where-Object { $M.FieldlessFlags -notcontains $_ })
Check 'ParseArgs: no $FieldlessOnPurpose entry now binds a field' ($flStale.Count -eq 0) ("delete the entry: " + ($flStale -join ' '))

# ---------------------------------------------------------------------------
# the matrix and the gap
# ---------------------------------------------------------------------------
$rows = New-Object System.Collections.Generic.List[object]
$totalMissing = 0; $totalCells = 0; $totalDirect = 0
$missByFlag = @{}; $missByChannel = @{}
foreach ($v in $M.Accepted.Keys) {
  if ($UndocVerbs -and $UndocVerbs.Contains($v)) { continue }
  $roots = New-Object System.Collections.Generic.HashSet[string]
  foreach ($r in @($M.VerbRoots[$v])) { [void]$roots.Add($r) }; [void]$roots.Add('Run')
  $acc = @($M.Accepted[$v] | Where-Object { -not $UndocFlags.Contains($_) -and $M.GlobalInHelp -notcontains $_ } | Sort-Object)
  $doc = if ($M.Documented.Contains($v)) { $M.Documented[$v] } else { New-Object System.Collections.Generic.HashSet[string] }
  # a cell is documented if the flag OR an alias of it is on the verb's lines
  $missing = @($acc | Where-Object { $f = $_; -not $doc.Contains($f) -and -not (@($M.Aliases[$f]) | Where-Object { $doc.Contains($_) }) })
  $direct = @(); $via = [ordered]@{}
  foreach ($f in $missing) {
    $ch = $M.Channel[$v][$f]
    if (@($ch | Where-Object { $roots.Contains($_) }).Count -gt 0) { $direct += $f }
    else {
      $k = (($ch | Sort-Object) -join '+')
      if (-not $via.Contains($k)) { $via[$k] = @() }
      $via[$k] += $f
      $missByChannel[$k] = 1 + $missByChannel[$k]
    }
  }
  $phantom = @($doc | Where-Object { $_ -ne '--help' -and $M.GlobalInHelp -notcontains $_ -and -not $M.Accepted[$v].Contains($_) } | Sort-Object)
  $totalMissing += $missing.Count; $totalCells += $acc.Count; $totalDirect += $direct.Count
  foreach ($f in $missing) { $missByFlag[$f] = 1 + $missByFlag[$f] }
  $rows.Add([pscustomobject]@{ Verb = $v; Accepted = $acc.Count; Documented = ($acc.Count - $missing.Count); Missing = $missing; Direct = $direct; Via = $via; Phantom = $phantom; Roots = @($M.VerbRoots[$v]) })
}

if (-not $Quiet) {
  Write-Host ''
  Write-Host '-- matrix (verb: accepted / documented on its lines; MISSING split by how the flag reaches the verb)' -ForegroundColor Cyan
  foreach ($r in ($rows | Sort-Object { -$_.Missing.Count }, Verb)) {
    $line = ("  {0,-22} {1,3} / {2,3}" -f $r.Verb, $r.Accepted, $r.Documented)
    if ($r.Missing.Count -eq 0) { Write-Host $line -ForegroundColor DarkGray; continue }
    Write-Host $line -ForegroundColor Yellow
    if ($r.Direct.Count -gt 0) { Write-Host ("      DIRECT (read in {0}): {1}" -f (($r.Roots | Sort-Object) -join '/'), ($r.Direct -join ' ')) -ForegroundColor Yellow }
    foreach ($k in $r.Via.Keys) { Write-Host ("      via {0}: {1}" -f $k, ($r.Via[$k] -join ' ')) -ForegroundColor DarkYellow }
  }
  Write-Host ''
  Write-Host ("-- GAP: {0} missing (verb, flag) cell(s) out of {1} accepted cells across {2} documented verb(s)" -f $totalMissing, $totalCells, $rows.Count) -ForegroundColor Cyan
  Write-Host ("        {0} DIRECT (the verb's own routine reads the field) + {1} via shared helpers" -f $totalDirect, ($totalMissing - $totalDirect)) -ForegroundColor Cyan
  Write-Host '-- indirect cells by the helper(s) that read the field:' -ForegroundColor Cyan
  foreach ($e in ($missByChannel.GetEnumerator() | Sort-Object { -$_.Value }, Key)) { Write-Host ("  {0,3}  via {1}" -f $e.Value, $e.Key) }
  Write-Host '-- flags ranked by the number of verbs whose lines omit them:' -ForegroundColor Cyan
  foreach ($e in ($missByFlag.GetEnumerator() | Sort-Object { -$_.Value }, Key)) { Write-Host ("  {0,3}  {1}" -f $e.Value, $e.Key) }
  Write-Host ''
  Note ("record COPIES not followed ({0}): {1}" -f $M.CopySites.Count, ($M.CopySites -join '; '))
  if ($M.UnknownEdges.Count -gt 0) { Note ("whole-record uses passed to a routine with no TArgs span ({0}): {1}" -f $M.UnknownEdges.Count, (($M.UnknownEdges | Sort-Object -Unique) -join '; ')) }
  if ($M.OtherUses.Count -gt 0)    { Note ("whole-record uses that are neither a call nor a copy ({0}): {1}" -f $M.OtherUses.Count, (($M.OtherUses | Sort-Object -Unique) -join ' | ')) }
  $ph = @($rows | Where-Object { $_.Phantom.Count -gt 0 })
  Note ("REVERSE direction (a verb's lines name a flag the verb never reads) is REPORTED ONLY -- continuation prose names other verbs' flags freely: {0} verb(s)" -f $ph.Count)
  foreach ($r in $ph) { Write-Host ("        {0,-22} {1}" -f $r.Verb, ($r.Phantom -join ' ')) -ForegroundColor DarkGray }
}

# ---------------------------------------------------------------------------
# CONTROLS -- the scan must be blind to comments, strings and dead branches,
# and sighted for a real read, a real flag binding and a live branch. Each
# plants a token in an in-memory copy of the source and rebuilds the matrix.
# ---------------------------------------------------------------------------
if (-not $Quiet) { Write-Host ''; Write-Host '-- controls' -ForegroundColor Cyan }
$g = [Guid]::NewGuid().ToString('N').Substring(0, 6)
$anchor = [regex]::Match($raw, '(?m)^function DoOutline\(const AArgs: TArgs\): Integer;\r?\n(?:var\r?\n(?:[^\r\n]*\r?\n)*?)?begin\r?\n')
Check 'CONTROL anchor: DoOutline body located for planting' $anchor.Success 'pick another Do<Verb> routine to plant into'
$paAnchor = [regex]::Match($raw, "(?m)^    else if A = '--json'    then Result\.AsJson:= True\r?\n")
Check 'CONTROL anchor: ParseArgs --json branch located for planting' $paAnchor.Success ''
if ($anchor.Success -and $paAnchor.Success) {
  $plant = @"
  // AArgs.ZzLineComment$g
  { AArgs.ZzBraceComment$g }
  (* AArgs.ZzParenComment$g *)
  Writeln('AArgs.ZzString$g');
{`$IFDEF ZZ_NEVER_DEFINED_$g}
  if AArgs.ZzDeadBranch$g then Writeln('dead');
{`$ELSE}
  if AArgs.ZzLiveBranch$g then Writeln('live');
{`$ENDIF}
  if AArgs.ZzPlainRead$g then Writeln('read');
  ZzHelper$g(AArgs);

"@
  $helper = "function ZzHelper$g(const AArgs: TArgs): Integer;`r`nbegin`r`n  Result:= Ord(AArgs.ZzViaCallee$g);`r`nend;`r`n`r`n"
  $ctlSrc = $raw.Substring(0, $anchor.Index) + $helper + $anchor.Value + $plant + $raw.Substring($anchor.Index + $anchor.Length)
  $ctlSrc = $ctlSrc.Insert($ctlSrc.IndexOf($paAnchor.Value), "    else if A = '--zz-planted-$g' then Result.ZzPlainRead${g}:= True`r`n")
  $C = Build-Matrix $ctlSrc $helpText
  $reads = $C.VerbFields['outline']
  Check 'CONTROL blind: a field read inside a // comment is NOT seen'    (-not $reads.ContainsKey("ZzLineComment$g")) ''
  Check 'CONTROL blind: a field read inside a { } comment is NOT seen'   (-not $reads.ContainsKey("ZzBraceComment$g")) ''
  Check 'CONTROL blind: a field read inside a (* *) comment is NOT seen' (-not $reads.ContainsKey("ZzParenComment$g")) ''
  Check 'CONTROL blind: a field read inside a string literal is NOT seen' (-not $reads.ContainsKey("ZzString$g")) ''
  Check 'CONTROL blind: a field read in an inactive {$IFDEF} branch is NOT seen' (-not $reads.ContainsKey("ZzDeadBranch$g")) ''
  Check 'CONTROL sighted: a field read in the {$ELSE} (live) branch IS seen' ($reads.ContainsKey("ZzLiveBranch$g")) ''
  Check 'CONTROL sighted: a plain field read IS seen'                     ($reads.ContainsKey("ZzPlainRead$g")) ''
  Check 'CONTROL sighted: a read inside a callee passed the record IS seen (closure)' ($reads.ContainsKey("ZzViaCallee$g")) ''
  Check 'CONTROL channel: the callee read is attributed to the callee, the plain read to DoOutline' `
    ($reads.ContainsKey("ZzViaCallee$g") -and $reads["ZzViaCallee$g"].Contains("ZzHelper$g") -and $reads.ContainsKey("ZzPlainRead$g") -and $reads["ZzPlainRead$g"].Contains('DoOutline')) ''
  Check 'CONTROL copy: a record COPY passed onward is recorded, not followed' `
    (@($C.CopySites | Where-Object { $_ -match 'DoDocumentProject copies the record into IndexArgs and passes it to DoIndex' }).Count -ge 1 -and -not $C.VerbFields['document'].ContainsKey('Watch')) `
    'either the DoDocumentProject copy site changed, or document now inherits index --watch through the copy'
  Check 'CONTROL sighted: a planted ParseArgs flag binds to its field'    ($C.FlagFields.Contains("--zz-planted-$g") -and $C.FlagFields["--zz-planted-$g"].Contains("ZzPlainRead$g")) ''
  Check 'CONTROL end-to-end: the planted flag is accepted by outline and reported MISSING' `
    ($C.Accepted['outline'].Contains("--zz-planted-$g") -and -not $C.Documented['outline'].Contains("--zz-planted-$g")) ''
  Check 'CONTROL isolation: the planted flag is NOT accepted by an unrelated verb (rules)' (-not $C.Accepted['rules'].Contains("--zz-planted-$g")) ''
}

if ($Json) {
  [pscustomobject]@{
    gap_cells = $totalMissing; accepted_cells = $totalCells; verbs = $rows.Count
    rows = @($rows | ForEach-Object { [pscustomobject]@{ verb = $_.Verb; accepted = $_.Accepted; documented = $_.Documented; missing = @($_.Missing); phantom = @($_.Phantom) } })
    by_flag = @($missByFlag.GetEnumerator() | Sort-Object { -$_.Value }, Key | ForEach-Object { [pscustomobject]@{ flag = $_.Key; verbs = $_.Value } })
  } | ConvertTo-Json -Depth 5
}

Write-Host ''
if ($script:Failed) { Write-Host 'VERB FLAG MATRIX: FAIL' -ForegroundColor Red; exit 1 }
Write-Host ("VERB FLAG MATRIX: PASS (gap = {0} cell(s), reported not asserted)" -f $totalMissing) -ForegroundColor Green
exit 0
