<#
  run_index_section_summary_reconciles.ps1 -- the per-section summary line must
  report FLOWS that reconcile against the walk, under labels that do not lie.

  WHY THIS EXISTS. The line used to read:

      === Library [Win64] -> ...library-Win64.sqlite : files=6993 symbols=... \
          refs=... parsed=7003 skipped=916 [14918.1s, 28 files/min]

  and every number in it was correct. It still cost a session, because it
  printed one STOCK (`files=`, rows in the database) beside two FLOWS
  (`parsed=`, `skipped=`) under labels that read as one population:

    * `parsed=7003` EXCEEDED `files=6993`, which reads as arithmetic gone
      wrong. It is not. ParsedFiles is incremented BEFORE the parse, by
      contract (IIndexer: deliberately an upper bound, so the caller can gate
      the four whole-DB resolve passes -- over-counting wastes a pass,
      under-counting serves stale ancestry and call edges). So it counts files
      whose parse RAISED and never got a row. The gap of 10 was 10 real
      EIntOverflow skips: silent data loss that had been present since 1.11.0
      and that nobody read as a defect, because the line looked like bad maths
      rather than missing units.
    * `skipped=916` names a population DISJOINT from the log's own `SKIP`
      lines. It counts up-to-date skips only -- never the size guard, never a
      parse failure. The same English word meant two different things ten lines
      apart.
    * the rate divided the WHOLE CORPUS by this run's wall clock. An
      incremental run that re-parsed three files claimed hundreds of files/min,
      and `--resolve-only` quoted a rate for a walk that never happened.

  So this runner does not test arithmetic. It tests that the line still
  RECONCILES against the walk after the relabelling, and that each field keeps
  counting what its name now claims.

  THE INVARIANT

      INV:  attempted + up-to-date + oversize == walked

  `walked` is Length(VisitedFiles): unique paths ADMITTED to the walk, recorded
  in Indexer.IndexFile BEFORE every skip -- deliberately, because out-of-scope
  eviction deletes indexed files that are NOT in that list, so a file the walk
  declined to re-parse must still be on the recorded side or refreshing an
  index would delete the very files it skipped.

  TWO PRECONDITIONS, both enforced below rather than assumed:

    (1) NO NESTED ROOTS. The visited list de-dups on the lowercased path, so a
        file reached twice through overlapping roots is walked once but runs
        the skip logic twice and lands in `up-to-date` the second time. INV
        then fails by exactly the number of double visits (~900 per platform on
        the real library manifest -- see the nested-roots finding). Both
        fixtures below use ONE non-nested root.

    (2) NO EXCEPTION SKIPS. There are TWO SKIP shapes in the indexer, not one,
        and the written plan for this work accounted for only the first:

          Indexer.pas:871   SKIP <path>: <N> KB exceeds parse limit (<M> KB)
          Indexer.pas:1290  SKIP <path>: <ExceptionClass>: <message>

        The oversize skip Exits before BOTH counters, so it is in `walked` and
        in neither -- which is exactly why INV needs the `+ oversize` term. But
        an exception escaping IndexFile can be raised on EITHER side of
        `Inc(FParsedFiles)`: a parse failure (EIntOverflow was one) is counted
        in `attempted`, while a pre-parse failure -- TFile.ReadAllBytes on a
        file that is locked or has vanished mid-walk -- is not, and lands in
        `walked` alone. From the log the two are indistinguishable. So in the
        wild the honest relation is `attempted + up-to-date + oversize <=
        walked`, and equality holds only when no exception skip occurred. This
        runner asserts that count is ZERO and only then asserts equality.

  THE FAILURE INJECTOR IS THE SIZE GUARD, and it has to be something.

  The plan this runner implements specified an FX-overflow fixture -- a unit
  containing `TOvf = (ovA = $7FFFFFFF)` -- to force `attempted > files`. That
  injector is GONE: the enum-ordinal overflow it exploited was fixed under
  extractor 1.14.0-alpha, so the unit now indexes normally. Asserting "exactly
  one EIntOverflow SKIP" would go RED against a correct engine, and asserting
  nothing in its place would leave INV trivially true (with no skips of any
  kind, attempted + up-to-date == walked holds for arithmetic reasons alone and
  proves nothing about what the counters count).

  The size guard replaces it. It is not hypothetical: `MS2.SQL: 2090 KB exceeds
  parse limit` was the ONLY skip in the 2026-09-09 full re-parse. FX-oversize
  below therefore carries the whole weight of this runner -- if it is ever
  weakened, INV becomes a tautology.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
  -Exe points at the engine under test; aim it at a pre-change build to RED-check.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }

