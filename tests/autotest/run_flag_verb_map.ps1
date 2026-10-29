<#
  run_flag_verb_map.ps1 -- the PER-VERB flag axis: derive it, prove the
  derivation still works, and report what --help does not say.

  WHAT THIS IS FOR
  ----------------
  CLAUDE.md's DOCS-IN-SYNC table promises, of `--help`:

      every verb the CLI accepts is listed;
      EVERY FLAG A VERB ACCEPTS IS LISTED ON THAT VERB'S LINE

  run_docs_sync_guard.ps1 check 1 enforces the first clause. The second was
  UNCHECKABLE, and that guard's check 9 header says exactly why: ParseArgs is
  verb-agnostic, so the parser does not know which verb takes which flag, and
  attributing flags from the banner BY POSITION is worse than useless (measured
  there: it gives --rebuild to resolve-dbs and --fix to exceptions-sync).

  tests\autotest\lib\CliFlagVerbMap.ps1 supplies the missing truth source, from
  SOURCE ALONE -- flag -> TArgs field -> reading routine -> verb. It does not
  use the index, deliberately: docs\INBOX-property-refs-never-resolve.md
  records that the resolver walks `kind = 'call'` only, so a field/property ref
  never gets a refs.symbol_id, and a map built on those refs would be a ghost
  measurement. Fixing that needs a resolver-version bump and a call_edges
  decision, both deferred; the text of one file already carries the chain.

  WHY THIS GUARD DOES NOT FAIL ON THE GAP IT FOUND
  ------------------------------------------------
  MEASURED, 2026-09-15, against the deployed Win64 exe and the source on disk:

      (verb, flag) cells the code consumes .......... 439
      cells missing from the verb's own --help line .. 124   across 33 verbs

  and the shape of it matters more than the total. 51 of the 124 sit on three
  lines -- lint-project 17, check-ast 17, lint-all 17 -- and they are the SAME
  seventeen lint/autofix/doc flags each time. The banner today factors that
  vocabulary onto the `lint` line and lets the reader carry it across; closing
  the gap literally means repeating it on every lint-shaped verb, which is a
  BANNER DESIGN decision, not a doc-drift bug.

  This repo's own rule decides the rest: a finding count that will be ignored
  IS the defect, and it is a defect in the RULE as often as in the code. A
  guard landing red over 124 cells nobody agreed to close is a guard that gets
  weakened, and a weakened guard costs more than a missing one. So:

    * the gap is PRINTED in full every run, never summarised away;
    * it is RATCHETED against the recorded baseline below, so it can grow no
      further silently -- adding a flag to a verb and not documenting it on
      that verb's line fails here, and that failure IS closable by whoever
      caused it;
    * closing the standing 124 is left to the owner, with the cost stated.

  Lower $BaselineCells when the banner is extended. Never raise it to get
  green: raising it is the weakening this header exists to prevent.

  WHAT IT HARD-FAILS ON
  ---------------------
  The derivation itself. Every assertion that reports a gap is of the form
  "this set difference is empty", and an empty set is what a BROKEN scanner
  produces too, so the scanner is proved alive before it is believed:

    * four PLANTED cases, on synthetic source, for the three ways a text scan
      of Pascal goes wrong -- a comment, a string literal, an inactive
      {$IFDEF} branch -- plus a positive control that the same planted read IS
      found when it is none of those. Without the control the three absence
      assertions pass against a scanner that finds nothing at all.
    * four STRUCTURAL assertions, each encoding a defect that was measured
      while building the map, not one imagined for the test:
        - TFbSnapshot.Run(AArgs.X) read as a call to the DISPATCHER Run, which
          silently gave fb-snapshot and link-orm all 161 flags;
        - Get-RoutineSpanRange matching the interface forward declaration of
          Run instead of its implementation, which yielded zero verbs while
          every downstream set stayed legitimately empty;
        - the four MULTI-LINE dispatch arms (index, lsp, resolve-dbs, serve)
          scoring as unresolved under an entry-routine-only model;
        - a branch's GUARD read of Result.Command counted as a binding, which
          handed --dir/--in-place/--root/--unit to nearly every verb.

  Exit code: 0 on full pass, 1 on any failure.

  Usage: pwsh -File tests\autotest\run_flag_verb_map.ps1
         pwsh -File tests\autotest\run_flag_verb_map.ps1 -Report   (matrix only)
