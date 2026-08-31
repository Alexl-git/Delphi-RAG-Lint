<#
  run_docs_sync_guard.ps1 -- the DOCUMENTED CLI surface must match the REAL one.

  Owner rule, standing as of 2026-08-17: `--help`, README.md and docs\AI-*.md are
  in sync with the code, always. This runner is that rule made falsifiable.

  WHY THIS EXISTS
  ---------------
  Four verbs -- usages, outline, ghost-check, ghost-recover -- were accepted by
  the CLI and driven by the IDE plugin for MONTHS while `--help` never mentioned
  them. Nothing could have caught it: they worked, the battery was green, and the
  only reader who would have noticed is a human diffing two lists by eye. They
  were found by harvesting the command strings the plugin issues and comparing
  them against the help text, which is check 1 below.

  Doc drift is the failure mode where the tool is RIGHT and the reader is wrong,
  so it produces no error anywhere -- an agent reading README.md indexes into a
  database path that was deleted, a user reads "150 rules" and disables a rule
  pack that has since doubled. The cost lands on someone who cannot see the code.

  WHAT IT CHECKS
  --------------
    1  every verb the CLI ACCEPTS appears in `--help`
       (or in $UndocumentedOnPurpose below, WITH a reason)
    2  every rule count stated in README.md / INSTALL.md equals the LIVE catalog
       (`drag-lint rules --json`) -- total and fixable
    3  no doc names a database path in the DEAD shared-project layout
       C:\Projects\.drag-lint\<project>.sqlite. That folder now holds ONLY
       library-Win32.sqlite / library-Win64.sqlite; a project's index moved to
       <project folder>\_D-RAG\<project file base name>.sqlite in 2026-08-11.
    4  no doc claims something is UNDOCUMENTED when `--help` documents it

  CHECK 4 EXISTS BECAUSE CHECKS 1-3 WATCHED THE DRIFT HAPPEN
  ----------------------------------------------------------
  v1.5.0-alpha added the four hidden verbs (usages, outline, ghost-check,
  ghost-recover) and the autofix flags (--file --fix --fix-line --fix-rule
  --apply, plus --no-preprocess) to `--help`. Checks 1-3 all went green on that
  release -- correctly, because the verb list, the rule counts and the DB paths
  were all in sync. Meanwhile ~7 pages under docs\wiki\ still read "Not listed in
  `drag-lint --help` as of v1.4.0-alpha", which had gone from true to exactly
  false. A list comparison cannot see a sentence; prose drifts silently, and it
  drifts INTO A LIE rather than into a gap, which is the worse direction: a
  reader who believes "these flags are undocumented but accepted" will not go
  looking for the documentation that now exists.

  CONSERVATIVE BY CONSTRUCTION, AND THE NARROWING IS THE DESIGN
  -------------------------------------------------------------
  A false FAIL here is worse than a missed one: it puts the battery red over a
  sentence, and the fix is a judgement call about English rather than a fact.
  So the phrase set only matches claims of ABSENCE FROM THE SURFACE ("not listed
  in ... --help", "no CLI equivalent", "not a documented CLI entry point"). It
  DELIBERATELY does not match claims about a documented thing's DETAIL, and there
  are four of those in the tree right now:

    create-enum-helper.md:19, document-all.md:19, find-unit.md:16, safe-delete.md:14
        "...whether omitting it produces a dry run is not documented in the help
        text for this verb"   -- the VERB is documented; a behaviour is not.
    callgraph.md:12
        "which one is the default is not documented in the..."   -- same shape.

  Every one of those would FAIL on a naive "not documented" + page-name match,
  and every one of them is TRUE. Bare "undocumented" is excluded for the same
  reason: it is a FEATURE NAME here (README.md:493 "dead code, undocumented,
  TODOs"; the IDE's "Find Undocumented (public)..." action).

  TOKEN ASSOCIATION, AND WHAT IT REFUSES TO GUESS
  -----------------------------------------------
  A claim only fails if a token can be tied to it CONFIDENTLY, by exactly three
  routes, over a 3-line window (the claim line, the one before, the one after --
  because these sentences wrap, e.g. Fix-all-in-unit.md:31 ends "are NOT listed
  in" and the "--help" lands on :32):

    1. a backticked --flag        (`--fix`, `--apply`)      -- `--help` excluded,
       since every one of these sentences names it by construction
    2. a backticked bare token that is a live help verb
    3. the PAGE FILENAME, when its stem is itself a live help verb -- usages.md,
       outline.md and ghost-check.md ARE those verbs' pages

  Anything else is SKIPPED and NAMED as a [NOTE], never guessed. The skips are
  real coverage gaps and they are supposed to be visible: Compile-Buffer-
  unsaved.md:8 and Recover-Buffer-Compile-Files.md:8 carry the same false "Not
  listed in `drag-lint --help`" line, but their pages are named for the IDE
  ACTION and mention their verb (`ghost-check` / `ghost-recover`) four lines
  further down, outside the window. Widening the window to catch them would also
  start sweeping in tokens from unrelated paragraphs, which is how a guard like
  this starts crying wolf. Named, not silently dropped -- the encoding guard's
  rule for its own unscanned roots.

  HOW "ACCEPTED" IS DETERMINED, AND THE BOUND ON IT
  -------------------------------------------------
  Two sources, deliberately, because each covers the other's blind spot:

    THE DISPATCH TABLE is authoritative and total. DRagLint.CLI.pas's Run() is a
    flat `else if Args.Command = '<verb>' then` chain terminating in
    `ERROR: unknown command`, so the literals in that chain ARE the accepted set.
    Reading it costs nothing and covers every verb, including ones no test and no
    plugin ever invokes. It is a TEXT read of one specific code shape, which is
    its bound: rewrite the dispatch as a table or a case and this scan goes quiet.

    A LIVE PROBE covers exactly that bound. A genuine verb invoked with no args
    prints its OWN usage and never emits `ERROR: unknown command`; a non-verb
    falls through to the general banner and does. Candidate names come from the
    IDE plugin's command strings ("%s" <token> / .exe" <token>) -- the mechanism
    that found the original four. Only candidates the dispatch scan did NOT
    already claim get probed, so in a healthy tree the probe set is the harvest's
    junk (`db`, `params`, `bodyLen` -- JSON format strings, not verbs) and a real
    verb appearing there means the source scan missed it.

  PROBING IS NOT FREE, AND ONE VERB PROVED IT
  -------------------------------------------
  RETIRED 2026-08-30 -- `scan-all` no longer exists, and this paragraph is kept
  because the HAZARD it describes outlived the verb. `index --all` reads the
  same manifest and writes the same databases, so the $NeverProbe rule below is
  unchanged. The retired verb's own behaviour, for the record:
  `scan-all` with no arguments walked UP from the CWD for a .drag-lint.json, found
  C:\Projects\.drag-lint.json -- which still carries a live `scan` block naming
  ten project roots -- and starts indexing them. The battery runs every runner
  with CWD = the repo root ON PURPOSE (run_battery.ps1:404), i.e. inside
  C:\Projects, so a naive probe sweep would launch a full multi-project scan as a
  side effect of a documentation check. Hence: probes run from a scratch CWD
  outside C:\Projects, with stdin closed and a hard timeout, and $NeverProbe
  refuses a short list by name regardless of where it was harvested from.

  IT COMPARES A BUILT ARTIFACT AGAINST SOURCE, AND THAT IS A REAL BOUND
  ---------------------------------------------------------------------
  `--help` comes from third_party\dll-win64\drag-lint.exe; the accepted-verb list
  comes from src\cli\DRagLint.CLI.pas ON DISK. Those are two different points in
  time. Edit PrintHelp and do not rebuild, and check 1 reads the OLD help against
  the NEW dispatch -- reporting doc drift for what is really a stale build. It
  was live while this runner was written: HEAD's CLI.pas lacked the `usages` and
  `outline` help lines that the shipped exe already prints.
  So a check-1 failure has two candidate causes and the cheap one is second:
  rebuild first, re-run, and only then go edit the docs.

  POSITIVE CONTROLS ARE BUILT IN
  ------------------------------
  This repo has shipped guards that could only ever pass. Every derived list here
  therefore asserts its own non-emptiness -- a help parse that yields 0 verbs, a
  dispatch scan that yields 0, or a rules catalog that reports total 0 makes the
  comparison downstream vacuous and TRUE, which is worse than no guard at all.
  The probe classifier additionally proves itself both ways on every run: a known
  verb must classify REAL and a synthetic token must classify NOT-A-VERB, or
  check 1's probe half is declared broken rather than passed.

  SCOPE, and it was WIDENED on 2026-08-31 for cause. Check 2 originally policed
  the TOTAL and the FIXABLE count only, and recorded that "N enabled by default"
  was equally checkable but deliberately unchecked. That omission then did
  exactly what an unchecked claim does: README.md carried "152 enabled by
  default" in one paragraph and "154 enabled by default" in another, against a
  live 154, and this guard passed every run. So DEFAULT-ON is now checked too.

  Categories and the built-in/external split were the last two known-unchecked
  claims, and they went in the same day, for the reason the paragraph they
  replace gave: "nothing has gone wrong with them yet" is precisely the state
  the default-on count was in when README drifted to 152. Check 2 now polices
  total, fixable, default-on, categories, built-in and external -- every count
  `rules --json` can answer -- and asserts the built-in/external split accounts
  for the whole catalog, so a renamed source value cannot quietly make both
  halves low and turn every correct doc into a reported bug.

  Exit code: 0 on full pass, 1 on any failure.

  Usage: pwsh -File tests\autotest\run_docs_sync_guard.ps1
#>
[CmdletBinding()]
param(
  [string] $Exe  = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string] $Repo = "$PSScriptRoot\..\.."
)

$ErrorActionPreference = 'Stop'
$script:Failed = $false

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $status = if ($Ok) { 'PASS' } else { 'FAIL' }
  $color  = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
  if (-not $Ok) { $script:Failed = $true }
}

$Repo = (Resolve-Path $Repo).Path
Write-Host '== documented CLI surface vs the real one ==' -ForegroundColor Cyan

# Full path only. A bare `drag-lint` resolves off PATH to a frozen Win32 build on
# this machine (NoDefaultCurrentDirectoryInExePath=1), which once reported 33,626
# findings against a real 14,764 and read as a catastrophic regression.
Check 'engine exe present' (Test-Path -LiteralPath $Exe) $Exe
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host 'DOCS SYNC GUARD: FAIL' -ForegroundColor Red; exit 1 }
$Exe = (Resolve-Path $Exe).Path

