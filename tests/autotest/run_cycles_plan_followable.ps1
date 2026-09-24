<#
  run_cycles_plan_followable.ps1 -- `cycles --plan` must be a MECHANICAL
  playbook: a model with no project context must be able to follow it to a
  compiling tree whose cycle report matches the playbook's own prediction.

  WHY (docs\INBOX-test-cycle-playbook-followability-haiku-flash.md, run
  2026-09-23): Haiku followed the old playbook on circular-demo and FAILED.
    1. "extract the shared contract into a leaf unit" for the CLASS
       TDemoSession: it moved the declaration and left the method bodies
       behind -> E2065 x5, the project stopped compiling. The playbook never
       said a class carries its method bodies, nor offered a base-class
       extraction that keeps the class where it is.
    2. "cycle 1 should be gone" -- but cutting the interface edges leaves a
       LEGAL implementation-only cycle. DONE was never defined.
    3. Nothing was concrete: no line ranges, no consumer list per symbol, no
       per-section uses decision, no checklist, no expected output.

  This suite pins the elements that make it followable, on a COPY of the
  repo's circular-demo (which must itself stay circular -- never edit it):
    * a kind + recipe per moved symbol, with exact declaration lines;
    * for the class TDemoSession: its method-body line ranges AND the
      base-class extraction chosen instead (with the reason);
    * a consumer list per symbol: unit, section, first-use line;
    * a per-unit decision on the old uses entry (keep / move / remove);
    * the new units named, their full content, and their uses rule;
    * .dpr / .dproj registration lines;
    * a DONE definition and an OPTIONAL Part B for the implementation edges;
    * a numbered checklist ending in the exact expected `cycles` output.

  POSITIVE CONTROL: the plain `cycles` report on the same copy must still find
  the 4-unit group with interface coupling -- otherwise every assertion below
  could pass against a playbook that found nothing to do.

  The end-to-end proof (apply the playbook literally, compile, re-index,
  compare) is run by hand with rsvars + msbuild; it is not part of the
  battery because the battery has no compiler.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }
function Has([string]$Text, [string]$Literal) { return $Text.Contains($Literal) }

$exePath = (Resolve-Path $Exe).Path
$demoDir = (Resolve-Path (Join-Path $PSScriptRoot '..\..\circular-demo')).Path

$scratch = Join-Path C:\TEMP 'draglint_cyclesplan'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
Copy-Item (Join-Path $demoDir '*.pas')   $scratch -Force
Copy-Item (Join-Path $demoDir '*.dpr')   $scratch -Force
Copy-Item (Join-Path $demoDir '*.dproj') $scratch -Force
$db    = Join-Path $scratch 'demo.sqlite'
$dproj = Join-Path $scratch 'CircularDemo.dproj'

