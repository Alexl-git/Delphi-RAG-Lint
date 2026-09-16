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

# ---------------------------------------------------------------------------
# CHECK 6 -- the COMMON QUESTIONS table agrees across all three surfaces
#
# The table exists because two grep-fallback audits found agents reaching for
# grep on questions the tool already answers -- eight of ten in the second one,
# every time because the reporter did not know the command. A discoverability
# aid that drifts is worse than none: it teaches a command that no longer works.
# So it is held to the DOCS-IN-SYNC rule like any other surface, in BOTH
# directions -- a question added to --help but not to the docs fails here, and
# so does one dropped from either doc.
#
# Verbs are checked against the CLI dispatch table harvested for check 1, so a
# renamed verb cannot survive in the table.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 6: the COMMON QUESTIONS table' -ForegroundColor Cyan

function Normalize-Q([string]$s) {
  # The three surfaces format the same question differently -- README puts the
  # symbol in backticks, --help does not. Compare MEANING, not punctuation.
  return ((($s -replace '[`*]', '') -replace '[^A-Za-z0-9]+', ' ').Trim().ToLowerInvariant())
}

$helpBlock = ''
if ($helpText -match '(?s)COMMON QUESTIONS(.*?)\r?\nUsage:') { $helpBlock = $Matches[1] }
Check 'the --help COMMON QUESTIONS block is present' ($helpBlock -ne '') `
  'it must lead the banner -- the whole point is that a reader in a hurry sees it first'

# question -> command, from lines shaped "  <question>   drag-lint <verb> ..."
$helpRows = @()
foreach ($m in [regex]::Matches($helpBlock, '(?m)^\s{2}(\S[^\r\n]*?)\s{2,}(drag-lint\s+[a-z][a-z0-9-]*)')) {
  $helpRows += [pscustomobject]@{ Q = (Normalize-Q $m.Groups[1].Value); Verb = ($m.Groups[2].Value -split '\s+')[1] }
}
# Non-emptiness is the control: a harvest that yields nothing makes every
# comparison below trivially true, which is this repo's commonest fail-open.
Check 'the --help table parsed' ($helpRows.Count -ge 10) "$($helpRows.Count) question(s)"

$helpQ = @($helpRows | ForEach-Object { $_.Q } | Sort-Object -Unique)

foreach ($doc in @('README.md', 'docs\AI-USAGE.md')) {
  $path = Join-Path $Repo $doc
  if (-not (Test-Path -LiteralPath $path)) { Check "$doc exists" $false $path; continue }
  $txt  = Get-Content -LiteralPath $path -Raw
  $rows = @()
  foreach ($m in [regex]::Matches($txt, '(?m)^\|\s*([^|]+?)\s*\|\s*`(drag-lint[^`]*)`')) {
    $rows += (Normalize-Q $m.Groups[1].Value)
  }
  $rows = @($rows | Sort-Object -Unique)
  Check "$doc carries the table" ($rows.Count -ge 10) "$($rows.Count) row(s)"

  $missingHere = @($helpQ | Where-Object { $rows -notcontains $_ })
  $extraHere   = @($rows  | Where-Object { $helpQ -notcontains $_ })
  Check "$doc lists every question --help does" ($missingHere.Count -eq 0) `
    ("not in $doc" + ": " + ($missingHere -join ' | '))
  Check "$doc lists no question --help omits" ($extraHere.Count -eq 0) `
    ("only in $doc" + ": " + ($extraHere -join ' | '))
}

# Every verb the table recommends must be a verb the CLI accepts. $dispatch is
# harvested from the source in check 1; a table naming a retired verb is exactly
# the "advises a command it refuses" defect that shipped in 5080478.
$badVerbs = @($helpRows | ForEach-Object { $_.Verb } | Sort-Object -Unique |
              Where-Object { $dispatch -notcontains $_ })
Check 'every verb the table recommends is accepted by the CLI' ($badVerbs.Count -eq 0) `
  ("unknown: " + ($badVerbs -join ', '))

# NEGATIVE CONTROL: the comparison must be capable of noticing a difference.
Check 'negative control: an invented question is not in the set' `
  (-not ($helpQ -contains (Normalize-Q 'How do I summon a dragon?')))

# ---------------------------------------------------------------------------
# CHECK 7 -- every --help verb is NAMED in README.md and docs\AI-USAGE.md
#
# Checks 1-6 hold --help against the CODE and against the COMMON QUESTIONS
# table. Nothing held the two PROSE surfaces against the verb list, yet the
# DOCS-IN-SYNC rule names all three: "--help, README.md, and docs\AI-USAGE.md
# are part of the product".
#
# This closes the gap that rule was written for. Session 70 found --castlib in
# neither README nor AI-USAGE while --help documented it -- and found it BY
# HAND, which is the failure mode: silence. Measured 2026-09-06: --help lists 80
# verbs, README names all 80, AI-USAGE was missing exactly `migrate-dbs` and
# `shared-unit`.
#
# SCOPE IS DELIBERATE: VERBS ONLY, NOT FLAGS. At flag level README lacks 16 and
# AI-USAGE 39 of 144 distinct --flags -- 55 doc lines of churn now, plus a
# maintenance cost on every new flag forever. That is an owner decision with a
# price attached, not a guard to switch on quietly. The counts are recorded here
# so the decision can be made on numbers rather than on appetite.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 7: every --help verb is named in README and AI-USAGE' -ForegroundColor Cyan