# ---------------------------------------------------------------------------
# CHECK 1 -- every accepted verb is in --help
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 1: verbs' -ForegroundColor Cyan

# Verbs the CLI accepts but deliberately does NOT advertise. Every one is a
# self-test or a diagnostic entry point that exists FOR THE BATTERY, not for a
# user: every one is invoked by a runner under tests\. (It used to read "eight of
# the nine", the ninth being scan-all, which advertised its own DEPRECATED
# banner instead; that verb was RETIRED 2026-08-30 -- deprecated since v0.45,
# zero callers anywhere on the box.) This is not a backlog to be
# cleared -- it is the line between the product's surface and its test harness.
# ASSERTED below, both directions: an entry that is no longer accepted is stale
# and must be deleted, and an entry that HAS since been documented is stale too.
$UndocumentedOnPurpose = [ordered]@{
  'selftest'            = 'umbrella self-test dispatcher (manifest-merge / glob / closure / dbselect / drift / ...). 35 references under tests\. Not a user verb.'
  'contrast-selftest'   = 'self-test for the hover contrast computation; driven by a runner under tests\.'
  'doc-facts-selftest'  = 'self-test for the doc-facts renderer; driven by runners under tests\.'
  'test-store-freshness'= 'store-freshness probe used by a test runner; requires --db and does nothing else.'
  'dump-pp-lex'         = 'diagnostic: preprocessor lexer dump. The documented preprocessor verbs are preprocess-file and pp-profile.'
  'dump-pp-eval'        = 'diagnostic: preprocessor expression-evaluation dump. Same pairing as dump-pp-lex.'
  'resolve-uses'        = 'diagnostic behind the documented `check-unit --resolve-uses` flag; not a surface verb of its own.'
  'convert-reemit'      = 'internal stage of the conversion pipeline (DFM re-emit), driven by convert-apply and by two runners under tests\.'
}

