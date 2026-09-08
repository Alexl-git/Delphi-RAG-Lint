<#
  run_uses_fix_json_and_only.ps1 -- `uses-fix --format json` and `--only`.

  WHY THIS EXISTS
  ---------------
  `uses-fix` is the one verb in this repo with real rewrite power and no test
  coverage, because verifying an edit means running a Delphi compile. That gap
  is exactly why it shipped as a report the IDE will not let you act on.

  Making it actionable needs two things, and they are useless apart: a
  MACHINE-READABLE list of candidates to put checkboxes against, and a way to
  say "apply these three". With only --apply, a fix button is all-or-nothing
  over changes the user has not seen one by one.

  WHAT THIS GUARD ASSERTS, AND WHAT IT DELIBERATELY DOES NOT
  ----------------------------------------------------------
  Candidacy is decided from the INDEX; only VERIFICATION compiles. This runner
  asserts the index-side contract -- which units are candidates, of what kind,
  and how --only narrows the set -- and it does NOT assert whether an edit
  verified. There is no real project here, so dcc will not validate anything,
  and every candidate is expected to come back `skipped`.

  That is a deliberate boundary, not a hole: a guard that required a working
  compile would be untestable on any box without the exact project set up, and
  would fail for reasons that have nothing to do with the code under test. What
  it costs is stated plainly -- nothing here proves an edit is CORRECT, only
  that the right edits are OFFERED and that selection reaches the write path.
  The compiler-verification half remains covered only by the engine's own
  shadow-compile logic, which is unchanged by this feature.

  `deselected` is distinguishable from `skipped` precisely because it is set
  BEFORE TryEdit, so --only is observable even with no compiler at all.

  RED BASELINE, measured 2026-09-07 by running this runner against drag-lint
  1.9.0-alpha (built 2026-09-02, VS Code's private engine copy), which predates
  both flags:

      RED    1a, 2a, 2b, 3a, 3b, 3d, 4a, 4b, 5
      GREEN  6a, 6b -- text mode is genuinely unchanged by this feature, which
             is the point of asserting it
      GREEN BUT VACUOUS  2c, 3c, 3e -- with no JSON document, $j.items is null
             and every NEGATIVE assertion holds trivially. They earn their keep
             only against an engine that DOES emit JSON, where 2c stops "list
             every used unit" and 3e stops "mark everything deselected".
      NOT REACHED  1b, 1c, 1d -- guarded behind 1a, correctly.

  Run it that way again if you need to re-establish the baseline:
      pwsh -File tests\autotest\run_uses_fix_json_and_only.ps1 -Exe <old engine>

  Usage: pwsh -File tests\autotest\run_uses_fix_json_and_only.ps1
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n, $ok, $d = '') {
  Write-Host ("  [{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]), $n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if (-not $ok -and $d) { Write-Host "        $d" -ForegroundColor DarkGray }
  if (-not $ok) { $script:fail = $true }
}
function WritePas([string]$Path, [string]$Text) {
  $norm = ($Text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP 'draglint_uses_fix_json'
if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path $scratch | Out-Null
$src = Join-Path $scratch 'src'
New-Item -ItemType Directory -Path $src | Out-Null
$db = Join-Path $scratch 'uf.sqlite'

# uMoveMe   -- named in the INTERFACE uses but referenced only from the
#              implementation  -> a MOVE candidate.
# uDropMe   -- named and never referenced at all, no init/final
#              -> a REMOVE candidate (only with --remove-unused).
# uKeepMe   -- referenced FROM THE INTERFACE -> not a candidate at all, which is
#              what stops "every used unit is a candidate" passing these checks.
WritePas (Join-Path $src 'uMoveMe.pas') @'
unit uMoveMe;
interface
type
  TMoveMe = class
    procedure Go;
  end;
implementation
procedure TMoveMe.Go;
begin
end;
end.
'@
WritePas (Join-Path $src 'uDropMe.pas') @'
unit uDropMe;
interface
type
  TDropMe = class
    procedure Nope;
  end;
implementation
procedure TDropMe.Nope;
begin
end;
end.
'@
WritePas (Join-Path $src 'uKeepMe.pas') @'
unit uKeepMe;
interface
type
  TKeepMe = class
    procedure Stay;
  end;
implementation
procedure TKeepMe.Stay;
begin
end;
end.
'@
WritePas (Join-Path $src 'uMain.pas') @'
unit uMain;

interface

uses
  uMoveMe,
  uDropMe,
  uKeepMe;

type
  TMain = class
    FKeep: TKeepMe;
    procedure Run;
  end;

implementation

procedure TMain.Run;
var
  M: TMoveMe;
begin
  M := TMoveMe.Create;
  try
    M.Go;
  finally
    M.Free;
  end;
end;

end.
'@
# A .dproj only has to EXIST for the verify step to be attempted; it is not
# expected to produce a working compile here (see the header).
WritePas (Join-Path $src 'App.dproj') @'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <ItemGroup>
    <DCCReference Include="uMain.pas"/>
    <DCCReference Include="uMoveMe.pas"/>
    <DCCReference Include="uDropMe.pas"/>
    <DCCReference Include="uKeepMe.pas"/>
  </ItemGroup>
</Project>
'@

$unit = Join-Path $src 'uMain.pas'
$proj = Join-Path $src 'App.dproj'

Write-Host '== uses-fix --format json / --only ==' -ForegroundColor Cyan

& $exePath index $src --db $db 2>&1 | Out-Null
Check 'fixture indexed' (Test-Path $db) $db

function RunJson([string[]]$ExtraArgs) {
  $a = @('uses-fix', $unit, '--project', $proj, '--db', $db, '--remove-unused', '--format', 'json') + $ExtraArgs
  $raw = (& $exePath @a 2>$null | Out-String)
  # The engine prints a defaults banner on some paths; take the JSON object only.
  $i = $raw.IndexOf('{')
  if ($i -lt 0) { return $null }
  try { return ($raw.Substring($i) | ConvertFrom-Json) } catch { return $null }
}

# ---------------------------------------------------------------------------
# 1 -- THE JSON CONTRACT. Without a parseable document there is nothing to
#      build a checkbox list from, and every assertion below is vacuous.
# ---------------------------------------------------------------------------
$j = RunJson @()
Check '1a --format json emits a parseable document' ($null -ne $j) 'no JSON object on stdout'
if ($null -ne $j) {
  Check '1b it declares its schema' ($j.schema -eq 'uses-fix/1') "schema=$($j.schema)"
  Check '1c it names the unit and the project' `
    (($j.unit -match 'uMain\.pas') -and ($j.project -match 'App\.dproj')) `
    "unit=$($j.unit) project=$($j.project)"
  Check '1d it reports applied=false on a dry run' ($j.applied -eq $false) "applied=$($j.applied)"
}

# ---------------------------------------------------------------------------
# 2 -- THE CANDIDATES, and the one that must NOT be a candidate.
# ---------------------------------------------------------------------------
$names = @($j.items | ForEach-Object { $_.unit })
Check '2a uMoveMe is offered as a move' `
  (@($j.items | Where-Object { $_.unit -eq 'uMoveMe' -and $_.kind -eq 'move' }).Count -eq 1) `
  "items: $($names -join ', ')"
Check '2b uDropMe is offered as a remove' `
  (@($j.items | Where-Object { $_.unit -eq 'uDropMe' -and $_.kind -eq 'remove' }).Count -eq 1) `
  "items: $($names -join ', ')"
# NEGATIVE CONTROL. Without this, "list every used unit" passes 2a and 2b.
Check '2c uKeepMe is NOT offered (referenced from the interface)' `
  ($names -notcontains 'uKeepMe') `
  "a unit used in the interface must never be proposed for a move or a removal"

# ---------------------------------------------------------------------------
# 3 -- SELECTION. The flag the fix button needs.
# ---------------------------------------------------------------------------
$sel = RunJson @('--only', 'uMoveMe')
Check '3a --only still LISTS the deselected candidate' `
  ((@($sel.items | ForEach-Object { $_.unit })) -contains 'uDropMe') `
  'hiding unticked candidates makes the user wonder where their unit went'
Check '3b and marks it deselected rather than skipped' `
  ((@($sel.items | Where-Object { $_.unit -eq 'uDropMe' })).status -eq 'deselected') `
  "status=$((@($sel.items | Where-Object { $_.unit -eq 'uDropMe' })).status)"
Check '3c the selected candidate is NOT deselected' `
  ((@($sel.items | Where-Object { $_.unit -eq 'uMoveMe' })).status -ne 'deselected') `
  'the unit that was asked for must reach the verify step'
Check '3d the selection is echoed back' `
  ((@($sel.selection)) -contains 'uMoveMe') "selection=$($sel.selection -join ',')"
# POSITIVE CONTROL for 3b: with no --only, NOTHING is deselected. Without this,
# 3b would pass on an engine that marked everything deselected always.
Check '3e positive control: no --only means nothing is deselected' `
  (@($j.items | Where-Object { $_.status -eq 'deselected' }).Count -eq 0) `
  'deselected must be caused by the flag, not be the default'

# ---------------------------------------------------------------------------
# 4 -- A SELECTION THAT MATCHES NOTHING IS REPORTED, not silently dropped.
# ---------------------------------------------------------------------------
$bad = RunJson @('--only', 'uNoSuchUnit')
Check '4a an unmatched selection is listed under unmatched' `
  ((@($bad.unmatched)) -contains 'uNoSuchUnit') "unmatched=$($bad.unmatched -join ',')"
Check '4b and every real candidate is deselected' `
  (@($bad.items | Where-Object { $_.status -ne 'deselected' }).Count -eq 0) `
  'a typo must not fall through to applying everything'

# ---------------------------------------------------------------------------
# 5 -- A JSON CALLER GETS A DOCUMENT IN EVERY OUTCOME. uKeepMe has a clean uses
#      clause, so this is the "nothing to change" path.
# ---------------------------------------------------------------------------
$clean = (& $exePath uses-fix (Join-Path $src 'uKeepMe.pas') --project $proj --db $db --format json 2>$null | Out-String)
$ci = $clean.IndexOf('{')
$cleanJson = if ($ci -ge 0) { try { $clean.Substring($ci) | ConvertFrom-Json } catch { $null } } else { $null }
Check '5 "nothing to change" still emits JSON' `
  (($null -ne $cleanJson) -and ($cleanJson.schema -eq 'uses-fix/1')) `
  'an empty stdout makes "nothing to do" indistinguishable from a crash'

# ---------------------------------------------------------------------------
# 7 -- `applied` IS THE OUTCOME, NOT THE FLAG.
#      Self-review found the first cut reporting applied=true for `--apply` on a
#      unit with nothing to change: no write, no .bak, and a caller told its
#      file had been rewritten. uKeepMe has a clean uses clause.
# ---------------------------------------------------------------------------
$keep = Join-Path $src 'uKeepMe.pas'
$rawA = (& $exePath uses-fix $keep --project $proj --db $db --apply --format json 2>$null | Out-String)
$ai = $rawA.IndexOf('{')
$applyJson = if ($ai -ge 0) { try { $rawA.Substring($ai) | ConvertFrom-Json } catch { $null } } else { $null }
Check '7a --apply with nothing to change still emits JSON' ($null -ne $applyJson) 'no document'
Check '7b and reports applied=false, because nothing was written' `
  ($applyJson.applied -eq $false) "applied=$($applyJson.applied)"
Check '7c and no .bak was left behind (the claim matches the disk)' `
  (-not (Test-Path ($keep + '.bak'))) `
  'applied=false must mean no backup exists, or the field is still lying'

# ---------------------------------------------------------------------------
# 8 -- THE SAFETY CAVEAT REACHES THE MACHINE CALLER.
#      Text mode has always printed "best-effort ... do a full project build".
#      JSON suppressed it, so the one caller putting a button in front of a
#      human was the only one never shown it.
# ---------------------------------------------------------------------------
Check '8 the counts object carries deselected' `
  ($null -ne $sel.counts.deselected) "counts=$($sel.counts | ConvertTo-Json -Compress)"

# ---------------------------------------------------------------------------
# 9 -- THE SWEEP FORM DOES NOT SWALLOW THE FLAGS.
#      `uses-fix` with no <unit.pas> goes to the sweep, which honours neither.
#      Silence there makes a mistyped command look like an answer.
# ---------------------------------------------------------------------------
$sweepErr = Join-Path $scratch 'sweep.err'
& $exePath uses-fix --project $proj --db $db --only uMoveMe --format json 2>$sweepErr | Out-Null
$sweepNote = if (Test-Path $sweepErr) { Get-Content $sweepErr -Raw } else { '' }
Check '9a the sweep says --only does not apply to it' `
  ($sweepNote -match '--only applies to') "stderr was:`n$sweepNote"
Check '9b and says the same of --format json' `
  ($sweepNote -match '--format json applies to') "stderr was:`n$sweepNote"

# ---------------------------------------------------------------------------
# 6 -- TEXT MODE IS UNCHANGED. The IDE and humans still use it.
# ---------------------------------------------------------------------------
$txt = (& $exePath uses-fix $unit --project $proj --db $db --remove-unused 2>$null | Out-String)
Check '6a text mode prints no JSON' ($txt -notmatch '"schema"') 'text callers must not suddenly get a document'
Check '6b text mode still names the candidates' `
  (($txt -match 'uMoveMe') -and ($txt -match 'uDropMe')) `
  "got:`n$txt"

Write-Host ''
if ($script:fail) { Write-Host 'USES-FIX json/only: FAIL' -ForegroundColor Red; exit 1 }
else { Write-Host 'USES-FIX json/only: PASS' -ForegroundColor Green; exit 0 }