$exePath = (Resolve-Path $Exe).Path
Write-Host "engine under test: $exePath" -ForegroundColor DarkGray

# Unique scratch per run. Remove-Item is permission-blocked in some sessions and
# takes the WHOLE command with it, so this runner never tries to wipe anything.
$scratch = Join-Path C:\TEMP ('draglint_sectionsummary_{0}' -f [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $scratch | Out-Null

function Write-Ascii($p,$t) {
  [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"),
    (New-Object System.Text.UTF8Encoding($false)))
}

# SEPARATE HANDLES, DELIBERATELY -- and this is the opposite of what
# run_index_stage_markers.ps1 does, on purpose.
#
# That runner merges the two streams into one file because it asserts the ORDER
# of lines against each other, and only a single handle preserves write order.
# This runner asserts no ordering at all: it COUNTS `SKIP` lines and parses
# fields out of the summary. Merging buys it nothing and costs it correctness,
# because the two streams interleave MID-LINE.
#
# Measured, not theorised. The first version of this runner merged them and the
# battery caught it -- from the repo root as CWD, `index --all` produced:
#
#   walking 3 file(s) under C:\TEMP\dbg-oversize-3667  SKIP C:\TEMP\...\uB.pas: 1 KB exceeds parse limit (1 KB)
#
# The `walking N file(s) under <dir>` line goes to STDERR (Indexer.pas:1327);
# the SKIP goes to STDOUT. The stderr write was cut in half mid-path -- note the
# truncated `3667` -- and the SKIP was spliced into the middle of it. A
# line-anchored `^\s*SKIP` then does not match, the oversize count reads 0, and
# INV fails while the engine is behaving perfectly. It reproduced 2/2 from the
# repo root and 0/2 from C:\TEMP, so it presents as a mysterious CWD dependency
# rather than as the stream race it is.
#
# Keeping the streams apart removes the whole class of problem: stdout alone,
# from a single-threaded run, is never shredded. Stderr is captured too, so a
# failure can still be diagnosed.
function RunCapture([string]$ArgLine) {
  $id  = [guid]::NewGuid().ToString('N').Substring(0,8)
  $so  = Join-Path $scratch ("run-$id.out.log")
  $se  = Join-Path $scratch ("run-$id.err.log")
  cmd /c "`"$exePath`" $ArgLine > `"$so`" 2> `"$se`"" | Out-Null
  $code = $LASTEXITCODE
  $out  = if (Test-Path -LiteralPath $so) { (Get-Content -LiteralPath $so -Raw) } else { '' }
  $err  = if (Test-Path -LiteralPath $se) { (Get-Content -LiteralPath $se -Raw) } else { '' }
  if ($null -eq $out) { $out = '' }
  if ($null -eq $err) { $err = '' }
  return @{ Out = $out; Err = $err; Code = $code }
}

# ---------------------------------------------------------------------------
# ONE anchored regex, named groups, no defaults.
#
# A non-match returns $null and every dependent Check below tests for it
# explicitly. There is no `-or $true` and no `else { 0 }` anywhere in this file:
# a summary line that changed shape must FAIL the assertions, not silently
# satisfy them against a default. That is the difference between this runner and
# a runner incapable of failing.
#
# Anchored on the full field sequence in order, so a field that is dropped,
# reordered or renamed breaks the match rather than being skipped over by a
# permissive gap pattern.
# ---------------------------------------------------------------------------
$SUMMARY_RX = '===\s*(?<name>\S+)[^\r\n]*?\sfiles=(?<files>\d+)\s+symbols=(?<symbols>\d+)\s+refs=(?<refs>\d+)\s+walked=(?<walked>\d+)\s+attempted=(?<attempted>\d+)\s+up-to-date=(?<utd>\d+)\s+\[(?<secs>\d+(?:\.\d+)?)s,\s*(?<rate>[^\]]+)\]\s*==='

function Parse-Summary([string]$Text) {
  $m = [regex]::Match($Text, $SUMMARY_RX)
  if (-not $m.Success) { return $null }
  return @{
    name      = $m.Groups['name'].Value
    files     = [int]$m.Groups['files'].Value
    symbols   = [int]$m.Groups['symbols'].Value
    refs      = [int]$m.Groups['refs'].Value
    walked    = [int]$m.Groups['walked'].Value
    attempted = [int]$m.Groups['attempted'].Value
    utd       = [int]$m.Groups['utd'].Value
    secs      = [double]$m.Groups['secs'].Value
    rate      = $m.Groups['rate'].Value.Trim()
    line      = $m.Value
  }
}

$MULTILINE = [System.Text.RegularExpressions.RegexOptions]::Multiline
function Count-OversizeSkips([string]$Text) {
  return [regex]::Matches($Text, '^\s*SKIP\s+.+?:\s+\d+\s+KB exceeds parse limit', $MULTILINE).Count
}
function Count-AllSkips([string]$Text) {
  return [regex]::Matches($Text, '^\s*SKIP\s+', $MULTILINE).Count
}

# Assert INV for one run, having first proved the two preconditions hold.
function Check-Inv([string]$Tag, $s, [string]$Text) {
  $over = Count-OversizeSkips $Text
  $exc  = (Count-AllSkips $Text) - $over
  Check "$Tag precondition: no exception SKIP lines" ($exc -eq 0) `
    "exception skips=$exc -- a pre-parse failure is in walked but in neither counter, so INV would fail for a reason that is not a counter defect"
  Check "$Tag INV: attempted + up-to-date + oversize == walked" `
    (($null -ne $s) -and ($exc -eq 0) -and (($s.attempted + $s.utd + $over) -eq $s.walked)) `
    $(if ($null -eq $s) { 'summary line did not match the anchored regex' } else { "attempted=$($s.attempted) up-to-date=$($s.utd) oversize=$over walked=$($s.walked)" })
  return $over
}

function New-Config([string]$Path,[string]$OutDir,[string]$Src,[string]$Section,[string]$Db,[int]$MaxKB) {
  $kbLine = if ($MaxKB -gt 0) { ', "maxParseFileKB": ' + $MaxKB } else { '' }
  @"
{
  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 4096, "enginePath": "auto", "maxJobs": 1$kbLine },
  "indexes": {
    "outDir": "$($OutDir -replace '\\','\\')",
    "sections": [
      { "name": "$Section", "db": "$Db", "include": ["$($Src -replace '\\','\\')"] }
    ]
  }
}
"@ | Set-Content $Path -Encoding ascii
}

function Unit([string]$Name,[string]$Pad) {
  return @"
unit $Name;

interface
$Pad
type
  T$Name = class
  public
    procedure Work;
  end;

implementation

procedure T$Name.Work;
begin
end;

end.
"@
}

# ===========================================================================
# FX-clean -- three small units, ONE non-nested root, default size guard.
# ===========================================================================
Write-Host "`n--- FX-clean: three units, no skips of any kind ---" -ForegroundColor Cyan

$srcClean = Join-Path $scratch 'src-clean'
New-Item -ItemType Directory -Path $srcClean | Out-Null
foreach ($u in @('uA','uB','uC')) { Write-Ascii (Join-Path $srcClean "$u.pas") (Unit $u '') }

$outClean = Join-Path $scratch 'out-clean'
New-Item -ItemType Directory -Path $outClean | Out-Null
$cfgClean = Join-Path $scratch 'cfg-clean.json'
New-Config $cfgClean $outClean $srcClean 'CounterProbe' 'counterprobe.sqlite' 0

# --- R1: fresh --rebuild ---------------------------------------------------
$r1 = RunCapture ("index --all --config `"$cfgClean`" --jobs 1 --rebuild")
Check 'R1 exit 0' ($r1.Code -eq 0) "exit=$($r1.Code)"
$s1 = Parse-Summary $r1.Out
Check 'R1 summary matches the anchored regex (walked=/attempted=/up-to-date= all present, in order)' `
  ($null -ne $s1) "no match -- observed tail: $(($r1.Out -split "`r?`n" | Where-Object { $_ -match '^===' }) -join ' | ')"
Check 'R1 files=3'      (($null -ne $s1) -and ($s1.files     -eq 3)) "files=$(if($s1){$s1.files})"
Check 'R1 walked=3'     (($null -ne $s1) -and ($s1.walked    -eq 3)) "walked=$(if($s1){$s1.walked})"
Check 'R1 attempted=3'  (($null -ne $s1) -and ($s1.attempted -eq 3)) "attempted=$(if($s1){$s1.attempted})"
Check 'R1 up-to-date=0' (($null -ne $s1) -and ($s1.utd       -eq 0)) "up-to-date=$(if($s1){$s1.utd})"
Check-Inv 'R1' $s1 $r1.Out | Out-Null
# files is the STOCK, attempted the FLOW. On a fresh rebuild with no skip of any
# kind they must agree -- and stating it as a RELATIONSHIP rather than a literal
# is what lets this survive: when a future parse failure reappears, files falls
# below attempted by exactly the failure count and this check still describes
# the truth.
Check 'R1 files == attempted (no skips, so stock and flow agree)' `
  (($null -ne $s1) -and ($s1.files -eq $s1.attempted)) `
  "files=$(if($s1){$s1.files}) attempted=$(if($s1){$s1.attempted})"
Check 'R1 rate is reported as attempted/min' `
  (($null -ne $s1) -and ($s1.rate -match '^\d+ attempted/min$')) "rate='$(if($s1){$s1.rate})'"

# --- R2: unchanged rerun. THE RATE CONTROL. --------------------------------
# This is the run the old numerator got wrong: nothing is parsed, yet the line
# used to quote the whole corpus over the elapsed time. 'n/a' is the assertion.
$r2 = RunCapture ("index --all --config `"$cfgClean`" --jobs 1")
Check 'R2 exit 0' ($r2.Code -eq 0) "exit=$($r2.Code)"
$s2 = Parse-Summary $r2.Out
Check 'R2 summary matches' ($null -ne $s2) 'no match'
Check 'R2 files=3'       (($null -ne $s2) -and ($s2.files     -eq 3)) "files=$(if($s2){$s2.files})"
Check 'R2 walked=3'      (($null -ne $s2) -and ($s2.walked    -eq 3)) "walked=$(if($s2){$s2.walked})"
Check 'R2 attempted=0'   (($null -ne $s2) -and ($s2.attempted -eq 0)) "attempted=$(if($s2){$s2.attempted})"
Check 'R2 up-to-date=3'  (($null -ne $s2) -and ($s2.utd       -eq 3)) "up-to-date=$(if($s2){$s2.utd})"
Check-Inv 'R2' $s2 $r2.Out | Out-Null
Check 'R2 rate is n/a when nothing was attempted (NOT a corpus-over-elapsed number)' `
  (($null -ne $s2) -and ($s2.rate -eq 'n/a')) "rate='$(if($s2){$s2.rate})'"

# --- R3: touch one unit ----------------------------------------------------
Start-Sleep -Milliseconds 1100   # mtime granularity: the skip test keys on mtime+sha
Write-Ascii (Join-Path $srcClean 'uB.pas') (Unit 'uB' "`r`n{ touched }")
$r3 = RunCapture ("index --all --config `"$cfgClean`" --jobs 1")
Check 'R3 exit 0' ($r3.Code -eq 0) "exit=$($r3.Code)"
$s3 = Parse-Summary $r3.Out
Check 'R3 summary matches' ($null -ne $s3) 'no match'
Check 'R3 walked=3'     (($null -ne $s3) -and ($s3.walked    -eq 3)) "walked=$(if($s3){$s3.walked})"
Check 'R3 attempted=1'  (($null -ne $s3) -and ($s3.attempted -eq 1)) "attempted=$(if($s3){$s3.attempted}) -- only the touched unit"
Check 'R3 up-to-date=2' (($null -ne $s3) -and ($s3.utd       -eq 2)) "up-to-date=$(if($s3){$s3.utd})"
Check 'R3 files=3 (stock unchanged by an incremental re-parse)' `
  (($null -ne $s3) -and ($s3.files -eq 3)) "files=$(if($s3){$s3.files})"
Check-Inv 'R3' $s3 $r3.Out | Out-Null

# ===========================================================================
# FX-oversize -- THE FAILURE INJECTOR, and the only reason INV is not a
# tautology. uB is padded past a 1 KB limit, so it is ADMITTED to the walk
# (recorded in VisitedFiles) and then skipped before either counter.
# ===========================================================================
Write-Host "`n--- FX-oversize: one unit past the size guard (the injector) ---" -ForegroundColor Cyan

$srcOver = Join-Path $scratch 'src-over'
New-Item -ItemType Directory -Path $srcOver | Out-Null
Write-Ascii (Join-Path $srcOver 'uA.pas') (Unit 'uA' '')
Write-Ascii (Join-Path $srcOver 'uC.pas') (Unit 'uC' '')
# > 1024 bytes, so the 1 KB guard rejects it. The padding is a comment, so the
# file is still valid Pascal -- the point is that it is skipped for SIZE, not
# because it is malformed.
$pad = "`r`n{ " + ('x' * 1600) + " }"
Write-Ascii (Join-Path $srcOver 'uB.pas') (Unit 'uB' $pad)

$outOver = Join-Path $scratch 'out-over'
New-Item -ItemType Directory -Path $outOver | Out-Null
$cfgOver = Join-Path $scratch 'cfg-over.json'
New-Config $cfgOver $outOver $srcOver 'OversizeProbe' 'oversizeprobe.sqlite' 1

# --- R4: fresh --rebuild with the guard at 1 KB ----------------------------
$r4 = RunCapture ("index --all --config `"$cfgOver`" --jobs 1 --rebuild")
Check 'R4 exit 0' ($r4.Code -eq 0) "exit=$($r4.Code)"
$s4 = Parse-Summary $r4.Out
Check 'R4 summary matches' ($null -ne $s4) 'no match'
$over4 = Count-OversizeSkips $r4.Out
Check 'R4 the injector fired: exactly ONE oversize SKIP' ($over4 -eq 1) `
  "oversize skips=$over4 -- if this is 0 the guard did not engage and every check below is vacuous"
Check 'R4 walked=3 (the oversize file IS admitted to the walk)' `
  (($null -ne $s4) -and ($s4.walked -eq 3)) `
  "walked=$(if($s4){$s4.walked}) -- it must be recorded, or out-of-scope eviction would delete the file it declined to parse"
Check 'R4 attempted=2 (the oversize file is NOT attempted)' `
  (($null -ne $s4) -and ($s4.attempted -eq 2)) "attempted=$(if($s4){$s4.attempted})"
Check 'R4 up-to-date=0' (($null -ne $s4) -and ($s4.utd -eq 0)) "up-to-date=$(if($s4){$s4.utd})"
Check 'R4 files=2 (no row for a file that was never parsed)' `
  (($null -ne $s4) -and ($s4.files -eq 2)) "files=$(if($s4){$s4.files})"
Check-Inv 'R4' $s4 $r4.Out | Out-Null

# NEGATIVE CONTROL. Without the oversize term INV must NOT hold here. An
# implementation that quietly counted the size-skipped file in `attempted` (or
# in `up-to-date`) would satisfy INV above by accident; this is the check that
# catches it, and it is the single most load-bearing assertion in this file.
Check 'R4 N1 NEGATIVE CONTROL: attempted + up-to-date != walked without the oversize term' `
  (($null -ne $s4) -and (($s4.attempted + $s4.utd) -ne $s4.walked)) `
  "attempted+up-to-date=$(if($s4){$s4.attempted + $s4.utd}) walked=$(if($s4){$s4.walked}) -- equal means the skipped file was counted in a flow it never entered, and INV above passed for the wrong reason"

# --- R5: rerun. The oversize file must be re-skipped, never 'up to date'. ---
$r5 = RunCapture ("index --all --config `"$cfgOver`" --jobs 1")
Check 'R5 exit 0' ($r5.Code -eq 0) "exit=$($r5.Code)"
$s5 = Parse-Summary $r5.Out
Check 'R5 summary matches' ($null -ne $s5) 'no match'
$over5 = Count-OversizeSkips $r5.Out
Check 'R5 the oversize file is skipped again' ($over5 -eq 1) "oversize skips=$over5"
Check 'R5 walked=3'    (($null -ne $s5) -and ($s5.walked    -eq 3)) "walked=$(if($s5){$s5.walked})"
Check 'R5 attempted=0' (($null -ne $s5) -and ($s5.attempted -eq 0)) "attempted=$(if($s5){$s5.attempted})"
Check 'R5 up-to-date=2 (the oversize file never becomes up-to-date -- it has no row)' `
  (($null -ne $s5) -and ($s5.utd -eq 2)) `
  "up-to-date=$(if($s5){$s5.utd}) -- 3 would mean the size-skipped file was counted as current"
Check-Inv 'R5' $s5 $r5.Out | Out-Null
Check 'R5 rate is n/a' (($null -ne $s5) -and ($s5.rate -eq 'n/a')) "rate='$(if($s5){$s5.rate})'"

# ===========================================================================
# C1 -- the fields other tooling keys on must survive the relabelling.
# ===========================================================================
Write-Host "`n--- C1: pre-existing anchors still match ---" -ForegroundColor Cyan
# run_index_stage_markers.ps1 anchors on the section name + files=, and its own
# header records that a tighter `[^=]*` pattern broke the last time fields were
# added here. Assert its exact shapes so this change cannot repeat that.
Check 'C1 files= is still immediately followed by symbols= (stage-markers B anchor)' `
  ([regex]::IsMatch($r1.Out,'===\s*CounterProbe[^=]*files=\d+\s+symbols=\d+')) `
  'run_index_stage_markers.ps1:200 keys on exactly this adjacency'
Check 'C1 the loose summary anchor still matches (stage-markers B summary index)' `
  ([regex]::IsMatch($r1.Out,'===\s*CounterProbe\b[^\r\n]*files=\d+[^\r\n]*===')) `
  'run_index_stage_markers.ps1:219'
# The DoIndex "Done." line is a DIFFERENT line and was deliberately left alone:
# run_index_fingerprint_entry_points.ps1:101 and run_index_resume_per_file.ps1:149
# both parse `skipped N up-to-date` from it. Renaming the section line must not
# have touched it.
# TWICE, deliberately. CLI.pas:4699 gates the clause on `SkippedUpToDate > 0`,
# so a fresh database never prints it and asserting it on a first run fails
# against a perfectly correct engine -- which is what the first draft of this
# check did during its own red check. The second run is the one where all three
# units are up to date and the phrase is legitimately expected.
$dbDone = Join-Path $scratch 'done.sqlite'
RunCapture ("index `"$srcClean`" --db `"$dbDone`"") | Out-Null
$rDone = RunCapture ("index `"$srcClean`" --db `"$dbDone`"")
Check 'C1 the DoIndex Done. line is untouched (skipped N up-to-date still parses)' `
  ([regex]::IsMatch($rDone.Out,'skipped \d+ up-to-date')) `
  "two other runners parse this phrase; the section-line rename must not reach it -- observed: $(($rDone.Out -split "`r?`n" | Where-Object { $_ -match '^Done\.' }) -join ' | ')"

Write-Host ''
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0

<#
  RED-CHECK RECORD -- 2026-09-09, verbatim.

  A guard that has never been observed failing is not a guard. This repo has
  recorded four separate instances of one that could not fail, so the red
  output belongs in the file rather than in a session that will be cleared.

  Run against the engine deployed BEFORE this change (drag-lint 1.10.1-alpha,
  built 2026-09-09 10:54:29, copied aside before the rebuild):

      pwsh -File run_index_section_summary_reconciles.ps1 -Exe <pre-change>\drag-lint.exe
      -> FAIL, exit 1, 34 of 49 checks red.

  The summary line it produced, verbatim:

      === CounterProbe -> ...\counterprobe.sqlite : files=3 symbols=9 refs=3 \
          parsed=3 skipped=0 [0.1s, 2432 files/min] ===

  and the reds that matter:

      [FAIL] R1 summary matches the anchored regex (walked=/attempted=/up-to-date=
             all present, in order)
             no match -- observed: ... parsed=3 skipped=0 [0.1s, 2432 files/min]
      [FAIL] R1 rate is reported as attempted/min          rate=''
      [FAIL] R2 rate is n/a when nothing was attempted     rate=''
      [FAIL] R4 walked=3 (the oversize file IS admitted to the walk)   walked=
      [FAIL] R4 N1 NEGATIVE CONTROL: attempted + up-to-date != walked
             without the oversize term

  Note the rate in that line: 2432 files/min, from a 0.1-second run over three
  files. That is the whole-corpus-over-elapsed numerator this change removes,
  caught in the act by the runner's own red output.

  Two checks PASSED against the pre-change engine, correctly and by design:

    * 'R4 the injector fired: exactly ONE oversize SKIP' -- the size guard is
      pre-existing behaviour, not something this change introduces. If it had
      gone red, the injector would have been imaginary and every INV assertion
      built on it vacuous.
    * both C1 anchors -- they assert that OTHER runners' patterns survive, so
      they must hold on both sides of the change. A C1 that only passed after
      the change would not be testing compatibility at all.

  One check failed against the pre-change engine on the FIRST red run and was
  wrong to: 'C1 the DoIndex Done. line is untouched'. The cause was the
  assertion, not the build -- CLI.pas:4699 prints `skipped N up-to-date` only
  when N > 0, and the check indexed a fresh database. Fixed by indexing twice
  and asserting on the second run. Recorded here because "the guard went red so
  the code is broken" is the inference that produced a false defect report in
  this repo before.
#>