Push-Location C:\TEMP
try {
  $idx = & $exePath index --project $dproj --db $db 2>&1 | Out-String
  Check 'SANITY: the four demo units indexed with no errors' `
        (([regex]::Matches($idx, 'Demo\w+\.pas\s*->\s*\d+ symbols, \d+ refs, 0 errors')).Count -eq 4) $idx

  $report = & $exePath cycles --db $db 2>&1 | Out-String
  Check 'POSITIVE CONTROL: plain report finds the 4-unit group with interface coupling' `
        ($report -match '\[4 units\].*has interface coupling') $report

  $plan = (& $exePath cycles --plan --db $db 2>&1 | Out-String) -replace "`r`n", "`n"
  Set-Content -Path (Join-Path $scratch 'plan.md') -Value $plan -Encoding ascii

  # --- 1. kind + recipe per symbol ------------------------------------------
  Check 'TDemoLogLevel: kind enum + exact declaration lines (doc comment included)' `
        (Has $plan '`TDemoLogLevel` -- **enum**, declared at `DemoLogger.pas` lines 14-15') $plan
  Check 'TDemoAuditKind: kind enum + exact declaration lines' `
        (Has $plan '`TDemoAuditKind` -- **enum**, declared at `DemoAudit.pas` lines 23-24') $plan
  Check 'TDemoSession: kind class-with-methods + declaration lines' `
        (Has $plan '`TDemoSession` -- **class with methods**, declared at `DemoSession.pas` lines 14-47') $plan
  Check 'TDemoSession: the method-body line ranges are listed' `
        (Has $plan 'method bodies at `DemoSession.pas` lines 64-73, 75-80, 82-86, 88-95, 97-100') $plan
  Check 'TDemoSession: base-class extraction chosen, class kept in place' `
        ((Has $plan 'extract a base class') -and (Has $plan '`TDemoSessionBase`') -and
         (Has $plan 'becomes `TDemoSession = class(TDemoSessionBase)`')) $plan
  Check 'TDemoSession: the choice is justified by what the bodies use' `
        ($plan -match 'bodies use [^\n]*`GDemoAuditTrail`') $plan

  # --- 2. consumers per symbol ---------------------------------------------
  Check 'consumers of TDemoLogLevel: DemoConfig interface, first use line 23' `
        (Has $plan '`DemoConfig.pas` interface (first use: line 23)') $plan
  Check 'consumers of TDemoLogLevel: the .dpr, first use line 37' `
        (Has $plan '`CircularDemo.dpr` program uses (first use: line 37)') $plan
  Check 'consumers of TDemoSessionBase: DemoLogger lines 40 and 53 switch to the base' `
        (Has $plan '`DemoLogger.pas` lines 40, 53') $plan

  # --- 3. per-unit uses decisions ------------------------------------------
  Check 'DemoConfig: DemoLogger moves from interface to implementation uses' `
        ($plan -match '`DemoConfig\.pas` / `DemoLogger`: [^\n]*\*\*move\*\* it from the interface uses to the implementation uses') $plan
  Check 'DemoSession: DemoAudit moves from interface to implementation uses' `
        ($plan -match '`DemoSession\.pas` / `DemoAudit`: [^\n]*\*\*move\*\*') $plan

  # --- 4. new units + their uses rule ---------------------------------------
  foreach ($u in 'DemoLogger.Contracts','DemoAudit.Contracts','DemoSession.Contracts') {
    Check "new unit ${u}: full content given" (Has $plan "unit $u;") $plan
  }
  Check 'new units: the uses rule names the cycle units it must never use' `
        (Has $plan 'never a unit of this cycle') $plan

  # --- 5. registration ------------------------------------------------------
  Check '.dpr registration line for a new unit' `
        (Has $plan "DemoLogger.Contracts in 'DemoLogger.Contracts.pas'") $plan
  Check '.dproj DCCReference line for a new unit' `
        (Has $plan '<DCCReference Include="DemoLogger.Contracts.pas"/>') $plan

  # --- 6. edits are bottom-up with the current text quoted -------------------
  Check 'edits: bottom-up ordering is stated' (Has $plan 'from the bottom of the file to the top') $plan
  Check 'edits: the class header replacement is spelled out' `
        (Has $plan '  TDemoSession = class(TDemoSessionBase)') $plan

  # --- 7. DONE + optional Part B ------------------------------------------
  Check 'DONE is defined' (Has $plan '### DONE') $plan
  Check 'Part B is present and marked optional' (Has $plan '### Part B (optional)') $plan
  Check 'Part B names the global that keeps the implementation cycle alive' `
        (Has $plan '`GDemoSettings`') $plan

  # --- 8. checklist with exact expected output ------------------------------
  Check 'checklist is present' (Has $plan '### Checklist') $plan
  Check 'checklist has a compile step' ($plan -match '\d+\. \[ \] Compile ') $plan
  # IDE-9 run 2: Haiku passed 4/4 but saved the NEW units with LF endings,
  # because the plan never said how to save them.
  Check 'checklist says to save new units as ASCII + CRLF' `
        ($plan -match '\[ \] Create `[^`]+` with the exact text given for `[^`]+`\. Save it as plain ASCII with Windows CRLF line endings') $plan
  Check 'checklist gives the re-index command for this project' `
        (Has $plan ('index --project "' + $dproj + '" --db "' + $db + '"')) $plan
  Check 'checklist predicts the implementation-only result exactly' `
        ($plan -match '1 circular unit group\(s\) found:\n  \[4 units\] [a-z <\->]+   \(implementation-only -- legal, lower impact\)') $plan

  # --- the old, unfollowable wording is gone ---------------------------------
  Check 'the old "cycle N should be gone" promise is gone' ($plan -notmatch 'should be gone') $plan
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