#>
[CmdletBinding()]
param(
  [string] $Exe  = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string] $Repo = "$PSScriptRoot\..\..",
  [switch] $Report
)

$ErrorActionPreference = 'Stop'
$script:Failed = $false

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $status = if ($Ok) { 'PASS' } else { 'FAIL' }
  $color  = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
  if (-not $Ok) { $script:Failed = $true }
}

# FLAG ALIASES (docs\CLI-FLAG-ALIASES.md, features\flag-aliases.json). An alias
# is a second spelling of ONE option: same parser branch, same TArgs field. The
# policy: a verb line names the CANONICAL spelling only, and every alias is
# listed once, in the generated "Flag aliases:" section of --help. So this axis
# counts an OPTION, not a spelling: a verb that reads TArgs.Output consumes
# --output, and its line naming --output documents it -- --out is not a second,
# undocumentable cell. Folding happens BEFORE the gap is computed; the planted
# case below proves a NON-alias undocumented flag is still counted after it.
function Get-CanonicalFlag([string]$Flag, [hashtable]$AliasOf) {
  if ($AliasOf.ContainsKey($Flag)) { return $AliasOf[$Flag] }
  return $Flag
}

function Get-VerbGap($VerbFlags, [hashtable]$Blocks, $HelpSet, $GlobalFlags, [string[]]$Exempt, [hashtable]$AliasOf) {
  $rows = @(); $total = 0; $miss = 0; $noBlock = @()
  foreach ($verb in $VerbFlags.Keys) {
    if (-not $Blocks.ContainsKey($verb)) { $noBlock += $verb; continue }
    $want = @(@($VerbFlags[$verb] | ForEach-Object { Get-CanonicalFlag $_ $AliasOf }) | Sort-Object -Unique | Where-Object {
                $HelpSet.Contains($_) -and -not $GlobalFlags.Contains($_) -and ($Exempt -notcontains $_) })
    $m = @($want | Where-Object { -not $Blocks[$verb].Contains($_) })
    $total += $want.Count
    $miss  += $m.Count
    if ($m.Count -gt 0) { $rows += [pscustomobject]@{ verb = $verb; consumes = $want.Count; missing = $m.Count; flags = ($m -join ' ') } }
  }
  return [pscustomobject]@{ Rows = $rows; Total = $total; Missing = $miss; NoBlock = $noBlock }
}

# Every `(A = 'x') or (A = 'y')` test in the CLI source is an alias group. Read
# from the source, so the table cannot list a pair the parser does not accept,
# nor miss one it does.
function Get-ParserAliasGroups([string]$CliText) {
  $groups = @()
  foreach ($line in ($CliText -split "`r?`n")) {
    if ($line -notmatch "\(A\s*=\s*'-[^']*'\)\s*or\s*\(A\s*=\s*'-") { continue }
    $lits = @([regex]::Matches($line, "A\s*=\s*'(-[^']*)'") | ForEach-Object { $_.Groups[1].Value })
    if ($lits.Count -ge 2) { $groups += ,(@($lits | Sort-Object) -join ' ') }
  }
  return @($groups | Sort-Object -Unique)
}

# A token regex for one alias spelling: '-?' needs escaping, and '--in' must not
# match inside '--include'.
function Get-AliasTokenRx([string]$Alias) {
  return '(?<![A-Za-z0-9-])' + [regex]::Escape($Alias) + '(?![A-Za-z0-9-])'
}

