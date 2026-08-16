<#
  run_cycles_local_var_scope.ps1 -- `cycles --plan` must not report a routine's
  own LOCAL variable as cross-unit coupling.

  INBOX-cycles-scope-and-local-var-refs. The "Why it cycles" scan resolves each
  implementation-section ref by a bare `FindSymbolsByExactName` sweep of the
  whole DB. It skipped candidates that were THEMSELVES local/param-kind, but
  went on to the next same-named candidate -- so a routine-local `SharedName` in
  unit A matched a unit-level `SharedName` in unit B and was reported as a thing
  to "move, extract, or inline" to break the cycle. Delphi resolves that name to
  the local; it creates no dependency on B whatsoever.

  This scan is a standalone name heuristic and never consults the call resolver,
  so nothing else was going to catch it. The fix asks the ref's OWN enclosing
  routine first and discards the ref when it declares that name.

  Fixture (fixtures\cyclescope) is an IMPLEMENTATION-ONLY cycle, because that is
  the branch printing "Why it cycles (implementation-section edges)" -- an
  interface-coupled cycle takes a different path entirely:

    uCycA.UseIt  declares a LOCAL  SharedName   -> must NOT be reported
    uCycA.UseIt  calls            RealThing     -> MUST still be reported
    uCycB        declares unit-level SharedName and RealThing

  RED VERIFIED 2026-08-16: with the scope check neutralised, the output carries
      - line 29: `SharedName`  [var]  -> declared in `ucycb`
  alongside RealThing. So the fixture genuinely reproduces, and the "SharedName
  is absent" assertion is not vacuous.

  THE POSITIVE CONTROL IS `RealThing`. A test asserting only "SharedName is
  gone" would pass just as well if the whole cause-list broke and printed
  nothing -- which is the more likely regression, since the list already has a
  "(no specific symbol resolved -- index gap)" fallback that prints on empty.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }

$exePath = (Resolve-Path $Exe).Path
$fixDir  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\cyclescope')).Path

$scratch = Join-Path C:\TEMP 'draglint_cyclescope'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
Copy-Item (Join-Path $fixDir '*.pas') $scratch -Force
$db = Join-Path $scratch 'cyc.sqlite'

Push-Location C:\TEMP
try {
  $idx = & $exePath index $scratch --db $db 2>&1 | Out-String
  Check 'SANITY: both fixture units indexed with no errors' `
        (($idx -match 'uCycA\.pas\s*->\s*\d+ symbols, \d+ refs, 0 errors') -and
         ($idx -match 'uCycB\.pas\s*->\s*\d+ symbols, \d+ refs, 0 errors')) $idx

  $plan = & $exePath cycles --plan --db $db 2>&1 | Out-String

  Check 'SANITY: the cycle is detected and is implementation-only' `
        ($plan -match 'implementation-only') $plan
  Check 'SANITY: the "Why it cycles" section was produced' `
        ($plan -match 'Why it cycles') $plan
  Check 'POSITIVE CONTROL: RealThing IS still reported as real coupling' `
        ($plan -match '`RealThing`\s*\[procedure\]\s*->\s*declared in\s*`ucycb`') $plan
  Check 'SharedName (a routine LOCAL) is NOT reported as coupling to ucycb' `
        ($plan -notmatch '`SharedName`') $plan
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
