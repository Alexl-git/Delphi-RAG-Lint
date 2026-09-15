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

# RECORDED BASELINE -- see the header. Measured 2026-09-15 at 44a2b0a.
$BaselineCells = 124
$BaselineVerbs = 33

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
$globalFlags = New-Object System.Collections.Generic.HashSet[string]
foreach ($f in $map.Global) {
  if ($map.FieldFlags.ContainsKey($f)) { foreach ($x in $map.FieldFlags[$f]) { [void]$globalFlags.Add($x) } }
}
Write-Host ("      [NOTE] cross-verb (pre-dispatch) flags, excluded: " + (($globalFlags | Sort-Object) -join ' ')) -ForegroundColor DarkGray

# check 9 of run_docs_sync_guard.ps1 owns "accepted but in --help nowhere" (F1)
# and its exemption table. This axis asks only WHERE a documented flag is
# documented, so a flag the banner does not carry at all is not counted twice.
$exempt = @('--expr','--from-block','--selftest-fts5','--selftest-schema','--use-ignore','--dir','--target')

$rows = @(); $totalCells = 0; $missCells = 0; $noBlock = @()
foreach ($verb in $map.VerbFlags.Keys) {
  if (-not $blocks.ContainsKey($verb)) { $noBlock += $verb; continue }
  $want = @($map.VerbFlags[$verb] | Where-Object {
              $helpSet.Contains($_) -and -not $globalFlags.Contains($_) -and ($exempt -notcontains $_) })
  $miss = @($want | Where-Object { -not $blocks[$verb].Contains($_) })
  $totalCells += $want.Count
  $missCells  += $miss.Count
  if ($miss.Count -gt 0) { $rows += [pscustomobject]@{ verb = $verb; consumes = $want.Count; missing = $miss.Count; flags = ($miss -join ' ') } }
}

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