# RECORDED BASELINE -- see the header. Measured 2026-09-15 at 44a2b0a; re-measured
# 2026-09-22 (C3a) at 124/33 after glyph-vacuum's banner gained the --output alias
# (the row that had pushed it to 125/34). 123 on 2026-09-23 (D4): lint-all's banner
# line gained --rule, which the verb already consumed (ifdef-undefined-symbol).
# 112/27 on 2026-09-23 (ENG-6, docs\INBOX-output-flag-canonicalisation.md): --out
# left the banner (silent alias of --output by owner ruling), which removes the 8
# cells where a verb consumed Output but its line named only --output
# (lint-all, schema, export, butterfly, sql, uses-report, graph, deps-report),
# and export / forms-csv / convert-scaffold gained --output on their own lines
# (3 cells). Six verbs had nothing else missing and left the table.
# 108/24 on 2026-10-26 (FLAG lane, docs\CLI-FLAG-ALIASES.md): the drift to 125/36
# was undone by (1) folding aliases to their canonical flag (--out read by a verb
# whose line names --output is ONE documented option, not a missing cell), (2)
# --json named on schema / butterfly / compare / menu-tree / menu-drift and
# --output on check-ast (kept from lane 909fc131, without its --output|--out),
# and despite (3) Apply / Fix leaving the pinned cross-verb set (refusal-only
# reads, CliFlagVerbMap.ps1), which put --apply/--fix back into the count (+4).
# 104/24 on 2026-10-27 (fix/help-out-json): the three remaining --json / --output cells whose code reads them
# are now named -- lint-project --output, check-ast --json, serve --json (error-format switch). 107 -> 104.
# 103 on 2026-10-27 (fix/help-compare-out-root): compare --out-root is now named on its --help line. 104 -> 103.
$BaselineCells = 103
$BaselineVerbs = 24

$Repo = (Resolve-Path $Repo).Path
. (Join-Path $Repo 'tests\autotest\lib\CliFlagVerbMap.ps1')

Write-Host '== per-verb flag map: flag -> TArgs field -> reader -> verb ==' -ForegroundColor Cyan

# Full path only. A bare `drag-lint` resolves off PATH to a frozen Win32 build
# on this machine (NoDefaultCurrentDirectoryInExePath=1).
Check 'engine exe present' (Test-Path -LiteralPath $Exe) $Exe
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host 'FLAG-VERB MAP: FAIL' -ForegroundColor Red; exit 1 }
$Exe = (Resolve-Path $Exe).Path
$Cli = Join-Path $Repo 'src\cli\DRagLint.CLI.pas'
Check 'CLI source present' (Test-Path -LiteralPath $Cli) $Cli

# ---------------------------------------------------------------------------
# PLANTED CASES -- the scanner must be proved able to be wrong, and proved not
# to be. Synthetic source, so each hazard is isolated; the real file has no
# WIN32-guarded AArgs read to plant against, and inventing one in it would be
# a change to the product to suit its test.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- planted cases (comment / string literal / inactive {$IFDEF})' -ForegroundColor Cyan

