<#
  run_cyclefix_clause_edits.ps1 -- `cycles --plan` edits an EXISTING uses
  clause minimally, keeping its comments, and refuses on a directive.

  WHY (2026-10-19, E18 Task 3a): the planner rewrote a whole uses clause from
  `uses` to the last entry (FormatUses) and, when the clause held anything else
  -- a `// comment` line between entries, a directive -- it gave up with a
  MANUAL step ("In the implementation uses clause (lines a-b): remove ..."). A
  manual step makes `cycles --fix` refuse a cycle it could fix, and the
  whole-clause rewrite silently DROPPED a `{$IFDEF}` that sat on an entry line.
  Now every edit to an existing clause is computed over TUsesLexer tokens: add
  = `, <Unit>` after the last entry; remove = the entry and one separator;
  every comment is kept; a directive in the span an edit touches (or an entry
  inside a conditional region) refuses the whole cycle with `directive`.

  FIXTURES (tests\fixtures\cyclefix\, indexed as COPIES into scratch DBs):
    commentclause -- CfAlpha <-> CfBeta, implementation-only; CfAlpha's
      implementation clause has a `// comment` line between entries and a
      trailing `; // why` (the DemoAudit.pas / Regions.pas shapes).
    ifdefclause   -- the same, with the partner entry inside
      `{$IFDEF MSWINDOWS} , CfBeta {$ENDIF}` (MSWINDOWS, not DEBUG: the index
      does not define DEBUG, and an inactive branch has no edge, no cycle).

  ASSERTS
    commentclause: plan verdict mechanical, no refusal, no "In the ... uses
      clause" manual step; CfAlpha's edit is `Replace line 17` whose New text
      names CfBeta.Contracts and still holds `// why`; the comment line 16 is
      not part of any edit. END TO END: tools\follow-cycle-plan.ps1 applies the
      plan to the copy, both comments survive, and after a reindex `cycles`
      finds no cycle.
    ifdefclause: `refused: directive` naming CfAlpha.pas line 16; verdict
      refused with kind directive; CfAlpha gets no Replace/Delete edit.
  POSITIVE CONTROL: before any edit, `cycles` on each copy finds the 2-unit
  group -- otherwise every "no manual step" assertion could pass on a plan
  that found nothing to do.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-cyclefix-clause-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe      = (Resolve-Path $Exe).Path
$Repo     = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Fixtures = Join-Path $Repo 'tests\fixtures\cyclefix'
$Follower = Join-Path $Repo 'tools\follow-cycle-plan.ps1'
[void](New-Item -ItemType Directory -Force $WorkDir)

# Copies one fixture, indexes it into a scratch DB; returns @{Root; Db}.
function Prepare([string]$Name) {
  $root = Join-Path $WorkDir $Name
  if (Test-Path $root) { [IO.Directory]::Delete($root, $true) }
  [void](New-Item -ItemType Directory -Force $root)
  Get-ChildItem (Join-Path $Fixtures $Name) -File | ForEach-Object { Copy-Item $_.FullName (Join-Path $root $_.Name) }
  $db   = Join-Path $WorkDir ($Name + '.sqlite')
  if (Test-Path $db) { [IO.File]::Delete($db) }
  $proj = (Get-ChildItem $root -Filter *.dproj | Select-Object -First 1).FullName
  & $Exe index --project $proj --db $db *> (Join-Path $WorkDir ($Name + '-index.log'))
  Check "$Name indexed" ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
  return @{ Root = $root; Db = $db }
}

