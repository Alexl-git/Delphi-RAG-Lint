<#
run_compile_check_resolves_db.ps1 -- compile-check must not throw away a compile
it already ran just because it has nowhere to CACHE the result.

THE DEFECT THIS PINS, measured 2026-09-13 from a live IDE session. The plugin
issues

    drag-lint compile-check <project.dproj> --format json

with no --db, because every other verb it drives resolves the database from the
manifest. compile-check did not. It ran the entire compile, then hit
NoDbResolved and returned exit 2 with a 256-byte error message instead of the
findings. The plugin logged

    CompileDiagnose(async): exit=2 outLen=256
    CompileDiagnose(async): parsed=False E=0 W=0 H=0

and E=0 W=0 H=0 is INDISTINGUISHABLE FROM A CLEAN PROJECT. Auto-compile-on-save
had been dead for every project whose DB was not passed explicitly, and the
owner's own broken edit -- a property naming a getter he had just commented out,
which dcc reports as E2168 -- was never surfaced. `resolve-dbs --project`
resolved that same project's DB without complaint the whole time.

TWO INDEPENDENT CHANGES, and this guard holds both:
  1. compile-check resolves its own DB through ResolveReadDbs -- the SAME
     function resolve-dbs uses, so the two can never disagree.
  2. a DB that still does not resolve is a WARNING, not an exit. The caller
     asked what dcc says; the store is a cache for that answer, not the answer.

WHY CASE 2 IS NOT OPTIONAL. Case 1 asserts an EMPTY finding array, which a verb
that silently did nothing at all would also produce. Case 2 compiles a file with
a deliberate error and demands the error comes back, so "[]" in case 1 means
"compiled clean" rather than "never compiled".

THE GUARD WAS SHOWN TO BE CAPABLE OF FAILING, and this is the evidence rather
than an argument. The pre-fix binary, run on 2026-09-13 against the real
Micronite2027.dproj with the plugin's exact arguments, produced:

    exit: 2
    outLen: 308
    ERROR: compile-check: no --db was given and no project database resolves here.

Check 1 (exit <> 2), check 2 (that sentence absent) and check 3 (a JSON array is
present) all fail against that output. No rebuild of the old binary is needed to
re-confirm it; the measurement is quoted here because a guard nobody has seen go
red is a guard nobody has tested.

Needs a working dcc (RAD Studio). Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){
  Write-Host ("  [{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''}))
  if(-not $ok){ $script:fail = $true }
}

$work = Join-Path $env:TEMP ("dl-ccdb-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $work | Out-Null
function W([string]$p,[string[]]$l){ [IO.File]::WriteAllText($p, (($l -join "`r`n")+"`r`n"), [Text.Encoding]::ASCII) }

# A .dpr with no project file and no _D-RAG beside it: nothing can resolve a DB
# for it, which is exactly the state that used to return exit 2.
$good = Join-Path $work 'Tiny.dpr'
W $good @('program Tiny;','','{$APPTYPE CONSOLE}','','begin',"  Writeln('hi');",'end.')

Write-Host ''
Write-Host 'THE FIX -- a compile with nowhere to cache still REPORTS' -ForegroundColor Cyan

$out1 = (& $Exe compile-check $good --format json 2>&1 | Out-String)
$code1 = $LASTEXITCODE

Check '1. does NOT exit 2 (the old "no --db" bail)' `
      ($code1 -ne 2) "exit=$code1"

# The exact sentence the old build printed. Asserted by TEXT because that is
# what the plugin saw and what a regression would put back.
Check '2. the "no --db was given" refusal is gone' `
      ($out1 -notmatch 'no --db was given and no project database resolves here') `
      'this string returning means the cache became mandatory again'

Check '3. a JSON array is still emitted' `
      ($out1 -match '\[\s*\]|\[\s*\{') `
      "output=[$($out1.Trim())]"

Check '4. it SAYS caching was skipped, rather than skipping it silently' `
      ($out1 -match 'no database resolved for this target') `
      'a silent skip is how the original defect stayed invisible'

Write-Host ''
Write-Host 'CONTROLS' -ForegroundColor Cyan

# POSITIVE CONTROL. Case 1/3 are satisfied by a verb that compiles nothing and
# prints "[]". This one demands a real diagnostic, so an empty array above means
# "clean", not "inert".
$bad = Join-Path $work 'Broken.dpr'
W $bad @('program Broken;','','{$APPTYPE CONSOLE}','','begin','  ThisIdentifierDoesNotExist;','end.')
$out2 = (& $Exe compile-check $bad --format json 2>&1 | Out-String)
$code2 = $LASTEXITCODE

Check '5. positive control: a real compile ERROR comes back as JSON' `
      ($out2 -match '"severity":"Error"') `
      "exit=$code2 output=[$($out2.Trim())]"

Check '6. positive control: an error run exits 1, so exit codes still mean something' `
      ($code2 -eq 1) "exit=$code2"

# NARROWNESS. An explicit --db must still be honoured and must NOT print the
# skip warning -- otherwise check 4 would pass for a build that ignores --db.
$db = Join-Path $work 'cache.sqlite'
& $Exe index $work --db $db --rebuild *> $null
$out3 = (& $Exe compile-check $good --db $db --format json 2>&1 | Out-String)

Check '7. an explicit --db is honoured (no skip warning)' `
      ($out3 -notmatch 'no database resolved for this target') `
      "output=[$($out3.Trim())]"

Write-Host ''
try { [IO.Directory]::Delete($work, $true) } catch { }
if($fail){ Write-Host 'COMPILE-CHECK DB GUARD: FAIL' -ForegroundColor Red; exit 1 }
else     { Write-Host 'COMPILE-CHECK DB GUARD: PASS' -ForegroundColor Green; exit 0 }