# A verb that --help documents but the prose docs deliberately omit goes here,
# WITH a reason, and is asserted in BOTH directions below -- exactly like
# $UndocumentedOnPurpose. That two-way assertion is not ceremony: it caught a
# wrong "fix" in session 70, when convert-reemit's absence looked like the very
# defect this file exists to prevent and documenting it correctly FAILED.
# Empty today, because every help verb is in both docs.
$HelpOnlyOnPurpose = [ordered]@{}

# FAIL-OPEN CONTROL. A help parse that yielded nothing makes every "is it
# documented?" test below trivially true, so this check would PASS while
# asserting nothing. Check 1 asserts this too; it is repeated because THIS
# check's conclusion depends on it independently.
Check 'check 7 has a verb list to work with' ($helpVerbs.Count -gt 20) `
  "($($helpVerbs.Count) verb(s))"

function Doc-Names-Token([string]$haystack, [string]$token) {
  # A word boundary that understands hyphenated verbs: `lint` must NOT be
  # satisfied by `lint-all`, and `index` must not be satisfied by `--index-only`.
  return ($haystack -match ('(^|[^a-z-])' + [regex]::Escape($token) + '([^a-z-]|$)'))
}

$verbDocs = [ordered]@{
  'README.md'        = (Join-Path $Repo 'README.md')
  'docs\AI-USAGE.md' = (Join-Path $Repo 'docs\AI-USAGE.md')
}

foreach ($docName in $verbDocs.Keys) {
  $docPath = $verbDocs[$docName]
  if (-not (Test-Path -LiteralPath $docPath)) {
    Check "$docName exists" $false "not found at $docPath"
    continue
  }
  $docText = Get-Content -LiteralPath $docPath -Raw

  $absent = @($helpVerbs | Where-Object {
    (-not (Doc-Names-Token $docText $_)) -and (-not $HelpOnlyOnPurpose.Contains($_))
  })
  Check "every --help verb is named in $docName" ($absent.Count -eq 0) `
    ("missing: " + ($absent -join ' '))

  # POSITIVE CONTROL: the comparison must be CAPABLE of reporting an absence.
  # A token that cannot be in the doc must come back absent through the SAME
  # matcher -- without it, a matcher that always answers "present" passes.
  $ghost = 'zz-not-a-verb-' + ([guid]::NewGuid().ToString('N').Substring(0,8))
  Check "positive control: an invented verb is reported absent from $docName" `
    (-not (Doc-Names-Token $docText $ghost)) "control token: $ghost"
}

# --- 7a: the exemption list cannot outlive what it exempts, either way -------
# Direction 1: an entry that is no longer a --help verb is stale.
$staleHelpOnly = @($HelpOnlyOnPurpose.Keys | Where-Object { $helpVerbs -notcontains $_ })
Check 'every $HelpOnlyOnPurpose entry is still a --help verb' ($staleHelpOnly.Count -eq 0) `
  $(if ($staleHelpOnly.Count -gt 0) { "stale: $($staleHelpOnly -join ' ')" }
    else { "($($HelpOnlyOnPurpose.Count) exemption(s))" })