# Never probed, whatever a harvest turns up. A documentation check must not have
# side effects, and these do: `index` writes databases (`index --all` builds every
# section of the manifest, and the battery runs runners with CWD inside
# C:\Projects, where a manifest is discoverable), and
# `serve`/`lsp` are stdin protocol servers that would sit until the timeout.
$NeverProbe = [ordered]@{
  'index'    = 'writes/updates a .sqlite index'
  'serve'    = 'MCP stdio server -- blocks on stdin'
  'lsp'      = 'LSP stdio server -- blocks on stdin'
}

$helpText  = (& $Exe --help 2>&1 | Out-String)
$helpVerbs = @([regex]::Matches($helpText, '(?m)^\s{2}drag-lint\s+([a-z][a-z0-9-]*)') |
                 ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
# Non-emptiness is the control: a help parse that yields nothing makes every
# "is it documented?" comparison below trivially true.
Check '--help verb list parsed' ($helpVerbs.Count -gt 20) "($($helpVerbs.Count) verb(s))"

$cliPas = Join-Path $Repo 'src\cli\DRagLint.CLI.pas'
Check 'CLI dispatch source present' (Test-Path -LiteralPath $cliPas) 'src\cli\DRagLint.CLI.pas'
$cliSrc   = if (Test-Path -LiteralPath $cliPas) { Get-Content -LiteralPath $cliPas -Raw } else { '' }
$dispatch = @([regex]::Matches($cliSrc, "Args\.Command\s*=\s*'([a-z][a-z0-9-]*)'") |
                ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
Check 'CLI dispatch table parsed' ($dispatch.Count -gt 20) "($($dispatch.Count) verb(s) accepted)"

# --- 1a: accepted but undocumented ----------------------------------------
$missing = @($dispatch | Where-Object { ($helpVerbs -notcontains $_) -and (-not $UndocumentedOnPurpose.Contains($_)) })
Check 'every verb the CLI accepts is listed in --help' ($missing.Count -eq 0) `
  $(if ($missing.Count -gt 0) { "undocumented: $($missing -join ' ')" } else { "($($dispatch.Count) checked)" })
if ($missing.Count -gt 0) {
  Write-Host '        ^ the CLI accepts a verb that --help never names. This is how usages,' -ForegroundColor Yellow
  Write-Host '          outline, ghost-check and ghost-recover stayed invisible for months' -ForegroundColor Yellow
  Write-Host '          while the IDE plugin shipped features built on them.' -ForegroundColor Yellow
  Write-Host '          Add it to PrintHelp in src\cli\DRagLint.CLI.pas -- or, if it is a' -ForegroundColor Yellow
  Write-Host '          self-test / diagnostic, to $UndocumentedOnPurpose here WITH a reason.' -ForegroundColor Yellow
}

# --- 1b: documented but not accepted (the other direction of the same rule) --
$phantom = @($helpVerbs | Where-Object { $dispatch -notcontains $_ })
Check 'every verb --help advertises is still dispatched' ($phantom.Count -eq 0) `
  $(if ($phantom.Count -gt 0) { "phantom: $($phantom -join ' ')" } else { '' })
if ($phantom.Count -gt 0) {
  Write-Host '        ^ --help documents a verb the dispatch chain no longer handles, so it' -ForegroundColor Yellow
  Write-Host '          exits 2 with "unknown command" for anyone who follows the help.' -ForegroundColor Yellow
}

# --- 1c: the exemption list cannot outlive what it exempts ------------------
$staleExempt = @($UndocumentedOnPurpose.Keys | Where-Object { $dispatch -notcontains $_ })
Check 'every $UndocumentedOnPurpose entry is still an accepted verb' ($staleExempt.Count -eq 0) `
  $(if ($staleExempt.Count -gt 0) { "stale: $($staleExempt -join ' ')" } else { "($($UndocumentedOnPurpose.Count) exemption(s))" })
$nowDocumented = @($UndocumentedOnPurpose.Keys | Where-Object { $helpVerbs -contains $_ })
Check 'no $UndocumentedOnPurpose entry has since been documented' ($nowDocumented.Count -eq 0) `
  $(if ($nowDocumented.Count -gt 0) { "now in --help, drop the entry: $($nowDocumented -join ' ')" } else { '' })

# --- 1d: the live probe, covering the dispatch scan's blind spot ------------
$probeDir = Join-Path ([System.IO.Path]::GetTempPath()) ('draglint-docs-guard-' + [Guid]::NewGuid().ToString('N'))
[System.IO.Directory]::CreateDirectory($probeDir) | Out-Null
$probeIn = Join-Path $probeDir 'stdin.txt'
[System.IO.File]::WriteAllText($probeIn, '')

# TRUE = the engine dispatched it (a real verb). FALSE = it fell through to
# `ERROR: unknown command` and the general banner.
function Test-IsRealVerb([string]$Verb) {
  $o = Join-Path $script:probeDir ('o_' + ($Verb -replace '[^a-zA-Z0-9-]', '_') + '.txt')
  $e = $o + '.err'
  $p = Start-Process -FilePath $script:Exe -ArgumentList $Verb -WorkingDirectory $script:probeDir `
         -PassThru -WindowStyle Hidden `
         -RedirectStandardInput $script:probeIn -RedirectStandardOutput $o -RedirectStandardError $e
  if (-not $p.WaitForExit(20000)) { try { $p.Kill($true) } catch { }; $p.WaitForExit() }
  $txt = ([System.IO.File]::ReadAllText($o) + [System.IO.File]::ReadAllText($e))
  return ($txt -notmatch 'unknown command')
}

# The classifier proves itself BOTH ways before it is trusted to judge anything.
# `usages` is a real verb that requires --name, so it prints its own usage line
# and writes nothing; the synthetic token cannot be a verb by construction.
$ctlReal = Test-IsRealVerb 'usages'
$ctlFake = Test-IsRealVerb ('zz-not-a-verb-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
Check 'probe control: a known verb classifies as REAL' $ctlReal 'usages'
Check 'probe control: a synthetic token classifies as NOT-A-VERB' (-not $ctlFake) ''

$pluginDir = Join-Path $Repo 'src\delphi-plugin'
$harvest = @()
if (Test-Path -LiteralPath $pluginDir) {
  foreach ($f in (Get-ChildItem -LiteralPath $pluginDir -File -Filter '*.pas')) {
    $src = Get-Content -LiteralPath $f.FullName -Raw
    $harvest += @([regex]::Matches($src, '(?:"%s"|\.exe")\s+([a-z][a-z0-9-]*)') |
                    ForEach-Object { $_.Groups[1].Value })
  }
}
$harvest = @($harvest | Sort-Object -Unique)
Check 'IDE plugin command strings harvested' ($harvest.Count -gt 5) "($($harvest.Count) candidate token(s))"

$toProbe = @($harvest | Where-Object {
  ($helpVerbs -notcontains $_) -and ($dispatch -notcontains $_) -and (-not $NeverProbe.Contains($_))
})
$probedReal = New-Object System.Collections.Generic.List[string]
if ($ctlReal -and (-not $ctlFake)) {
  foreach ($t in $toProbe) { if (Test-IsRealVerb $t) { $probedReal.Add($t) } }
}
Check 'no plugin-issued token is an accepted verb the source scan missed' ($probedReal.Count -eq 0) `
  "($($toProbe.Count) probed$(if ($probedReal.Count -gt 0) { "; REAL: $($probedReal -join ' ')" }))"
if ($probedReal.Count -gt 0) {
  Write-Host '        ^ the engine dispatched a token the dispatch-table scan did not claim,' -ForegroundColor Yellow
  Write-Host '          so the verb list above is INCOMPLETE as well as undocumented. Check' -ForegroundColor Yellow
  Write-Host '          whether Run() still uses the flat `Args.Command = ''x''` chain this' -ForegroundColor Yellow
  Write-Host '          runner reads, then document the verb.' -ForegroundColor Yellow
}

try { [System.IO.Directory]::Delete($probeDir, $true) } catch { }

foreach ($k in $UndocumentedOnPurpose.Keys) {
  Write-Host ("  [NOTE] accepted but NOT in --help, on purpose: {0}" -f $k) -ForegroundColor DarkGray
  Write-Host ("         {0}" -f $UndocumentedOnPurpose[$k]) -ForegroundColor DarkGray
}
foreach ($k in $NeverProbe.Keys) {
  Write-Host ("  [NOTE] never probed: {0} -- {1}" -f $k, $NeverProbe[$k]) -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# CHECK 2 -- rule counts in README.md / INSTALL.md vs the live catalog
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 2: rule counts' -ForegroundColor Cyan

$total = 0; $fixable = 0; $defaultOn = 0
try {
  $cat       = (& $Exe rules --json 2>$null | Out-String) | ConvertFrom-Json
  $total     = [int]$cat.summary.total
  $fixable   = @($cat.rules | Where-Object { $_.fixable }).Count
  $defaultOn = @($cat.rules | Where-Object { $_.default_enabled }).Count
  $catCount  = @($cat.rules | Group-Object category).Count
  $builtin   = @($cat.rules | Where-Object { $_.source -eq 'builtin' }).Count
  $external  = @($cat.rules | Where-Object { $_.source -eq 'scm'     }).Count
} catch {
  Check 'rules --json parsed' $false $_.Exception.Message
}
# Non-emptiness control again: total=0 would make every stated count "wrong" in
# a way that looks like a docs bug, and fixable=0 would silently excuse every
# fixable claim. Assert the catalog is real before comparing anything to it.
Check 'live rule catalog read' `
  (($total -gt 0) -and ($fixable -gt 0) -and ($defaultOn -gt 0) -and
   ($catCount -gt 0) -and ($builtin -gt 0) -and ($external -gt 0)) `
  "total=$total fixable=$fixable defaultOn=$defaultOn categories=$catCount builtin=$builtin external=$external"
# The split must also ACCOUNT for the whole catalog. A source value that stops
# being 'builtin'/'scm' would leave both counts low and every doc claim would
# then look wrong, which reads as a docs bug rather than as this guard losing
# its grip on the data.
Check 'builtin + external accounts for every rule' (($builtin + $external) -eq $total) `
  "$builtin + $external vs total $total"

# 2026-08-17: docs\wiki\ joined this scan. It was README/INSTALL only, which left
# every wiki page's rule count unpoliced -- and pages DO state them (Fix-it.md
# and Features.md both quote "22 of the 173"). A wiki page carrying a stale count
# is exactly as wrong as a README carrying one, and the wiki is the more likely
# place for a count to rot because there are 125 pages of it.
$countDocs = @(
                @('README.md', 'INSTALL.md') | ForEach-Object { Join-Path $Repo $_ }
                Get-ChildItem -LiteralPath (Join-Path $Repo 'docs\wiki') -Filter '*.md' -File -ErrorAction SilentlyContinue |
                  ForEach-Object { $_.FullName }
              ) | Where-Object { Test-Path -LiteralPath $_ }
# WHOLE-FILE, NOT LINE BY LINE -- and that is the fix for the bug this check
# was widened to catch. The 152/154 drift lived at README.md:543-544, where the
# NUMBER and the words 'enabled by default' sit on DIFFERENT LINES because the
# paragraph wraps. A per-line scan cannot see that claim at all, so the count
# was unpoliced in the one place it was actually wrong -- and a probe that
# broke it stayed GREEN (observed 2026-08-31, README saying 999 and this guard
# passing). The same blind spot applied to 'N rules' and 'N fixable'.
#
# Newlines are replaced with SPACES rather than stripped, so every character
# offset is preserved 1:1 and a match index still maps back to a real line
# number. Report the line the claim STARTS on.
$badCount = New-Object System.Collections.Generic.List[string]
$seenCount = 0
foreach ($d in $countDocs) {
  $rel  = $d.Substring($Repo.Length + 1)
  $raw  = Get-Content -LiteralPath $d -Raw
  if ($null -eq $raw) { continue }
  $flat = $raw -replace '[\r\n]', ' '
  if ($flat.Length -ne $raw.Length) {
    # Never silently scan a mis-aligned string: the line numbers would be
    # wrong and every report would point at the wrong place.
    Check ('offset-preserving flatten for ' + $rel) $false 'newline replacement changed the length'
    continue
  }
  function LineOf([int]$idx) { return ([regex]::Matches($raw.Substring(0, $idx), "`n").Count + 1) }

  # "N rules" -- an exact claim, must equal the live total.
  foreach ($m in [regex]::Matches($flat, '\b(\d{2,4})\s+rules\b')) {
    $seenCount++
    if ([int]$m.Groups[1].Value -ne $total) {
      $badCount.Add(("{0}:{1}: says '{2} rules', live total is {3}" -f $rel, (LineOf $m.Index), $m.Groups[1].Value, $total))
    }
  }
  # "N+ rules" -- a floor, so only a claim ABOVE the live total is wrong.
  foreach ($m in [regex]::Matches($flat, '\b(\d{2,4})\+\s+rules\b')) {
    $seenCount++
    if ([int]$m.Groups[1].Value -gt $total) {
      $badCount.Add(("{0}:{1}: says '{2}+ rules', live total is only {3}" -f $rel, (LineOf $m.Index), $m.Groups[1].Value, $total))
    }
  }
  # "N with an auto-fix" / "N fixable" -- must equal the live fixable count.
  # \d{1,4}, NOT the \d{2,4} the two patterns above use. The fixable count is
  # plausibly a single digit (it was 22 when this was written, and a rule pack
  # that loses autofixes shrinks toward 0), and \d{2,4} made a one-digit claim
  # INVISIBLE rather than wrong -- caught by a positive control that broke the
  # count to 9 and watched this check stay silent. A two-digit floor is fine
  # for "N rules", where a genuine claim of "9 rules" would be absurd.
  foreach ($m in [regex]::Matches($flat, '\b(\d{1,4})\s+(?:with an auto-fix|with auto-fix|autofixable|fixable)\b')) {
    $seenCount++
    if ([int]$m.Groups[1].Value -ne $fixable) {
      $badCount.Add(("{0}:{1}: claims {2} fixable, live fixable is {3}" -f $rel, (LineOf $m.Index), $m.Groups[1].Value, $fixable))
    }
  }
  # "N enabled by default". Added 2026-08-31 after README.md said both 152 and
  # 154 in the same file, against a live 154, while this guard passed every run.
  foreach ($m in [regex]::Matches($flat, '\b(\d{1,4})\s+enabled by default\b')) {
    $seenCount++
    if ([int]$m.Groups[1].Value -ne $defaultOn) {
      $badCount.Add(("{0}:{1}: claims {2} enabled by default, live default-on is {3}" -f $rel, (LineOf $m.Index), $m.Groups[1].Value, $defaultOn))
    }
  }
  # "N categories". Added 2026-08-31 -- this guard's own scope note had been
  # carrying it as a known-unchecked claim, which is exactly the state the
  # default-on count was in when README drifted to 152.
  foreach ($m in [regex]::Matches($flat, '\b(\d{1,3})\s+categor(?:y|ies)\b')) {
    $seenCount++
    if ([int]$m.Groups[1].Value -ne $catCount) {
      $badCount.Add(("{0}:{1}: claims {2} categories, live is {3}" -f $rel, (LineOf $m.Index), $m.Groups[1].Value, $catCount))
    }
  }
  # "N built-in" / "N are built-in", and the same for external. rules.md phrases
  # it as "124 are built-in and 54 are external", so the optional 'are' is not
  # decoration -- without it that page's claims match nothing.
  foreach ($m in [regex]::Matches($flat, '\b(\d{1,4})\s+(?:are\s+)?built-in\b')) {
    $seenCount++
    if ([int]$m.Groups[1].Value -ne $builtin) {
      $badCount.Add(("{0}:{1}: claims {2} built-in, live is {3}" -f $rel, (LineOf $m.Index), $m.Groups[1].Value, $builtin))
    }
  }
  foreach ($m in [regex]::Matches($flat, '\b(\d{1,4})\s+(?:are\s+)?external\b')) {
    $seenCount++
    if ([int]$m.Groups[1].Value -ne $external) {
      $badCount.Add(("{0}:{1}: claims {2} external, live is {3}" -f $rel, (LineOf $m.Index), $m.Groups[1].Value, $external))
    }
  }
}

# SELF-TEST, because every pattern above was silently matching nothing at some
# point in this guard's life. Assert each one finds at least one live claim:
# a pattern that matches zero documents is indistinguishable from a clean tree.
$patternHits = [ordered]@{}
foreach ($pat in @(
      @{ n = 'N rules';           r = '\b(\d{2,4})\s+rules\b' },
      @{ n = 'N fixable';         r = '\b(\d{1,4})\s+(?:with an auto-fix|with auto-fix|autofixable|fixable)\b' },
      @{ n = 'N enabled by default'; r = '\b(\d{1,4})\s+enabled by default\b' },
      @{ n = 'N categories';      r = '\b(\d{1,3})\s+categor(?:y|ies)\b' },
      @{ n = 'N built-in';        r = '\b(\d{1,4})\s+(?:are\s+)?built-in\b' },
      @{ n = 'N external';        r = '\b(\d{1,4})\s+(?:are\s+)?external\b' })) {
  $hits = 0
  foreach ($d in $countDocs) {
    $raw2 = Get-Content -LiteralPath $d -Raw
    if ($null -eq $raw2) { continue }
    $hits += [regex]::Matches(($raw2 -replace '[\r\n]', ' '), $pat.r).Count
  }
  $patternHits[$pat.n] = $hits
  Check ('claim pattern is live: ' + $pat.n) ($hits -gt 0) "$hits match(es) across $($countDocs.Count) doc(s)"
}

Check 'rule-count claims located' ($seenCount -gt 0) "($seenCount claim(s) in README.md + INSTALL.md)"
Check 'every stated rule count matches the live catalog' ($badCount.Count -eq 0) "($($badCount.Count) mismatch(es))"
foreach ($x in $badCount) { Write-Host "        $x" -ForegroundColor Red }
if ($badCount.Count -gt 0) {
  Write-Host '        ^ `drag-lint rules` is the authoritative catalog and it moved. A stale' -ForegroundColor Yellow
  Write-Host '          count in the README is read by people deciding whether to adopt the' -ForegroundColor Yellow
  Write-Host '          tool, and by agents deciding whether a rule pack is worth enabling.' -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# CHECK 3 -- no doc names a database path that cannot exist
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 3: database paths' -ForegroundColor Cyan

# The ONLY .sqlite files that still live directly inside a .drag-lint\ folder.
# Everything else moved to <project folder>\_D-RAG\<project file base>.sqlite on
# 2026-08-11, and the union DBs that preceded that layout were deleted outright.
$LiveInSharedFolder = @('library-Win32', 'library-Win64')

$pathDocs = @(@('README.md', 'INSTALL.md') | ForEach-Object { Join-Path $Repo $_ }) +
            @(Get-ChildItem -LiteralPath (Join-Path $Repo 'docs') -File -Filter 'AI-*.md' -ErrorAction SilentlyContinue |
                ForEach-Object { $_.FullName })
$pathDocs = @($pathDocs | Where-Object { Test-Path -LiteralPath $_ })
Check 'docs to scan for DB paths located' ($pathDocs.Count -ge 3) "($($pathDocs.Count) file(s))"

$deadPaths = New-Object System.Collections.Generic.List[string]
$seenPaths = 0
foreach ($d in $pathDocs) {
  $rel = $d.Substring($Repo.Length + 1)
  $n = 0
  foreach ($line in (Get-Content -LiteralPath $d)) {
    $n++
    # Any .sqlite named DIRECTLY inside a .drag-lint folder, whatever the drive
    # or prefix. Broader than matching the literal C:\Projects\ spelling, and
    # correct for the same reason: the two library DBs are the only legitimate
    # inhabitants of that folder anywhere.
    foreach ($m in [regex]::Matches($line, '(?i)\.drag-lint[\\/]+([A-Za-z0-9._-]+)\.sqlite')) {
      $seenPaths++
      $stem = $m.Groups[1].Value
      if ($LiveInSharedFolder -notcontains $stem) {
        $deadPaths.Add(("{0}:{1}: {2}.sqlite -- shared-folder project layout, deleted 2026-08-11" -f $rel, $n, $stem))
      }
    }
  }
}
Check 'shared-folder .sqlite references located' ($seenPaths -gt 0) "($seenPaths reference(s))"
Check 'no doc names a database in the dead shared-project layout' ($deadPaths.Count -eq 0) "($($deadPaths.Count) offender(s))"
foreach ($x in $deadPaths) { Write-Host "        $x" -ForegroundColor Red }
if ($deadPaths.Count -gt 0) {
  Write-Host '        ^ that path cannot exist. A project index is now' -ForegroundColor Yellow
  Write-Host '          <project folder>\_D-RAG\<project file base name>.sqlite; only' -ForegroundColor Yellow
  Write-Host '          library-Win32.sqlite / library-Win64.sqlite remain in .drag-lint\.' -ForegroundColor Yellow
  Write-Host '          Do not hand-write the replacement either -- the doc should say' -ForegroundColor Yellow
  Write-Host '          `drag-lint resolve-dbs --project <x.dproj>` and let the tool answer.' -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# CHECK 4 -- no doc claims something is undocumented when --help documents it
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 4: stale "this is undocumented" claims' -ForegroundColor Cyan

# Claims of ABSENCE FROM THE SURFACE. See the header for the four "not documented
# in the help text for this verb" lines this deliberately does NOT match, and why
# every one of them is true.
$AbsenceClaims = @(
  'not\s+listed\s+in\b[^.]{0,40}--help'
  '\bis\s+not\s+in\s+`?--help'
  'no\s+CLI\s+equivalent'
  'not\s+a\s+documented\s+CLI\s+entry\s+point'
  '\bundocumented\s+(?:verb|flag|command|switch)\b'
)

# Claims that are legitimately true and must not fail the battery. Key is
# 'relative\path.md:LINE'. ASSERTED BOTH WAYS below: the file+line must still
# carry a claim, and that claim must still resolve to a documented token -- an
# entry that is no longer NEEDED is stale and fails, so this cannot rot into a
# blanket suppression the way a baseline does.
$NegativeClaimExemptions = [ordered]@{}

# Every --flag --help mentions. --help itself is excluded from association: each
# of these sentences names it ("not listed in `drag-lint --help`"), so treating
# it as the subject would fail every claim on the planet.
$helpFlags = @([regex]::Matches($helpText, '--[a-z][a-z0-9-]+') |
                 ForEach-Object { $_.Value } | Sort-Object -Unique |
                 Where-Object { $_ -ne '--help' })
Check '--help flag list parsed' ($helpFlags.Count -gt 20) "($($helpFlags.Count) flag(s))"

$claimDocs = @(Get-ChildItem -LiteralPath (Join-Path $Repo 'docs\wiki') -File -Filter '*.md' -ErrorAction SilentlyContinue |
                 ForEach-Object { $_.FullName }) +
             @(@('README.md', 'INSTALL.md') | ForEach-Object { Join-Path $Repo $_ })
$claimDocs = @($claimDocs | Where-Object { Test-Path -LiteralPath $_ })
Check 'docs to scan for stale claims located' ($claimDocs.Count -ge 3) "($($claimDocs.Count) file(s))"

$staleClaims = New-Object System.Collections.Generic.List[string]
$skipped     = New-Object System.Collections.Generic.List[string]
$exemptHit   = New-Object System.Collections.Generic.List[string]
# Location keys of exemptions that actually fired. A SET, deliberately: the first
# version tested staleness with `$exemptHit -notmatch $key`, and -notmatch over a
# COLLECTION returns the non-matching ELEMENTS rather than a boolean, so a
# non-empty remainder read as $true. That inverted the check both ways -- a
# needed exemption reported stale, a genuinely stale one reported fine -- and it
# passed review by looking exactly like a membership test. Caught only by running
# both controls.
$exemptHitLoc = New-Object System.Collections.Generic.HashSet[string]
$claimsSeen  = 0
$seenKey     = New-Object System.Collections.Generic.HashSet[string]

foreach ($d in $claimDocs) {
  $rel   = $d.Substring($Repo.Length + 1)
  $stem  = [System.IO.Path]::GetFileNameWithoutExtension($d)
  $lines = @(Get-Content -LiteralPath $d)
  for ($i = 0; $i -lt $lines.Count; $i++) {
    # The claim may WRAP, so match over this line plus the next one.
    $sentence = $lines[$i] + ' ' + $(if ($i + 1 -lt $lines.Count) { $lines[$i + 1] } else { '' })
    # The claim is ANCHORED to the line it starts on. Without this every claim is
    # counted twice -- once at its own line and once at the blank line above it,
    # whose 2-line window contains the whole sentence -- which inflates the
    # population and reports a [NOTE] against a line that is empty. Caught by the
    # first run: 14 "claims" over 7 real sentences.
    $isClaim = $false
    foreach ($pat in $AbsenceClaims) {
      $m = [regex]::Match($sentence, "(?i)$pat")
      if ($m.Success -and ($m.Index -lt $lines[$i].Length)) { $isClaim = $true; break }
    }
    if (-not $isClaim) { continue }
    $claimsSeen++

    # Association window: the line before, the claim line, the line after.
    $window = $(if ($i -gt 0) { $lines[$i - 1] } else { '' }) + ' ' + $sentence
    $tokens = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($window, '`(--[a-z][a-z0-9-]*)`')) {
      if ($m.Groups[1].Value -ne '--help') { $tokens.Add($m.Groups[1].Value) }
    }
    foreach ($m in [regex]::Matches($window, '`([a-z][a-z0-9-]*)`')) {
      if ($helpVerbs -contains $m.Groups[1].Value) { $tokens.Add($m.Groups[1].Value) }
    }
    if ($helpVerbs -contains $stem) { $tokens.Add($stem) }
    $tokens = @($tokens | Sort-Object -Unique)

    $loc = "{0}:{1}" -f $rel, ($i + 1)
    if ($tokens.Count -eq 0) {
      # NAMED, never guessed. A skip is a coverage gap and must be visible.
      $skipped.Add(("{0}: {1}" -f $loc, $lines[$i].Trim()))
      continue
    }
    foreach ($t in $tokens) {
      $documented = if ($t.StartsWith('--')) { $helpFlags -contains $t } else { $helpVerbs -contains $t }
      if (-not $documented) { continue }
      if (-not $seenKey.Add("$rel|$t")) { continue }   # one report per page per token
      if ($NegativeClaimExemptions.Contains($loc)) {
        $exemptHit.Add("$loc ($t)"); $exemptHitLoc.Add($loc) | Out-Null; continue
      }
      $staleClaims.Add(("{0}: claims '{1}' is undocumented, but --help documents it" -f $loc, $t))
    }
  }
}

Check 'absence-of-surface claims located' ($claimsSeen -gt 0) "($claimsSeen claim(s) across $($claimDocs.Count) file(s))"
Check 'no doc calls a documented verb or flag undocumented' ($staleClaims.Count -eq 0) "($($staleClaims.Count) stale claim(s))"
foreach ($x in $staleClaims) { Write-Host "        $x" -ForegroundColor Red }
if ($staleClaims.Count -gt 0) {
  Write-Host '        ^ that sentence was true and is now the OPPOSITE of the truth. It tells' -ForegroundColor Yellow
  Write-Host '          the reader not to look for documentation that exists. Fix the prose --' -ForegroundColor Yellow
  Write-Host '          or, if the claim is genuinely still right, add file:line to' -ForegroundColor Yellow
  Write-Host '          $NegativeClaimExemptions WITH a reason.' -ForegroundColor Yellow
}

# An exemption that is no longer NEEDED is stale. Without this the list would
# decay into a blanket suppression nobody re-reads -- the failure mode that got
# the encoding guard's 80-entry baseline deleted.
$staleExemptions = @($NegativeClaimExemptions.Keys | Where-Object { -not $exemptHitLoc.Contains($_) })
Check 'every $NegativeClaimExemptions entry is still needed' ($staleExemptions.Count -eq 0) `
  $(if ($staleExemptions.Count -gt 0) { "stale: $($staleExemptions -join ', ')" } else { "($($NegativeClaimExemptions.Count) exemption(s))" })
if ($staleExemptions.Count -gt 0) {
  Write-Host '        ^ the claim this exempts is gone, moved line, or no longer names a' -ForegroundColor Yellow
  Write-Host '          documented token. Delete the entry -- an exemption outliving the thing' -ForegroundColor Yellow
  Write-Host '          it excuses is a note that silently widens what this guard ignores.' -ForegroundColor Yellow
}
foreach ($k in $NegativeClaimExemptions.Keys) {
  Write-Host ("  [NOTE] stale-claim exemption: {0}" -f $k) -ForegroundColor DarkGray
  Write-Host ("         {0}" -f $NegativeClaimExemptions[$k]) -ForegroundColor DarkGray
}
# The skips ARE the blind spot. Printed in full, every run, on purpose.
Write-Host ("  [NOTE] {0} claim(s) skipped -- no token could be tied to the sentence:" -f $skipped.Count) -ForegroundColor DarkGray
foreach ($x in $skipped) { Write-Host ("         {0}" -f $x) -ForegroundColor DarkGray }

# ---------------------------------------------------------------------------
# CHECK 5 -- documented menu items still exist in the menu registration
#
# Added session 27, after a menu restructure silently invalidated the feature
# map, the menu reference and the user guide all at once. Checks 1-4 cover the
# CLI surface; nothing covered the IDE surface, so "drag-lint > Run AST Checks"
# could name a menu path that had not existed for a week and every check passed.
#
# Deliberately NARROW. It compares only the LEAF caption of each documented
# "drag-lint > ..." path against the set of captions the registration actually
# creates. It does NOT verify submenu nesting: captions are unique in practice,
# and matching whole paths would need a parse of the menu tree that would break
# on every cosmetic regrouping -- a guard that cries wolf gets weakened, and a
# weakened guard is what produced the drift this exists to catch.
# ---------------------------------------------------------------------------

Write-Host ''
Write-Host '-- check 5: documented menu paths vs the registration' -ForegroundColor Cyan

$editorPas = Join-Path $Repo 'src\delphi-plugin\DragLint.Plugin.Editor.pas'
$aboutForm = Join-Path $Repo 'src\delphi-plugin\DragLint.Plugin.AboutForm.pas'
$menuSrc   = ''
foreach ($p in @($editorPas, $aboutForm)) {
  if (Test-Path -LiteralPath $p) { $menuSrc += (Get-Content -LiteralPath $p -Raw) }
}
Check 'plugin menu sources located' ($menuSrc.Length -gt 0) `
  "$([System.IO.Path]::GetFileName($editorPas)) + $([System.IO.Path]::GetFileName($aboutForm))"

# Captions the plugin actually creates: menu items, section headers, and the
# About window's buttons (the seven diagnostics actions live there now, so a doc
# naming them is correct only if the button still exists).
$liveCaptions = New-Object System.Collections.Generic.HashSet[string]
foreach ($rx in @(
    "AddWrappedItem\(\s*\w+\s*,\s*'([^']+)'",
    "AddSectionHeader\(\s*\w+\s*,\s*'([^']+)'",
    "Add(?:Proc)?Button\(\s*'([^']+)'",
    "\.Caption\s*:=\s*'([^']+)'")) {
  foreach ($m in [regex]::Matches($menuSrc, $rx)) {
    # '&&' is the Delphi escape for a literal '&' in a caption; docs write one.
    [void]$liveCaptions.Add($m.Groups[1].Value.Replace('&&', '&').Trim())
  }
}
Check 'live menu captions harvested' ($liveCaptions.Count -ge 40) "$($liveCaptions.Count) caption(s)"

# Documented paths: "drag-lint > A > B" in any tracked doc, plus the feature
# map's MenuPath column.
$menuDocs = @()
foreach ($d in @('docs\wiki', 'docs')) {
  $dir = Join-Path $Repo $d
  if (Test-Path -LiteralPath $dir) {
    $menuDocs += @(Get-ChildItem -LiteralPath $dir -Filter *.md -File -ErrorAction SilentlyContinue)
  }
}
$fmPath = Join-Path $Repo 'docs\wiki-featuremap.tsv'
if (Test-Path -LiteralPath $fmPath) { $menuDocs += @(Get-Item -LiteralPath $fmPath) }
Check 'docs to scan for menu paths located' ($menuDocs.Count -gt 0) "$($menuDocs.Count) file(s)"

# PLAN-*, INBOX-* and RESUME-* are gitignored working notes: they record what
# the menu USED to be on purpose, and must not fail the battery.
$menuDocs = @($menuDocs | Where-Object { $_.Name -notmatch '^(PLAN|INBOX|RESUME)-' })

# Docs abbreviate captions on purpose -- "Call Graph" for "Call Graph
# (Butterfly)...", "Compile Buffer" for "Compile Buffer (unsaved)". Comparing
# raw strings flags all of those, and a guard that flags correct prose is one
# that gets switched off. So: normalise both sides, then accept a doc leaf that
# is a PREFIX of a real caption. That still catches a caption that no longer
# exists at all, which is the failure this check is for.
function Get-CaptionKey([string]$S) {
  $s = $S.Replace('&&', '&')
  $s = $s -replace '\.\.\.', ' '          # trailing ellipsis is decoration
  $s = $s -replace '[`*"]', ' '
  $s = $s -replace '\s+', ' '
  return $s.Trim().Trim('.', ',', ';', ':', ')', '(').ToLowerInvariant()
}

$liveKeys = @($liveCaptions | ForEach-Object { Get-CaptionKey $_ } | Where-Object { $_ })

$badPaths = New-Object System.Collections.Generic.List[string]
$pathCount = 0
foreach ($f in $menuDocs) {
  $lineNo = 0
  foreach ($line in (Get-Content -LiteralPath $f.FullName)) {
    $lineNo++
    # Require whitespace around the separator. Without it "Uses Audit --
    # interface->impl moves" splits at the arrow in ordinary prose and the
    # fragment "impl moves + unused" gets reported as a dead menu path.
    # '*' terminates the capture: menu paths are usually written in bold, and
    # without this the match runs on into the parenthetical that follows
    # ("**drag-lint > drag-lint Options...** (or **Tools > Options > ...").
    foreach ($m in [regex]::Matches($line, 'drag-lint\s+>\s+([^|*`\r\n]+)')) {
      $segs = @($m.Groups[1].Value -split '\s+>\s+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
      if ($segs.Count -eq 0) { continue }
      # Prose commonly continues past the menu path ("... > Show Structure, then
      # right-click"). Cut the leaf at the first sentence break.
      $leaf = ($segs[-1] -split '(?:,|;|:|"|\.\s|\s--\s|\bthen\b|\band\b)')[0]
      $key  = Get-CaptionKey $leaf
      if (-not $key) { continue }
      $pathCount++
      # Prefix match in BOTH directions. Docs abbreviate ("Call Graph" for "Call
      # Graph (Butterfly)..."), and prose runs on past the caption ("Open Plugin
      # Log opens the..."). Either way the caption is present and correct; only a
      # name that matches nothing in either direction is genuinely dead.
      $hit = $false
      foreach ($lk in $liveKeys) {
        if ($lk -eq $key -or $lk.StartsWith($key) -or $key.StartsWith($lk)) { $hit = $true; break }
      }
      if (-not $hit) {
        $badPaths.Add(("{0}:{1}: drag-lint > ... > '{2}'" -f $f.Name, $lineNo, $leaf.Trim()))
      }
    }
  }
}
Check 'menu paths located in docs' ($pathCount -gt 0) "$pathCount reference(s)"
Check 'every documented menu path names a caption that exists' ($badPaths.Count -eq 0) `
  $(if ($badPaths.Count -gt 0) { "$($badPaths.Count) dead path(s)" } else { '0 dead path(s)' })
foreach ($b in ($badPaths | Select-Object -First 25)) { Write-Host ("         {0}" -f $b) -ForegroundColor Yellow }
if ($badPaths.Count -gt 0) {
  Write-Host '        ^ the doc names a menu item the plugin no longer creates. Either the' -ForegroundColor Yellow
  Write-Host '          item was renamed/moved and the doc was not updated, or the doc has a' -ForegroundColor Yellow
  Write-Host '          typo. A menu path that leads nowhere is worse than no path at all.' -ForegroundColor Yellow
}

# POSITIVE CONTROL. Without this the check passes when the harvest silently
# returns nothing -- the exact fail-open shape that let a scrub run zero times
# while its whole suite stayed green.
$ctlLive = $liveCaptions.Contains('About')
$ctlDead = $liveCaptions.Contains('Zz Not A Real Menu Item')
Check 'positive control: a real caption is recognised' $ctlLive "'About'"
Check 'negative control: an invented caption is not' (-not $ctlDead) "'Zz Not A Real Menu Item'"

Write-Host ''
if ($script:Failed) { Write-Host 'DOCS SYNC GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'DOCS SYNC GUARD: PASS' -ForegroundColor Green
exit 0