$plant = @"
function DoPlanted(const AArgs: TArgs): Integer;
begin
  { a brace comment naming AArgs.ZzInBraceComment and Result.ZzInBraceComment }
  // a line comment naming AArgs.ZzInLineComment
  (* an old-style comment naming AArgs.ZzInOldComment *)
  Writeln('a string literal naming AArgs.ZzInString and a fake {`$IFDEF} directive');
  Result:= AArgs.ZzPlainlyRead;
  {`$IFDEF WIN32}
  Result:= AArgs.ZzInDeadBranch;
  {`$ELSE}
  Result:= AArgs.ZzInLiveBranch;
  {`$ENDIF}
  {`$IFDEF ZZ_NO_RULING_FOR_THIS}
  Result:= AArgs.ZzInUnevaluatedBranch;
  {`$ENDIF}
end;
"@ -replace "`r?`n", "`r`n"

$pl  = ConvertTo-PascalProjections -Text $plant
$plr = Resolve-PascalConditionals -NoComments $pl.NoComments -Code $pl.Code
$seen = New-Object System.Collections.Generic.HashSet[string]
foreach ($m in [regex]::Matches($plr.Code, '\bAArgs\.([A-Za-z_][A-Za-z0-9_]*)')) { [void]$seen.Add($m.Groups[1].Value) }

# THE POSITIVE CONTROL COMES FIRST. Every assertion below it is an absence, and
# absence is also what a scanner that reads nothing reports.
Check 'CONTROL a plain AArgs read IS found (else every absence below is vacuous)' `
  ($seen.Contains('ZzPlainlyRead')) `
  'if this fails, every PLANT assertion below is vacuous'
Check 'CONTROL the lexer preserves length, so offsets stay true' `
  (($pl.NoComments.Length -eq $plant.Length) -and ($pl.Code.Length -eq $plant.Length)) `
  "in=$($plant.Length) nc=$($pl.NoComments.Length) cd=$($pl.Code.Length)"

Check 'PLANT a read inside a { brace comment } is not a read' (-not $seen.Contains('ZzInBraceComment')) ''
Check 'PLANT a read inside a // line comment is not a read'   (-not $seen.Contains('ZzInLineComment'))  ''
Check 'PLANT a read inside an (* old comment *) is not a read' (-not $seen.Contains('ZzInOldComment'))  ''
Check 'PLANT a read inside a string literal is not a read'     (-not $seen.Contains('ZzInString'))      ''
Check 'PLANT a read in an INACTIVE {$IFDEF WIN32} branch is dropped' (-not $seen.Contains('ZzInDeadBranch')) ''
Check 'PLANT a read in the ACTIVE {$ELSE} branch survives'           ($seen.Contains('ZzInLiveBranch'))      ''
Check 'PLANT an UNRULED {$IFDEF} keeps its branch (superset, not a silent drop)' `
  ($seen.Contains('ZzInUnevaluatedBranch')) ''
Check 'PLANT the unruled directive is NAMED, not swallowed' `
  ($plr.Unevaluated.Count -eq 1 -and $plr.Unevaluated[0] -match 'ZZ_NO_RULING_FOR_THIS') `
  ("unevaluated: " + ($plr.Unevaluated -join ' '))

# A {$IFDEF} printed from inside a Writeln must not open a conditional: it has
# no {$ENDIF}, so a scanner that reads it unbalances every conditional after it.
# CLI.pas:892 does exactly this, which is why the directive scan runs on the
# strings-blanked projection.
Check 'PLANT a {$IFDEF} inside a STRING LITERAL opens no conditional' `
  (@($plr.Unevaluated | Where-Object { $_ -notmatch 'ZZ_NO_RULING_FOR_THIS' }).Count -eq 0) `
  ("stray directive(s): " + (@($plr.Unevaluated | Where-Object { $_ -notmatch 'ZZ_NO_RULING_FOR_THIS' }) -join ' '))

# ---------------------------------------------------------------------------
# PLANTED ALIAS CASES -- the fold must be proved unable to hide a real gap.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- planted cases (alias fold)' -ForegroundColor Cyan
$pAlias = @{ '--zz-short' = '--zz-canon' }
$pVerbs = [ordered]@{ 'zz-verb' = @('--zz-canon', '--zz-short', '--zz-undoc', '--zz-named') }
$pBlock = New-Object System.Collections.Generic.HashSet[string]
[void]$pBlock.Add('--zz-canon'); [void]$pBlock.Add('--zz-named')
$pHelp = New-Object System.Collections.Generic.HashSet[string]
foreach ($x in @('--zz-canon', '--zz-short', '--zz-undoc', '--zz-named')) { [void]$pHelp.Add($x) }
$pNone = New-Object System.Collections.Generic.HashSet[string]
$pg = Get-VerbGap -VerbFlags $pVerbs -Blocks @{ 'zz-verb' = $pBlock } -HelpSet $pHelp -GlobalFlags $pNone -Exempt @() -AliasOf $pAlias
Check 'CONTROL an undocumented NON-alias flag is still counted after the fold' `
  ($pg.Missing -eq 1 -and $pg.Rows.Count -eq 1 -and $pg.Rows[0].flags -eq '--zz-undoc') `
  ("missing=$($pg.Missing) flags=" + (@($pg.Rows | ForEach-Object flags) -join ';'))
Check 'PLANT an alias of a flag the line names is one option, not a second cell' `
  ($pg.Total -eq 3) "consumes=$($pg.Total) (canon+short fold to 1, + undoc + named)"
$pg2 = Get-VerbGap -VerbFlags $pVerbs -Blocks @{ 'zz-verb' = $pBlock } -HelpSet $pHelp -GlobalFlags $pNone -Exempt @() -AliasOf @{}
Check 'CONTROL without the alias table the same alias IS a missing cell (the fold is what removes it)' `
  ($pg2.Missing -eq 2) "missing=$($pg2.Missing)"
$pTxt = "  drag-lint zz-verb [--zz-short <f>]`r`nFlag aliases:`r`n  --zz-canon          also: --zz-short`r`n"
$pLeak = @(($pTxt -split "`r?`n") | Where-Object { $_ -notmatch '^\s{2}-\S*\s+also:' -and $_ -match (Get-AliasTokenRx '--zz-short') })
Check 'CONTROL an alias on a verb line IS reported by the leak scan' ($pLeak.Count -eq 1) "leaks=$($pLeak.Count)"
Check 'CONTROL the alias token regex does not match a longer flag' `
  (-not ('--include-mode' -match (Get-AliasTokenRx '--in')) -and ('[--in <f>]' -match (Get-AliasTokenRx '--in'))) ''

# ---------------------------------------------------------------------------
# PLANTED REFUSAL CASES -- a pre-dispatch read that only REFUSES must not make a
# flag cross-verb (--rule, comma-list refusal), and a real consumer must still.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- planted cases (refusal-only reads)' -ForegroundColor Cyan
$pRefuse = @"
begin
  if Args.RuleConflict <> '' then
  begin
    Writeln(ErrOutput, Args.RuleConflict);
    Exit(2);
  end;
  if Args.Rule.Contains('') then
  begin
    Writeln(ErrOutput, Format('', [Args.Rule]));
    Exit(2);
  end;
end;
"@ -replace "`r?`n", "`r`n"
$pConsume = @"
begin
  if Args.Rule <> '' then
  begin
    UseTheRule(Args.Rule);
  end;
end;
"@ -replace "`r?`n", "`r`n"
$pNoExit = @"
begin
  if Args.Rule.Contains('') then
  begin
    Writeln(ErrOutput, Args.Rule);
  end;
end;
"@ -replace "`r?`n", "`r`n"
$rd = { param($t) @([regex]::Matches((Remove-RefusalOnlyReads -Span $t -Field 'Rule'), '\bArgs\.Rule\b')).Count }
Check 'CONTROL the helper sees a plain Args.Rule read (else the absences below are vacuous)' `
  (@([regex]::Matches($pRefuse, '\bArgs\.Rule\b')).Count -eq 2) ''
Check 'PLANT an `if Args.Rule... then begin .. Exit(2); end` block is refusal-only: no Args.Rule left' `
  ((& $rd $pRefuse) -eq 0) "left=$(& $rd $pRefuse)"
Check 'CONTROL an UNDOCUMENTED consumer of Args.Rule (no Exit(2)) still counts as a read' `
  ((& $rd $pConsume) -eq 2) "left=$(& $rd $pConsume)"
Check 'CONTROL a block that reads Args.Rule but does not refuse (no Exit(2)) still counts' `
  ((& $rd $pNoExit) -eq 2) "left=$(& $rd $pNoExit)"
Check 'PLANT the helper leaves RuleConflict alone (it has its own refusal-only entry)' `
  (@([regex]::Matches((Remove-RefusalOnlyReads -Span $pRefuse -Field 'Rule'), '\bArgs\.RuleConflict\b')).Count -eq 2) ''

# ---------------------------------------------------------------------------
# THE MAP, against the real source
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- the map' -ForegroundColor Cyan
$map = Get-CliVerbFlagMap -CliPath $Cli

Check 'map: verbs derived from the dispatch chain' ($map.VerbFlags.Count -gt 50) `
  "($($map.VerbFlags.Count) verb(s)) -- a low count means the dispatch scan broke, not that the CLI shrank"
Check 'map: flags bound to a TArgs field' ($map.FlagFields.Count -gt 100) `
  "($($map.FlagFields.Count) flag(s))"
Check 'map: routines with a body' ($map.Routines.Count -gt 100) `
  "($($map.Routines.Count) routine(s))"

# --- structural assertions: one per defect measured while building this ------
$fb = @($map.VerbFlags['fb-snapshot'])
Check 'no qualified call is read as a call to the dispatcher Run' ($fb.Count -lt 20) `
  ("fb-snapshot consumes $($fb.Count) flag(s) -- TFbSnapshot.Run(AArgs.X) is being read as Run(Args), so its closure is the whole CLI")

foreach ($v in @('index', 'lsp', 'serve', 'resolve-dbs')) {
  Check "multi-line dispatch arm resolves: $v" (@($map.VerbFlags[$v]).Count -gt 0) `
    'an entry-routine-only dispatch model scores this arm as unresolved and maps none of its flags'
}

Check 'a branch GUARD read is not a field binding' `
  ((@($map.FlagFields['--in-place']) -join ',') -eq 'GhostInPlace') `
  ("--in-place binds " + (@($map.FlagFields['--in-place']) -join ',') + " -- Result.Command is TESTED by that branch, not assigned")

Check 'flags that bind no TArgs field are named, not dropped' `
  ($map.NoField.Count -gt 0 -and $map.NoField.Count -lt 10) `
  ("no-field flags: " + ($map.NoField -join ' '))
foreach ($f in $map.NoField)     { Write-Host ("      [NOTE] binds no TArgs field: {0}" -f $f) -ForegroundColor DarkGray }
foreach ($o in $map.Orphan)      { Write-Host ("      [NOTE] positional branch (attributed to no flag): {0}" -f $o) -ForegroundColor DarkGray }
foreach ($u in $map.Unevaluated) { Write-Host ("      [NOTE] conditional kept unevaluated (both arms): {0}" -f $u) -ForegroundColor DarkGray }

# ---------------------------------------------------------------------------
# THE GAP -- printed in full, ratcheted, never closed silently
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- per-verb gap vs --help' -ForegroundColor Cyan

$FlagRx = '--[A-Za-z][A-Za-z0-9-]*'
$helpText = (& $Exe --help 2>&1 | Out-String)

# A verb's BLOCK is its `  drag-lint <verb> ...` line plus the continuation
# lines under it, up to the next verb line or the next section header. The
# block, not the line, because several verbs wrap their flag list.
$blocks = @{}
$cur = $null
foreach ($l in ($helpText -split "`r?`n")) {
  $vm = [regex]::Match($l, '^\s{2}drag-lint\s+([a-z][a-z0-9-]*)')
  if ($vm.Success) {
    $cur = $vm.Groups[1].Value
    if (-not $blocks.ContainsKey($cur)) { $blocks[$cur] = New-Object System.Collections.Generic.HashSet[string] }
  } elseif ($l -match '^[A-Z][A-Za-z /]+:\s*$') { $cur = $null }
  if ($cur) { foreach ($m in [regex]::Matches($l, $FlagRx)) { [void]$blocks[$cur].Add($m.Value) } }
}
Check 'help: verb blocks parsed' ($blocks.Count -gt 50) "($($blocks.Count) block(s))"

$helpSet = New-Object System.Collections.Generic.HashSet[string]
foreach ($m in [regex]::Matches($helpText, $FlagRx)) { [void]$helpSet.Add($m.Value) }
Check 'help: flag set parsed' ($helpSet.Count -gt 100) "($($helpSet.Count) flag(s))"

# Flags bound to a field Run reads BEFORE it dispatches are cross-verb plumbing
# (--db, --platform, --project, the positional path). They belong on no single
# verb line, and the banner documents them in its own Databases block.
# --- the alias table, proved against the parser and against --help ----------
$aliasPath = Join-Path $Repo 'features\flag-aliases.json'
Check 'alias table present' (Test-Path -LiteralPath $aliasPath) $aliasPath
$AliasOf = @{}
$tableGroups = @()
if (Test-Path -LiteralPath $aliasPath) {
  foreach ($row in @((Get-Content -LiteralPath $aliasPath -Raw | ConvertFrom-Json).aliases)) {
    foreach ($a in @($row.aliases)) { $AliasOf[[string]$a] = [string]$row.canonical }
    $tableGroups += ,(@(@($row.canonical) + @($row.aliases) | Sort-Object) -join ' ')
  }
}
$tableGroups = @($tableGroups | Sort-Object -Unique)
$parserGroups = Get-ParserAliasGroups -CliText ([IO.File]::ReadAllText($Cli))
Check 'alias groups read from the parser (else the two-way check below is vacuous)' ($parserGroups.Count -ge 4) `
  ("($($parserGroups.Count) group(s)): " + ($parserGroups -join ' | '))
$grpDiff = @(Compare-Object -ReferenceObject $parserGroups -DifferenceObject $tableGroups |
             ForEach-Object { '{0}[{1}]' -f $(if ($_.SideIndicator -eq '=>') { 'table-only' } else { 'parser-only' }), $_.InputObject })
Check 'alias table == the parser''s alias groups (two-way)' ($grpDiff.Count -eq 0) `
  ("difference: " + ($grpDiff -join ' ') + " -- every (A = 'x') or (A = 'y') pair is a row of features\flag-aliases.json, and nothing else is")

# Policy: a verb line, a note, COMMON QUESTIONS -- every --help line except the
# alias rows themselves -- names the canonical spelling only.
$helpLines = @($helpText -split "`r?`n")
$aliasRowRx = '^\s{2}(-\S+)\s+also:\s+(.*)$'
$leaks = @()
foreach ($l in $helpLines) {
  if ($l -match $aliasRowRx) { continue }
  foreach ($a in $AliasOf.Keys) { if ($l -match (Get-AliasTokenRx $a)) { $leaks += ("{0} in: {1}" -f $a, $l.Trim()) } }
}
Check 'no --help line outside the alias section names an alias (canonical only)' ($leaks.Count -eq 0) `
  ("$($leaks.Count) leak(s)")
foreach ($x in $leaks) { Write-Host ("      [LEAK] {0}" -f $x) -ForegroundColor Red }
$listed = @{}
foreach ($l in $helpLines) {
  $am = [regex]::Match($l, $aliasRowRx)
  if ($am.Success) { foreach ($t in ($am.Groups[2].Value -split '[,\s]+' | Where-Object { $_ })) { $listed[$t] = $am.Groups[1].Value } }
}
$unlisted = @($AliasOf.Keys | Where-Object { $listed[$_] -ne $AliasOf[$_] } | Sort-Object)
Check 'every alias is listed once in the --help "Flag aliases:" section, under its canonical flag' ($unlisted.Count -eq 0) `
  ("not listed (or under the wrong flag): " + ($unlisted -join ' '))

$globalFlags = New-Object System.Collections.Generic.HashSet[string]
foreach ($f in $map.Global) {
  if ($map.FieldFlags.ContainsKey($f)) { foreach ($x in $map.FieldFlags[$f]) { [void]$globalFlags.Add((Get-CanonicalFlag $x $AliasOf)) } }
}
Write-Host ("      [NOTE] cross-verb (pre-dispatch) flags, excluded: " + (($globalFlags | Sort-Object) -join ' ')) -ForegroundColor DarkGray

# THE CROSS-VERB SET IS PINNED. Every flag in it is exempted from every verb's
# gap count, so a flag that JOINS it silently -- ResolveConsumerDbs reading one
# more TArgs field, say -- would lower the gap without a line of --help changing,
# and a flag that LEAVES it (1.20.4: Run stopped calling the resolver before
# dispatch) inflates the gap for a reason no banner edit can fix. Either is a
# change to the classification, so it must be made here, deliberately.
# 2026-10-26 (FLAG lane): '--file' left the pinned list because it is an ALIAS of
# --in (features\flag-aliases.json) and the set is now folded to canonical
# spellings -- the same option, still exempt, counted once.
$ExpectedGlobalFlags = @('--db', '--dir', '--in', '--platform', '--project')
$globalDiff = @(Compare-Object -ReferenceObject $ExpectedGlobalFlags -DifferenceObject @($globalFlags | Sort-Object) |
                ForEach-Object { '{0}{1}' -f $(if ($_.SideIndicator -eq '=>') { '+' } else { '-' }), $_.InputObject })
Check 'cross-verb flag set is exactly the pinned set (--db --dir --in --platform --project)' ($globalDiff.Count -eq 0) `
  ("difference: " + ($globalDiff -join ' ') + " -- update `$ExpectedGlobalFlags only as a deliberate reclassification")

# check 9 of run_docs_sync_guard.ps1 owns "accepted but in --help nowhere" (F1)
# and its exemption table. This axis asks only WHERE a documented flag is
# documented, so a flag the banner does not carry at all is not counted twice.
$exempt = @('--expr','--from-block','--selftest-fts5','--selftest-schema','--use-ignore','--dir','--target')

$gap = Get-VerbGap -VerbFlags $map.VerbFlags -Blocks $blocks -HelpSet $helpSet -GlobalFlags $globalFlags -Exempt $exempt -AliasOf $AliasOf
$rows = $gap.Rows; $totalCells = $gap.Total; $missCells = $gap.Missing; $noBlock = $gap.NoBlock

Write-Host ''
Write-Host ("  (verb, flag) cells the code consumes : {0}" -f $totalCells)
Write-Host ("  cells missing from the verb's block  : {0}   (baseline {1})" -f $missCells, $BaselineCells)
Write-Host ("  verbs affected                       : {0}   (baseline {1})" -f $rows.Count, $BaselineVerbs)
Write-Host ("  verbs with no --help block at all    : {0} -- {1}" -f $noBlock.Count, ($noBlock -join ' '))
Write-Host ''
$rows | Sort-Object missing -Descending | Format-Table -AutoSize -Wrap | Out-String -Width 200 | Write-Host

if ($Report) { exit 0 }

Check 'gap has not grown past the recorded baseline (cells)' ($missCells -le $BaselineCells) `
  ("$missCells > $BaselineCells -- a flag was added to a verb without reaching that verb's --help block. Document it, or lower nothing: the baseline only ever goes DOWN")
Check 'gap has not grown past the recorded baseline (verbs)' ($rows.Count -le $BaselineVerbs) `
  ("$($rows.Count) > $BaselineVerbs")

# A baseline that has silently become generous is a baseline nobody trusts.
if ($missCells -lt $BaselineCells) {
  Write-Host ("      [NOTE] the gap has SHRUNK to $missCells -- lower `$BaselineCells to $missCells so it cannot drift back") -ForegroundColor Yellow
}

Write-Host ''
if ($script:Failed) { Write-Host 'FLAG-VERB MAP: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'FLAG-VERB MAP: PASS' -ForegroundColor Green
exit 0