# Runs `cycles --plan`; returns @{Text; Dump; File}.
function Get-Plan([string]$Db, [string]$Tag) {
  $out  = Join-Path $WorkDir ($Tag + '-plan.txt')
  $dump = Join-Path $WorkDir ($Tag + '-dump.txt')
  if (Test-Path $dump) { [IO.File]::Delete($dump) }
  $env:DRAGLINT_TEST_DUMP_PLAN = $dump
  try {
    $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
      -ArgumentList @('cycles', '--db', ('"' + $Db + '"'), '--edges', '--causes', '--plan', '--format', 'text') `
      -RedirectStandardOutput $out -RedirectStandardError (Join-Path $WorkDir ($Tag + '-stderr.txt'))
  } finally {
    $env:DRAGLINT_TEST_DUMP_PLAN = $null
  }
  Check "$Tag plan exit 0" ($p.ExitCode -eq 0) "exit=$($p.ExitCode)"
  $d = if (Test-Path $dump) { [IO.File]::ReadAllText($dump) } else { '' }
  return @{ Text = [IO.File]::ReadAllText($out); Dump = $d; File = $out }
}

# The Step-4 block of one file heading: from `#### `<File>`` to the next heading.
function Get-FileBlock([string]$Text, [string]$File) {
  $m = [regex]::Match($Text, '(?ms)^#### `' + [regex]::Escape($File) + '`  \(.*?(?=^#{2,4} |\z)')
  if ($m.Success) { return $m.Value } else { return '' }
}

function Get-CycleCount([string]$Db) {
  $t = (& $Exe cycles --db $Db 2>$null | Out-String)
  return ([regex]::Matches($t, '(?m)^\s*\d+\.\s')).Count, $t
}

try {
  # ---------------------------------------------------------------- commentclause
  Write-Host '== commentclause' -ForegroundColor Cyan
  $c = Prepare 'commentclause'
  $n, $raw = Get-CycleCount $c.Db
  Check 'control: the 2-unit cycle exists before the plan' ($raw -match '(?i)cfalpha' -and $raw -match '(?i)cfbeta' -and $raw -notmatch 'No circular') ($raw.Trim() -replace "`r?`n", ' | ')
  $plan = Get-Plan $c.Db 'commentclause'
  Check 'verdict mechanical' ($plan.Dump -match 'verdict=mechanical') $plan.Dump.Trim()
  Check 'no refusal kinds' ($plan.Dump -match "refusals=`t") $plan.Dump.Trim()
  Check 'no manual uses-clause step' ($plan.Text -notmatch '(?m)^E\d+\. In the \w+ uses clause') ''
  $alpha = Get-FileBlock $plan.Text 'CfAlpha.pas'
  Check 'CfAlpha has an edit block' ($alpha -ne '') ''
  $m = [regex]::Match($alpha, '(?ms)^E\d+\. Replace line 17\. Current text:\r?\n```pascal\r?\n(?<cur>.*?)\r?\n```\r?\nNew text:\r?\n```pascal\r?\n(?<new>.*?)\r?\n```')
  Check 'CfAlpha: Replace line 17 (the trailing-comment line)' $m.Success ($alpha -replace "`r?`n", ' | ')
  if ($m.Success) {
    Check 'New text keeps `// why`' ($m.Groups['new'].Value -match '// why') $m.Groups['new'].Value
    Check 'New text names CfBeta.Contracts' ($m.Groups['new'].Value -match 'CfBeta\.Contracts') $m.Groups['new'].Value
    Check 'New text drops the CfBeta entry' ($m.Groups['new'].Value -notmatch '\bCfBeta[;,]') $m.Groups['new'].Value
  }
  Check 'the comment line 16 is in no edit' ($alpha -notmatch 'CfBeta supplies the limit') ''

  # end to end: follow the plan on the copy, re-index, the cycle is gone
  $fo = & pwsh -NoProfile -File $Follower -PlanFile $plan.File -Cycle 1 2>&1 | Out-String
  Check 'follow-cycle-plan applies the plan' ($LASTEXITCODE -eq 0) ($fo.Trim() -replace "`r?`n", ' | ')
  # the follower SKIPS an unparseable step with a REFUSE line and still exits 0 -- read its output too
  Check 'follow-cycle-plan refuses no step' ($fo -notmatch 'REFUSE') ($fo.Trim() -replace "`r?`n", ' | ')
  $after = [IO.File]::ReadAllText((Join-Path $c.Root 'CfAlpha.pas'))
  Check 'applied CfAlpha keeps the comment line' ($after.Contains('  // CfBeta supplies the limit')) ''
  Check 'applied CfAlpha keeps the trailing comment' ($after -match 'CfBeta\.Contracts; // why: the limit lives there') ''
  $proj = (Get-ChildItem $c.Root -Filter *.dproj | Select-Object -First 1).FullName
  & $Exe index --project $proj --db $c.Db *> (Join-Path $WorkDir 'commentclause-reindex.log')
  $n2, $raw2 = Get-CycleCount $c.Db
  Check 'after the plan: no cycle' ($raw2 -match 'No circular') ($raw2.Trim() -replace "`r?`n", ' | ')

  # ---------------------------------------------------------------- ifdefclause
  Write-Host '== ifdefclause' -ForegroundColor Cyan
  $i = Prepare 'ifdefclause'
  $n, $raw = Get-CycleCount $i.Db
  Check 'control: the 2-unit cycle exists before the plan' ($raw -match '(?i)cfalpha' -and $raw -notmatch 'No circular') ($raw.Trim() -replace "`r?`n", ' | ')
  $plan = Get-Plan $i.Db 'ifdefclause'
  Check 'prints refused: directive naming CfAlpha line 16' ($plan.Text -match 'refused: directive[^\r\n]*line 16') ''
  Check 'verdict refused' ($plan.Dump -match 'verdict=refused') $plan.Dump.Trim()
  Check 'refusal kind directive' ($plan.Dump -match 'refusals=[^\t]*\bdirective\b') $plan.Dump.Trim()
  $alpha = Get-FileBlock $plan.Text 'CfAlpha.pas'
  Check 'CfAlpha gets no Replace/Delete edit (the directive is never rewritten)' ($alpha -notmatch '(?m)^E\d+\. (Replace|Delete) ') ($alpha -replace "`r?`n", ' | ')
} finally {
  if ($script:Failed) { Write-Host "work dir kept: $WorkDir" -ForegroundColor DarkGray }
}

if ($script:Failed) { Write-Host 'run_cyclefix_clause_edits: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_cyclefix_clause_edits: PASS' -ForegroundColor Green
exit 0
