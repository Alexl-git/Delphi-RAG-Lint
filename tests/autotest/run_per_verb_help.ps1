<#
  pending_per_verb_help.ps1 -- INBOX `per-verb-help-fatals`.

  THE DEFECT. `drag-lint <verb> --help` FATALed with exit 3 on EVERY verb
  measured (query, lint, index, rules, outline, resolve-dbs, lint-all, usages,
  document). `--help` reached the arg loop as an unrecognised token and hit
  `raise Exception.CreateFmt('Unknown argument: %s')`, so the single most
  natural discovery move a user makes answered with a stack-trace-shaped FATAL
  that reads as "this verb is broken".

  THE SECOND HALF, found while probing and not in the original note: the short
  forms were WORSE, not merely equal. `-h` and `-?` do not start with `--`, so
  the `(Result.Path = '') and (not A.StartsWith('--'))` branch swallowed them as
  a POSITIONAL PATH -- `drag-lint lint -h` answered
  `ERROR: path does not exist: -h`, exit 2. A user reads that as "help is not a
  thing here", and a wrapper script reads exit 2 as "the verb ran and found
  nothing". Both forms are pinned below for that reason.

  WHY THE ASSERTION IS THE USAGE LINE AND NOT THE VERB NAME. The note's stated
  verification was "prints something containing that verb's name". Measured,
  that is VACUOUS for at least one verb: the banner's every line begins
  `drag-lint`, so an output containing "lint" proves nothing about `lint`. The
  assertion here is that the banner carries a `  drag-lint <verb>` USAGE LINE
  for the verb asked about, which is non-vacuous and is a second, per-verb check
  on the completeness the docs-sync guard polices repo-wide.

  WHAT IS NOT CLAIMED. This does not test a per-verb help SYSTEM. The fix routes
  every form to the SAME whole banner; the note deferred per-verb text as a
  separate product decision with its own docs-sync cost. C1-C3 below exist so
  that a fix which stopped crashing by SWALLOWING every unrecognised token
  cannot pass.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }

$exePath = (Resolve-Path $Exe).Path

function RunExe([string[]]$ExeArgs) {
  $o = (& $exePath @ExeArgs 2>&1 | Out-String)
  return @{ Out = $o; Code = $LASTEXITCODE }
}

# The verbs the note measured, plus lint-all / usages / document -- chosen
# because each already owns at least one banner usage line, so a miss here is a
# help-routing failure and never a banner gap masquerading as one.
$verbs = @('query','lint','index','rules','outline','resolve-dbs','lint-all','usages','document')

Push-Location C:\TEMP
try {
  # ---- precondition: the no-verb banner still works, and is what we compare to.
  $base = RunExe @('--help')
  Check 'A0  `drag-lint --help` (no verb) exits 0' ($base.Code -eq 0) "exit $($base.Code)"
  Check 'A0b the no-verb banner carries the version header' `
        ($base.Out -match 'Delphi-RAG-Lint: symbol-aware index') 'header line missing'

  # ---- A: <verb> --help exits 0 and shows that verb's usage line.
  foreach ($v in $verbs) {
    $r = RunExe @($v, '--help')
    Check "A   ``$v --help`` exits 0" ($r.Code -eq 0) `
          ("exit $($r.Code): " + (($r.Out -split "`r?`n" | Where-Object { $_ -match '\S' } | Select-Object -First 2) -join ' | '))
    $hasLine = ($r.Out -split "`r?`n") | Where-Object { $_ -match ("^\s+drag-lint " + [regex]::Escape($v) + "(\s|$)") }
    Check "A   ``$v --help`` prints a 'drag-lint $v' usage line" ([bool]$hasLine) `
          'no usage line for this verb in the output'
  }

  # ---- B: the short forms, which were swallowed as a positional path.
  foreach ($v in @('lint','query','index')) {
    foreach ($f in @('-h','-?')) {
      $r = RunExe @($v, $f)
      Check "B   ``$v $f`` exits 0" ($r.Code -eq 0) "exit $($r.Code)"
      Check "B   ``$v $f`` is NOT taken as a positional path" `
            ($r.Out -notmatch 'path does not exist') 'swallowed by the Path branch'
    }
  }

  # ---- C: --help anywhere in the line, not only immediately after the verb.
  $r = RunExe @('lint','--json','--help')
  Check 'C   `lint --json --help` exits 0 (help wins mid-line)' ($r.Code -eq 0) "exit $($r.Code)"
  $r = RunExe @('query','find-callers','--help')
  Check 'C   `query find-callers --help` exits 0 (after a subcommand)' ($r.Code -eq 0) "exit $($r.Code)"

  # ---- POSITIVE CONTROLS. Without these, a fix that recognised EVERY
  #      unrecognised token as help would pass every assertion above.
  foreach ($v in @('query','lint')) {
    $r = RunExe @($v, '--zzz-not-a-flag')
    Check "C1  ``$v --zzz-not-a-flag`` STILL fails (exit <> 0)" ($r.Code -ne 0) "exit $($r.Code)"
    Check "C1  ``$v --zzz-not-a-flag`` STILL names the unknown argument" `
          ($r.Out -match 'Unknown argument') $r.Out
  }
  # A near-miss token: close enough to help to be caught by a sloppy prefix or
  # substring test, and it must not be. NOTE the assertion is "did NOT print the
  # banner", not "exited non-zero" -- measured, `rules -help` exits 0 on the
  # UNFIXED build because `rules` ignores its positional argument entirely, so an
  # exit-code proxy here would fail against correct code and prove nothing.
  foreach ($t in @('--helpme','--h','-help','--help-me','-hh')) {
    $r = RunExe @('rules', $t)
    Check "C2  ``rules $t`` does NOT print the help banner" `
          ($r.Out -notmatch 'Delphi-RAG-Lint: symbol-aware index') 'near-miss token routed to help'
  }
  # An unknown VERB keeps its own distinct answer (exit 2 + banner), which is
  # not the same path as an unknown FLAG and must not be collapsed into help.
  $r = RunExe @('zzz-not-a-verb')
  Check 'C3  an unknown VERB still exits 2' ($r.Code -eq 2) "exit $($r.Code)"
  Check 'C3  an unknown VERB still says so' ($r.Out -match 'unknown command') $r.Out
}
finally { Pop-Location }

if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