# Direction 2: an entry that HAS since been documented in BOTH docs is stale
# too. Without this direction the list quietly degrades into a suppression file.
$nowInDocs = @($HelpOnlyOnPurpose.Keys | Where-Object {
  $v = $_
  $hits = @($verbDocs.Values | Where-Object { Test-Path -LiteralPath $_ } |
            Where-Object { Doc-Names-Token (Get-Content -LiteralPath $_ -Raw) $v })
  $hits.Count -eq $verbDocs.Count
})
Check 'no $HelpOnlyOnPurpose entry is already in both docs' ($nowInDocs.Count -eq 0) `
  ("documented after all: " + ($nowInDocs -join ' '))

if ($HelpOnlyOnPurpose.Count -gt 0) {
  Write-Host '  verbs deliberately absent from the prose docs:' -ForegroundColor DarkGray
  foreach ($k in $HelpOnlyOnPurpose.Keys) {
    Write-Host ("    {0,-22} {1}" -f $k, $HelpOnlyOnPurpose[$k]) -ForegroundColor DarkGray
  }
}
Write-Host ''
Write-Host '-- check 8: the index-schema docs state the real SCHEMA_VERSION' -ForegroundColor Cyan
# WHY THIS EXISTS. On 2026-09-08 docs\INDEX-SCHEMA.md said schema_version 19 and
# docs\INDEXING-AND-DB-ARCHITECTURE.md said 17, against a live 21. Two schema
# revisions -- refs.receiver_text (v20) and refs.external_target (v21) -- were
# undocumented, and the whole comment-prose corpus had landed in string_literals
# without the table's description changing from "one row per string literal".
#
# None of it was caught, because checks 1-7 police --help, README and AI-USAGE
# and NOTHING policed the schema reference -- the document an external consumer
# reads before writing SQL against the index. That is the same silence this
# guard was created to end, in the one file where a wrong answer is acted on
# directly.
#
# Deliberately narrow: a version number is objective and cheap. It does not
# prove the prose is right, but a doc whose stated version matches the code has
# at least been looked at since the last migration, and every drift found on
# 2026-09-08 was accompanied by a stale version line.
$schemaSrc = Join-Path $repo 'src\storage\DRagLint.Storage.Schema.pas'
Check 'schema source present' (Test-Path -LiteralPath $schemaSrc) $schemaSrc
if (Test-Path -LiteralPath $schemaSrc) {
  $mSchema = [regex]::Match((Get-Content -LiteralPath $schemaSrc -Raw), 'SCHEMA_VERSION\s*=\s*(\d+)')
  Check 'SCHEMA_VERSION parsed from source' $mSchema.Success 'the constant moved or was renamed'
  if ($mSchema.Success) {
    $liveSchema = [int]$mSchema.Groups[1].Value
    Write-Host ("  live SCHEMA_VERSION = {0}" -f $liveSchema) -ForegroundColor DarkGray

    # INDEX-SCHEMA.md is the authoritative consumer reference and must be exact.
    $idxDoc = Join-Path $repo 'docs\INDEX-SCHEMA.md'
    Check 'docs\INDEX-SCHEMA.md present' (Test-Path -LiteralPath $idxDoc) $idxDoc
    if (Test-Path -LiteralPath $idxDoc) {
      $idxRaw   = Get-Content -LiteralPath $idxDoc -Raw
      $mStated  = [regex]::Match($idxRaw, '(?i)current schema version[^\r\n]*?\*\*(\d+)\*\*')
      Check 'INDEX-SCHEMA.md states a schema version' $mStated.Success `
        'expected a line like "Current schema version at time of writing: **NN**"'
      if ($mStated.Success) {
        $statedIdx = [int]$mStated.Groups[1].Value
        Check 'INDEX-SCHEMA.md states the REAL schema version' ($statedIdx -eq $liveSchema) `
          "doc says $statedIdx, source says $liveSchema -- a migration shipped without the consumer reference being updated"
      }
      # POSITIVE CONTROL: the matcher must be capable of rejecting a wrong number.
      $ctlRaw = $idxRaw -replace '(?i)(current schema version[^\r\n]*?\*\*)\d+(\*\*)', "`${1}999`${2}"
      $mCtl   = [regex]::Match($ctlRaw, '(?i)current schema version[^\r\n]*?\*\*(\d+)\*\*')
      Check 'POSITIVE CONTROL: a planted wrong version is detected' `
        ($mCtl.Success -and ([int]$mCtl.Groups[1].Value -ne $liveSchema)) `
        'if this passes silently the check above can never fail'
    }

    # INDEXING-AND-DB-ARCHITECTURE.md carries an "Applies to" banner. Its PROSE
    # is explicitly marked indicative rather than authoritative, so only the
    # banner is policed -- holding the whole document to the schema would fail
    # permanently and teach everyone to skip it.
    $archDoc = Join-Path $repo 'docs\INDEXING-AND-DB-ARCHITECTURE.md'
    if (Test-Path -LiteralPath $archDoc) {
      # Tolerant of where the bold falls: the banner writes
      # `**schema_version 21**` (whole phrase bold), an earlier revision wrote
      # `schema_version **17**` (number bold). Both are the same claim, and a
      # matcher that only accepts one shape fails on formatting rather than on
      # drift -- which is a guard crying wolf, the thing that teaches people to
      # ignore it.
      $mArch = [regex]::Match((Get-Content -LiteralPath $archDoc -Raw), '(?i)schema_version[^\d\r\n]{0,4}(\d+)')
      Check 'INDEXING-AND-DB-ARCHITECTURE.md banner states a schema version' $mArch.Success `
        'expected "schema_version NN" in the Applies-to banner'
      if ($mArch.Success) {
        Check 'INDEXING-AND-DB-ARCHITECTURE.md banner is current' ([int]$mArch.Groups[1].Value -eq $liveSchema) `
          ("banner says {0}, source says {1}" -f $mArch.Groups[1].Value, $liveSchema)
      }
    }
  }
}


# ---------------------------------------------------------------------------
# CHECK 9 -- every accepted FLAG is in --help, and the prose cannot name a
#            flag that is not
#
# WHY THIS EXISTS. Checks 1 and 7 police VERBS both ways; flags were policed
# only incidentally (check 4 parses $helpFlags to spot stale "undocumented"
# prose). The gap was not theoretical: CLAUDE.md's DOCS-IN-SYNC rule was
# written after an afternoon found the ENTIRE autofix flag set -- --file --fix
# --fix-line --fix-rule --apply --no-preprocess -- accepted by the CLI and
# absent from --help, so a user reading the banner could not discover autofix
# at all. Measured when this check was written: 19 more flags in exactly that
# state, and the prose naming 3 flags the banner denies.
#
# WHAT IT ENFORCES, and what it deliberately does NOT.
#   F1  every accepted flag appears in --help (or is exempt, with a reason)
#   F2  every --help flag is actually accepted (no phantoms)
#   F3  every flag README/AI-USAGE name appears in --help  <- REVERSE, total
#   F4  every PROMOTED flag is named in both prose docs    <- FORWARD, narrow
#
# F4 is narrow ON PURPOSE. The strict shape would be "every one of the ~147
# flags in all three documents": ~50 doc cells today and two more per flag
# forever, in documents whose job is orientation. README:587 says in its own
# voice that "the complete, authoritative flag list for every verb is
# `drag-lint --help`", and CLAUDE.md's table holds README and AI-USAGE to
# verbs, counts and paths -- not flag completeness. A guard that fails because
# --parent-pid is missing from README is a guard someone weakens, and this repo
# says a rule that is on but ignored is worse than one that is off. So F4 fails
# only on flags the BANNER ITSELF promotes: the COMMON QUESTIONS block, the
# Output/CI block, and flags appearing on >= 5 verb lines.
#
# PER-VERB IS NOT CHECKABLE, and the CLAUDE.md table's "on that verb's line"
# is therefore NOT enforced here. ParseArgs is verb-agnostic: almost every flag
# is parsed with no reference to Result.Command, so the code does not know
# which verb accepts which flag -- the Do<Verb> routine that reads the TArgs
# field does. Attributing flags from --help by position is worse than useless:
# measured, a naive "flags between this verb line and the next" parse
# attributes --rebuild to resolve-dbs and --fix to exceptions-sync, because
# continuation prose names other verbs' flags freely. Flags are therefore
# enforced as SETS HERE.
#
# THE PER-VERB AXIS NOW HAS A TRUTH SOURCE, and it is a separate runner:
# tests\autotest\lib\CliFlagVerbMap.ps1 derives flag -> TArgs field -> reading
# routine -> verb from source alone, and tests\autotest\run_flag_verb_map.ps1
# proves that derivation and reports the gap (MEASURED 2026-09-15: 439 cells
# consumed, 124 of them absent from their verb's own --help block, across 33
# verbs). It is deliberately NOT folded into this check: that gap is a banner-
# DESIGN decision the owner has not taken, so it is ratcheted and printed
# rather than failed, and this check must stay failable on the things that are
# already agreed. A recorded number left in a header is how "144 flags" reached
# a brief three releases after it stopped being true -- so if you re-measure,
# re-measure there, not here.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 9: flags' -ForegroundColor Cyan

# Its OWN regex, deliberately not check 4's $helpFlags. Two widenings are
# needed here -- '*' after the first letter (or --n, which IS in help, reads as
# undocumented) and [A-Za-z] on both sides (or --clientProcessId is invisible)
# -- and check 4's population is keyed to its narrower one. Sharing would mean
# this check silently changes which stale claims check 4 examines, so the two
# are kept independent.
$FlagRx  = '--[A-Za-z][A-Za-z0-9-]*'
# Prose must END on an alphanumeric: README wraps '--scan-libraries-' across a
# line break, and a trailing hyphen is a fragment, never a flag.
#
# CORRECTED 2026-09-16, found by F5 on its first run. The old form
# '--[A-Za-z][A-Za-z0-9-]*[A-Za-z0-9]' required at least TWO characters after
# the dashes, so a SINGLE-LETTER flag was invisible to the prose scan. `--n`
# (bench-context) is named in BOTH docs -- README.md:661 and AI-USAGE.md:625 --
# and F5 still reported it missing from both, because the matcher could not
# spell it. Documenting it would not have helped; the doc already did.
#
# The single-letter case is now an optional tail, and the trailing hyphen is
# excluded by a lookahead instead of by a mandatory final character, which keeps
# the original protection: a wrapped '--scan-libraries-' still does not match as
# a flag, and prose's ' -- ' em-dash still cannot match because a letter must
# follow the dashes immediately.
$ProseRx = '--[A-Za-z](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?![A-Za-z0-9-])'

function Get-FlagSet([string]$Text, [string]$Rx) {
  $s = New-Object System.Collections.Generic.HashSet[string]
  foreach ($m in [regex]::Matches($Text, $Rx)) { [void]$s.Add($m.Value) }
  return ,$s
}

# Flags ParseArgs accepts that --help deliberately does NOT print. THREE
# admissible classes, and an entry must cite one:
#   (a) flag of a verb that is itself in $UndocumentedOnPurpose
#   (b) back-compat ALIAS whose canonical form IS in --help
#   (c) test-harness entry point (pre-dispatch self-test)
# Anything else is a defect -- document it on the verb's line. Class (b) is the
# one that can absorb anything ("it's an alias of the default"), so it is
# reviewed at each release exactly as $UndocumentedOnPurpose is.
$FlagUndocumentedOnPurpose = [ordered]@{
  '--expr'            = '(a) dump-pp-eval expression; that verb is itself exempt'
  '--from-block'      = '(a) convert-reemit input; that verb is itself exempt'
  '--selftest-fts5'   = '(c) pre-dispatch self-test (Run, ParamStr(1)), driven by a runner under tests\'
  '--selftest-schema' = '(c) pre-dispatch self-test, same'
  '--use-ignore'      = '(b) no-op alias of the DEFAULT; --no-use-ignore is the documented switch'
  '--dir'             = '(b) alias of the positional <path> every verb documents'
  '--target'          = '(b) alias of the positional <target> on compile-check/ghost-check/check-unit'
}
# Not parsed through the `A = '...'` chain, so the scan cannot see them; listed
# by name WITH the handler that must still exist, so deleting the handler makes
# this stale rather than silently fine.
$StructuralFlags = [ordered]@{
  '--help'    = 'IsHelpToken'
  '--version' = "Result.Command = '--version'"
}
# Promoted flags a prose doc omits on purpose. Empty, and two-way asserted so
# it cannot rot into a suppression list.
$FlagHelpOnlyOnPurpose = [ordered]@{}

# --- the accepted set: the ParseArgs chain is authoritative and total --------
# It is one flat `else if A = '<flag>'` chain ending in
# `raise Exception.CreateFmt('Unknown argument: %s', [A])`, so its literals ARE
# the accepted set. Restricted to `A = '...'` rather than any '--x' literal
# because that span also carries comments quoting args.push('--stdio') and
# prose about `--rule --help`; a bare-literal sweep reads those as flags.
$paSpan = [regex]::Match($cliSrc, '(?s)function ParseArgs\s*:\s*TArgs;.*?\r?\nend; // function')
Check 'check 9: the ParseArgs span was located' $paSpan.Success `
  'the accepted-flag scan has nothing to read -- was ParseArgs renamed or its closing comment changed?'

$accepted = New-Object System.Collections.Generic.HashSet[string]
if ($paSpan.Success) {
  foreach ($m in [regex]::Matches($paSpan.Value, "\bA\s*=\s*'($FlagRx)'"))      { [void]$accepted.Add($m.Groups[1].Value) }
  foreach ($m in [regex]::Matches($paSpan.Value, "A\.StartsWith\('($FlagRx)'")) { [void]$accepted.Add($m.Groups[1].Value) }
}
foreach ($m in [regex]::Matches($cliSrc, "ParamStr\(1\)\s*=\s*'($FlagRx)'"))    { [void]$accepted.Add($m.Groups[1].Value) }
foreach ($k in $StructuralFlags.Keys) { [void]$accepted.Add($k) }

$helpSet = Get-FlagSet $helpText $FlagRx

# NON-EMPTINESS CONTROLS. Rewrite ParseArgs as a table or a case, or rename
# PrintHelp, and both scans go quiet -- and a quiet scan passes every other
# assertion in this check. Same bound check 1 puts on the dispatch scan.
Check 'check 9: accepted-flag set is populated' ($accepted.Count -gt 100) `
  "only $($accepted.Count) accepted flag(s) parsed -- the chain scan is broken, not the CLI"
Check 'check 9: --help flag set is populated' ($helpSet.Count -gt 100) `
  "only $($helpSet.Count) flag(s) in --help"

# --- F0: the exe is a BUILT ARTIFACT; source and exe must agree --------------
# third_party\dll-win64\drag-lint.exe is not tracked, so this check compares a
# built artifact against source on disk -- two points in time. Without F0, a
# PrintHelp edit with no rebuild reads as doc drift and sends the reader
# hunting through the docs. With it, the failure says "rebuild first".
$phSpan = [regex]::Match($cliSrc, '(?s)procedure PrintHelp.*?function ParseArgs')
Check 'check 9: the PrintHelp span was located' $phSpan.Success 'cannot compare source help against the exe'
if ($phSpan.Success) {
  $srcHelpSet = Get-FlagSet $phSpan.Value $FlagRx
  $f0Src = @($srcHelpSet | Where-Object { -not $helpSet.Contains($_) }) | Sort-Object
  $f0Exe = @($helpSet    | Where-Object { -not $srcHelpSet.Contains($_) }) | Sort-Object
  Check 'F0 the deployed exe''s --help matches PrintHelp in source' `
    (($f0Src.Count -eq 0) -and ($f0Exe.Count -eq 0)) `
    ("REBUILD FIRST -- in source only: $($f0Src -join ' ') | in the exe only: $($f0Exe -join ' ')")
}

# --- F1: accepted => documented ---------------------------------------------
$f1 = @($accepted | Where-Object {
          -not $helpSet.Contains($_) -and -not $FlagUndocumentedOnPurpose.Contains($_)
        }) | Sort-Object
Check 'F1 every accepted flag appears in --help (or is exempt)' ($f1.Count -eq 0) `
  ("$($f1.Count) accepted but undiscoverable: " + ($f1 -join ' '))

# --- F2: documented => accepted (no phantoms) -------------------------------
$f2 = @($helpSet | Where-Object { -not $accepted.Contains($_) }) | Sort-Object
Check 'F2 every --help flag is actually accepted' ($f2.Count -eq 0) `
  ("$($f2.Count) phantom(s) -- --help offers what ParseArgs rejects: " + ($f2 -join ' '))

# --- F1x / F2x: the exemption table cannot outlive what it exempts ----------
$exStale = @($FlagUndocumentedOnPurpose.Keys | Where-Object { -not $accepted.Contains($_) })
Check 'F1x every flag exemption is still accepted by the CLI' ($exStale.Count -eq 0) `
  ("stale entr(ies) -- the flag is gone, delete the exemption: " + ($exStale -join ' '))
$exNowDoc = @($FlagUndocumentedOnPurpose.Keys | Where-Object { $helpSet.Contains($_) })
Check 'F2x no flag exemption is now IN --help' ($exNowDoc.Count -eq 0) `
  ("documented after all, delete the exemption: " + ($exNowDoc -join ' '))
$structGone = @($StructuralFlags.Keys | Where-Object { $cliSrc -notmatch [regex]::Escape($StructuralFlags[$_]) })
Check 'F2x every structural flag''s handler still exists in source' ($structGone.Count -eq 0) `
  ("handler string no longer found for: " + ($structGone -join ' '))

foreach ($k in $FlagUndocumentedOnPurpose.Keys) {
  Write-Host ("      [NOTE] flag not in --help on purpose: {0} -- {1}" -f $k, $FlagUndocumentedOnPurpose[$k]) -ForegroundColor DarkGray
}

# --- F3: the prose may not name a flag --help denies ------------------------
# REVERSE and total: no list to maintain, and it catches the class that keeps
# happening -- prose running ahead of, or behind, the banner. Scoped to README
# and AI-USAGE exactly as check 7 is: docs\PLAN-* and docs\INBOX-* name
# --allow-missing-db, which was specified and deliberately NOT shipped, and
# sweeping those would fail the battery on a decision correctly recorded.
$proseDocs = [ordered]@{
  'README.md'        = (Join-Path $Repo 'README.md')
  'docs\AI-USAGE.md' = (Join-Path $Repo 'docs\AI-USAGE.md')
}
$proseSets = @{}
foreach ($name in $proseDocs.Keys) {
  $p = $proseDocs[$name]
  if (-not (Test-Path -LiteralPath $p)) { Check "check 9: $name exists" $false $p; continue }
  $set = Get-FlagSet (Get-Content -LiteralPath $p -Raw) $ProseRx
  $proseSets[$name] = $set
  Check "check 9: $name flag list parsed" ($set.Count -gt 50) "($($set.Count) flag(s))"
  $bad = @($set | Where-Object { -not $helpSet.Contains($_) }) | Sort-Object
  Check "F3 every flag $name names is in --help" ($bad.Count -eq 0) `
    ("$($bad.Count) named in prose but not in the banner: " + ($bad -join ' '))
}

# --- F4: the PROMOTED set must be in both prose docs ------------------------
# DERIVED from the banner, never hand-listed, so it tracks the banner instead
# of rotting beside it.
$helpLines = $helpText -split "`r?`n"
$promoted  = New-Object System.Collections.Generic.HashSet[string]
$inCQ = $false; $inCI = $false
foreach ($l in $helpLines) {
  if ($l -match '^\s*COMMON QUESTIONS') { $inCQ = $true;  continue }
  if ($l -match '^\s*Output/CI')        { $inCI = $true;  continue }
  # A block ends at the next section header OR the next verb line. The verb-line
  # clause is load-bearing: the Output/CI block is followed by MORE verb lines,
  # not a header, and a parser that only closed on a header swallowed 8 verbs
  # into "CI" and promoted 7 flags that nothing promotes.
  if (($inCQ -or $inCI) -and ($l -match '^\s{2}drag-lint\s+\S' -or $l -match '^[A-Z][A-Za-z /]+:\s*$')) {
    $inCQ = $false; $inCI = $false
  }
  if ($inCQ -or $inCI) { foreach ($m in [regex]::Matches($l, $FlagRx)) { [void]$promoted.Add($m.Value) } }
}
$verbLines = @($helpLines | Where-Object { $_ -match '^\s{2}drag-lint\s+\S' })
Check 'check 9: verb lines parsed for cross-cutting flags' ($verbLines.Count -gt 50) `
  "($($verbLines.Count) verb line(s))"
$freq = @{}
foreach ($l in $verbLines) {
  $seen = New-Object System.Collections.Generic.HashSet[string]
  foreach ($m in [regex]::Matches($l, $FlagRx)) { [void]$seen.Add($m.Value) }
  foreach ($x in $seen) { $freq[$x] = 1 + $freq[$x] }
}
# 5 is a knob, so the derived set is PRINTED every run -- a threshold nobody can
# see is a threshold nobody revisits.
foreach ($x in @($freq.GetEnumerator() | Where-Object { $_.Value -ge 5 } | ForEach-Object { $_.Key })) {
  [void]$promoted.Add($x)
}
[void]$promoted.Remove('--help')
Check 'check 9: the promoted set is a sane size' (($promoted.Count -ge 20) -and ($promoted.Count -le 60)) `
  "promoted=$($promoted.Count) -- outside 20..60 means the block parse broke, not that the banner changed"
Write-Host ("      [NOTE] promoted flags ({0}): {1}" -f $promoted.Count, (($promoted | Sort-Object) -join ' ')) -ForegroundColor DarkGray

foreach ($name in $proseSets.Keys) {
  $missing = @($promoted | Where-Object {
                 -not $proseSets[$name].Contains($_) -and -not $FlagHelpOnlyOnPurpose.Contains($_)
               }) | Sort-Object
  Check "F4 $name names every flag --help promotes" ($missing.Count -eq 0) `
    ("$($missing.Count) promoted flag(s) a reader of this doc cannot find: " + ($missing -join ' '))
}
$hoStale = @($FlagHelpOnlyOnPurpose.Keys | Where-Object { -not $promoted.Contains($_) })
Check 'F4x every $FlagHelpOnlyOnPurpose entry is still promoted' ($hoStale.Count -eq 0) `
  ("no longer promoted, delete the entry: " + ($hoStale -join ' '))

# --- F5: TOTAL flag coverage, not just the promoted subset ------------------
# F4 polices a curated subset (the COMMON QUESTIONS / Output-CI blocks plus any
# flag on 5+ verb lines, 20..60 of them). F5 is the whole banner.
#
# WHY THIS IS ON NOW, AFTER BEING PARKED SINCE 2026-09-05. The note
# INBOX-docs-guard-checks-help-only parked it as "an owner decision with a
# price, not because it is hard": measured then, README lacked 16 flags and
# AI-USAGE lacked 39, so turning it on cost 55 doc lines up front plus a
# maintenance cost on every new flag forever.
#
# Re-measured 2026-09-16: 163 flags in --help, **0 missing from either doc**.
# The sessions 93-97 docs work closed the debt as a side effect, so the up-front
# price is now nil and only the maintenance cost remains -- which is precisely
# the discipline THE DOCS-IN-SYNC RULE in CLAUDE.md already demands, and which
# F1-F4 already impose on verbs and on the promoted subset. Owner ruled to turn
# it on 2026-09-16.
#
# A CAUTION ABOUT THAT MEASUREMENT, because it was wrong the first time. The
# first pass matched flags with `--[a-z][a-z0-9-]*` and reported ONE missing
# flag, `--client`. There is no such flag: the regex truncated
# `--clientProcessId` at the capital P and then failed to find the stump in the
# docs. $FlagRx below admits camelCase for exactly this reason. A flag regex
# that cannot spell every flag reports doc gaps that do not exist -- and would
# hide real ones behind a name it mangles the same way.
foreach ($name in $proseSets.Keys) {
  $allMissing = @($helpSet | Where-Object {
                    -not $proseSets[$name].Contains($_) -and -not $FlagHelpOnlyOnPurpose.Contains($_)
                  }) | Sort-Object
  Check "F5 $name names EVERY flag in --help ($($helpSet.Count) flag(s))" ($allMissing.Count -eq 0) `
    ("$($allMissing.Count) flag(s) in the banner that this doc never names: " + ($allMissing -join ' '))
}

# --- POSITIVE CONTROLS ------------------------------------------------------
# Every assertion above is of the form "this set difference is empty", and an
# empty set is exactly what a BROKEN scan produces. These four plant a token
# and require the matcher to find it. They mutate in-memory copies, the way
# checks 7 and 8 do; no temp files.
$guid = [Guid]::NewGuid().ToString('N').Substring(0, 8)
$tok  = "--zz-planted-$guid"

$ctlSrc = $paSpan.Value + "`r`n  else if A = '$tok' then`r`n"
$ctlAcc = New-Object System.Collections.Generic.HashSet[string]
foreach ($m in [regex]::Matches($ctlSrc, "\bA\s*=\s*'($FlagRx)'")) { [void]$ctlAcc.Add($m.Groups[1].Value) }
Check 'CONTROL F1 a planted accepted flag is seen as undocumented' `
  ($ctlAcc.Contains($tok) -and -not $helpSet.Contains($tok)) `
  'the accepted-flag scan cannot see a new chain entry, so F1 can never fail'

$ctlHelpSet = Get-FlagSet ($helpText + " [$tok]") $FlagRx
Check 'CONTROL F2 a planted --help flag is seen as a phantom' `
  ($ctlHelpSet.Contains($tok) -and -not $accepted.Contains($tok)) `
  'the --help scan cannot see a new token, so F2 can never fail'

# CONTROL F5: F5 asserts a set difference is EMPTY, and an empty difference is
# also what a broken --help scan produces. Plant a flag into the banner copy and
# require F5's comparison to report it as missing from a doc that cannot contain
# it. Without this, F5 passes forever if $helpSet ever comes back empty.
if ($proseSets.ContainsKey('README.md')) {
  $ctlHelpF5 = Get-FlagSet ($helpText + " [$tok]") $FlagRx
  $ctlF5Missing = @($ctlHelpF5 | Where-Object {
                      -not $proseSets['README.md'].Contains($_) -and -not $FlagHelpOnlyOnPurpose.Contains($_)
                    })
  Check 'CONTROL F5 a planted --help flag is seen as undocumented' `
    ($ctlF5Missing -contains $tok) `
    'F5 cannot detect a banner flag absent from the prose, so it can never fail'
}

if ($proseSets.ContainsKey('README.md')) {
  $ctlProse = Get-FlagSet ((Get-Content -LiteralPath $proseDocs['README.md'] -Raw) + " ``$tok``") $ProseRx
  Check 'CONTROL F3 a planted prose flag is seen as not-in---help' `
    ($ctlProse.Contains($tok) -and -not $helpSet.Contains($tok)) `
    'the prose scan cannot see a new token, so F3 can never fail'
}

# --fix is in COMMON QUESTIONS, so it is promoted by construction; removing it
# from a copy of the doc must make F4 notice.
if ($proseSets.ContainsKey('docs\AI-USAGE.md') -and $promoted.Contains('--fix')) {
  $ctlAiText = (Get-Content -LiteralPath $proseDocs['docs\AI-USAGE.md'] -Raw) -replace '--fix\b', ''
  $ctlAiSet  = Get-FlagSet $ctlAiText $ProseRx
  Check 'CONTROL F4 removing a promoted flag from the doc is detected' `
    (-not $ctlAiSet.Contains('--fix')) `
    'F4 cannot detect a promoted flag going missing'
} else {
  Check 'CONTROL F4 --fix is in the promoted set' $false `
    '--fix is no longer promoted, so this control proves nothing -- pick another promoted flag'
}

# ---------------------------------------------------------------------------
# CHECK 10 -- every accepted SUBcommand is in --help
# ---------------------------------------------------------------------------
# WHY THIS EXISTS, AND WHY CHECK 1 COULD NEVER HAVE CAUGHT IT.
#
# Check 1 enumerates TOP-LEVEL verbs: `Args.Command = 'x'` in Run against
# `^  drag-lint <verb>` in the banner. `query` is in both, so check 1 passes --
# and passed, for months, while `query descendants` appeared ZERO times in
# --help despite shipping and being used by the converter team's editor.
#
# That is this guard's OWN founding failure ("four shipping verbs missing from
# --help") repeating one level down, inside the guard written to prevent it.
# The structural lesson is the point: an axis a guard does not enumerate is an
# axis that drifts silently, and adding the missing banner line WITHOUT adding
# this check would leave the next subcommand just as free to go missing.
#
# The verb -> subcommand map is derived FROM SOURCE by
# tests\autotest\lib\CliFlagVerbMap.ps1 (Get-CliVerbSubcommandMap), the same
# lexer + dispatch-closure machinery check 9 uses for flags. See that function's
# header for the binding rule and for the two shapes it deliberately excludes.
Write-Host ''
Write-Host '-- check 10: subcommands' -ForegroundColor Cyan

. (Join-Path $Repo 'tests\autotest\lib\CliFlagVerbMap.ps1')
$subMap = Get-CliVerbSubcommandMap -CliPath $cliPas

# Non-emptiness first: every assertion below is "this set difference is empty",
# and a broken derivation produces exactly that for free.
$subTotal = @($subMap.VerbSubs.Keys | ForEach-Object { $subMap.VerbSubs[$_] }).Count
Check 'check 10: subcommand map derived' ($subTotal -gt 20) `
  "($($subMap.VerbSubs.Keys.Count) verb(s) take subcommands; $subTotal literal(s))"
Check 'check 10: every subcommand literal bound to a verb' ($subMap.Unbound.Count -eq 0) `
  $(if ($subMap.Unbound.Count -gt 0) { "unbound: $($subMap.Unbound -join ' ')" } else { '' })

# "Documented" = a reader of --help can find the pair. Deliberately looser than
# check 1's `^  drag-lint <verb>` anchor: a subcommand named only in the COMMON
# QUESTIONS block IS discoverable, and failing it would be a false RED.
function Test-SubDocumented([string]$Verb, [string]$Sub) {
  return $script:helpText -match ("(?m)\bdrag-lint\s+" + [regex]::Escape($Verb) + "\s+" + [regex]::Escape($Sub) + "\b")
}

# --- 10a: accepted but undocumented ----------------------------------------
# A subcommand of a verb that is itself $UndocumentedOnPurpose inherits that
# exemption -- selftest's fifteen are the test harness's internals, and
# demanding --help document them would be demanding the opposite of check 1's
# stated line between "the product's surface" and "its test harness". No second
# exemption list: the verb's own entry is the ruling.
$subMissing = New-Object System.Collections.Generic.List[string]
$subSkipped = New-Object System.Collections.Generic.List[string]
$subChecked = 0
foreach ($verb in $subMap.VerbSubs.Keys) {
  if ($UndocumentedOnPurpose.Contains($verb)) {
    $subSkipped.Add("$verb ($($subMap.VerbSubs[$verb].Count))")
    continue
  }
  foreach ($sub in $subMap.VerbSubs[$verb]) {
    $subChecked++
    if (-not (Test-SubDocumented $verb $sub)) { $subMissing.Add("$verb $sub") }
  }
}
Check 'every subcommand the CLI accepts is named in --help' ($subMissing.Count -eq 0) `
  $(if ($subMissing.Count -gt 0) { "undocumented: $($subMissing -join ', ')" } else { "($subChecked checked)" })
if ($subMissing.Count -gt 0) {
  Write-Host '        ^ the CLI accepts a SUBcommand that --help never names. Check 1 cannot' -ForegroundColor Yellow
  Write-Host '          see this: it enumerates top-level verbs only, and the parent verb IS' -ForegroundColor Yellow
  Write-Host '          documented, so check 1 passes while the subcommand stays invisible.' -ForegroundColor Yellow
  Write-Host '          Add it to PrintHelp in src\cli\DRagLint.CLI.pas, then REBUILD -- this' -ForegroundColor Yellow
  Write-Host '          check reads the EXE''s help, not the source.' -ForegroundColor Yellow
}

# --- 10b: the exemption is a verb-level ruling, and must still hold ----------
foreach ($s in $subSkipped) {
  Write-Host ("  [NOTE] subcommands NOT required in --help: {0} -- parent verb is `$UndocumentedOnPurpose" -f $s) -ForegroundColor DarkGray
}

# --- 10c: POSITIVE CONTROLS -------------------------------------------------
# Without these, 10a passes against a derivation that returns nothing and
# against a matcher that calls everything documented.
$subGuid = [Guid]::NewGuid().ToString('N').Substring(0, 8)
Check 'CONTROL S1 a synthetic subcommand is seen as UNDOCUMENTED' `
  (-not (Test-SubDocumented 'query' ("zz-planted-$subGuid"))) `
  'the matcher calls everything documented, so 10a can never fail'

# The other direction, and the one that matters most: this check must not be a
# guard that always fails. A subcommand that IS in the banner has to pass.
$ctlDocumented = @('query find-callers', 'export enums', 'workspace status')
$ctlBad = @($ctlDocumented | Where-Object {
              $parts = $_ -split ' '
              -not (Test-SubDocumented $parts[0] $parts[1])
            })
Check 'CONTROL S2 a documented subcommand classifies as DOCUMENTED' ($ctlBad.Count -eq 0) `
  $(if ($ctlBad.Count -gt 0) { "matcher failed on: $($ctlBad -join ', ')" } else { "($($ctlDocumented.Count) checked)" })

# And the derivation must really be reading the dispatch chain: the verb we know
# takes subcommands must carry the ones we know it dispatches.
$ctlQuery = @('find-callers', 'ancestors', 'typecat')
$ctlQMiss = @($ctlQuery | Where-Object { $subMap.VerbSubs['query'] -notcontains $_ })
Check 'CONTROL S3 the derivation binds known subcommands to query' ($ctlQMiss.Count -eq 0) `
  $(if ($ctlQMiss.Count -gt 0) { "derivation missed: $($ctlQMiss -join ' ')" } else { "(query: $($subMap.VerbSubs['query'].Count) subcommand(s))" })

foreach ($verb in $subMap.VerbSubs.Keys) {
  Write-Host ("      [NOTE] {0}: {1}" -f $verb, ($subMap.VerbSubs[$verb] -join ' ')) -ForegroundColor DarkGray
}

Write-Host ''
if ($script:Failed) { Write-Host 'DOCS SYNC GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'DOCS SYNC GUARD: PASS' -ForegroundColor Green
exit 0
