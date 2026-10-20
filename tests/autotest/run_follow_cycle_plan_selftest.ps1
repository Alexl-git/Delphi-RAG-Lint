<#
  run_follow_cycle_plan_selftest.ps1 -- tools\follow-cycle-plan.ps1 applied to the
  `cycles --plan` playbook of a COPY of circular-demo must produce exactly the
  `cycles` output the playbook predicted, INCLUDING the order of the groups.

  WHY (E18 Task 2, feasibility 2026-10-19): after Part A on the 3-cycle demo,
  `cycles` printed the groups [4],[2],[3] (Tarjan discovery order) while the
  predicted block printed [2],[3],[4]. A mechanical follower compares line by
  line, so the prediction must keep every group where DoCycles will print it.

  HOW. Copy circular-demo to a private scratch root, index it (--db inside the
  scratch), `cycles --plan` -> plan.txt, follow Cycle 1 (exit 0, 3 new files),
  re-index, `cycles` -> actual. The predicted block is the text between the
  `It must print exactly:` fence of Cycle 1. Both sides drop informational lines
  (`(loaded`, `drag-lint: note:`, `  resolver:`) and are compared line for line.
  Cycles 2 and 3 are refused by the planner: the follower must exit 2 with
  `REFUSE: plan has no mechanical steps`. No compiler involved.
  POSITIVE CONTROL: swapping two predicted group lines in memory must make the
  compare FAIL. Also: -Root applies the same plan to a second copy (real run; the first copy must stay byte-unchanged) and\n  is refused (exit 2) when the plan paths share no common directory.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-follow-plan-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  Write-Host ("  [{0}] {1} {2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $n, $d) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Follow = Join-Path $Repo 'tools\follow-cycle-plan.ps1'

function Copy-Demo([string]$To) {
  New-Item -ItemType Directory -Force -Path $To | Out-Null
  foreach ($pat in '*.pas', '*.dpr', '*.dproj') { Copy-Item (Join-Path $Repo "circular-demo\$pat") $To -Force }
}
function Keep([string]$Text) {
  @($Text -split "\r?\n" | ForEach-Object { $_.TrimEnd() } |
    Where-Object { $_ -ne '' -and $_ -notmatch '^\(loaded|^drag-lint: note:|^\s+resolver:' })
}
function Run([string[]]$a) {
  $o = & $Exe @a 2>$null | Out-String
  return $o
}

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
Push-Location $WorkDir
try {
  $S = Join-Path $WorkDir 'copy'; Copy-Demo $S
  $dproj = Join-Path $S 'CircularDemo.dproj'; $db = Join-Path $S 'demo.sqlite'
  & $Exe index --project $dproj --db $db *> $null
  Check 'index the copy' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
  $plan = Join-Path $WorkDir 'plan.txt'
  [IO.File]::WriteAllText($plan, (Run @('cycles', '--db', $db, '--plan')), [Text.Encoding]::ASCII)

  # -Root: the same plan, applied for real to a second copy; the first copy must not change
  function Get-Hashes([string]$Dir) {
    $h = [ordered]@{}
    foreach ($f in Get-ChildItem -LiteralPath $Dir -File | Sort-Object Name) { $h[$f.Name] = (Get-FileHash -LiteralPath $f.FullName).Hash }
    return $h
  }
  $S2 = Join-Path $WorkDir 'copy2'; Copy-Demo $S2
  $h1 = (Get-Hashes $S | ConvertTo-Json -Compress); $h2 = (Get-Hashes $S2 | ConvertTo-Json -Compress)
  $ro = & pwsh -NoProfile -File $Follow -PlanFile $plan -Cycle 1 -Root $S2 2>&1 | Out-String
  Check '-Root run on a second copy exits 0' ($LASTEXITCODE -eq 0) $ro
  Check '-Root: copy2 got the 3 new files' ((@('DemoSession.Untangle.pas', 'DemoLogger.Untangle.pas', 'DemoAudit.Untangle.pas') | Where-Object { Test-Path (Join-Path $S2 $_) }).Count -eq 3)
  Check '-Root: copy2 changed' ((Get-Hashes $S2 | ConvertTo-Json -Compress) -cne $h2)
  Check '-Root: the original copy is byte-unchanged' ((Get-Hashes $S | ConvertTo-Json -Compress) -ceq $h1)
  # POSITIVE CONTROL (checked after the Cycle 1 follow below): without -Root the plan edits `copy`, not copy3
  $S3 = Join-Path $WorkDir 'copy3'; Copy-Demo $S3
  $h3 = (Get-Hashes $S3 | ConvertTo-Json -Compress)
  # -Root with paths sharing no common directory is refused
  $odd = ([IO.File]::ReadAllText($plan)) -replace '(?m)^(#### `DemoAudit\.Untangle` -> `)[^`]*(DemoAudit\.Untangle\.pas`)', '${1}D:\elsewhere\${2}'
  $oddPlan = Join-Path $WorkDir 'plan-odd.txt'; [IO.File]::WriteAllText($oddPlan, $odd, [Text.Encoding]::ASCII)
  $ro2 = & pwsh -NoProfile -File $Follow -PlanFile $oddPlan -Cycle 1 -Root $S3 2>&1 | Out-String
  Check '-Root with no common directory: exit 2 with REFUSE' ($LASTEXITCODE -eq 2 -and $ro2 -match 'REFUSE: -Root given but') $ro2
  $out = & pwsh -NoProfile -File $Follow -PlanFile $plan -Cycle 1 2>&1 | Out-String
  Check 'Cycle 1 follows: exit 0' ($LASTEXITCODE -eq 0) $out
  Check 'Cycle 1 created 3 new files' (([regex]::Matches($out, '(?m)^created ')).Count -eq 3) $out

  Check 'POSITIVE CONTROL: without -Root the plan changed its own tree (copy)' ((Get-Hashes $S | ConvertTo-Json -Compress) -cne $h1)
  Check 'POSITIVE CONTROL: without -Root the plan did not touch copy3' ((Get-Hashes $S3 | ConvertTo-Json -Compress) -ceq $h3)

  foreach ($c in 2, 3) {
    $o = & pwsh -NoProfile -File $Follow -PlanFile $plan -Cycle $c 2>&1 | Out-String
    Check "Cycle $c is refused (exit 2)" ($LASTEXITCODE -eq 2) $o
    Check "Cycle $c says no mechanical steps" ($o -match 'REFUSE: plan has no mechanical steps') $o
  }

  & $Exe index --project $dproj --db $db *> $null
  $actual = Keep (Run @('cycles', '--db', $db))

  $pt = [IO.File]::ReadAllText($plan)
  $m = [regex]::Match($pt, '(?s)## Cycle 1:.*?It must print exactly:\s*\r?\n```text\r?\n(.*?)\r?\n```')
  Check 'Cycle 1 has a predicted block' $m.Success
  $pred = if ($m.Success) { Keep $m.Groups[1].Value } else { @() }
  $same = ($pred.Count -gt 0) -and (($pred -join "`n") -ceq ($actual -join "`n"))
  Check 'predicted block == actual cycles output, group order included' $same ("`n  predicted:`n    " + ($pred -join "`n    ") + "`n  actual:`n    " + ($actual -join "`n    "))

  if ($pred.Count -ge 3) {
    $sw = @($pred); $t = $sw[1]; $sw[1] = $sw[2]; $sw[2] = $t
    Check 'POSITIVE CONTROL: swapped group lines no longer compare equal' (($sw -join "`n") -cne ($actual -join "`n"))
  }
  # ---- fix round 2: single new unit under -Root, and every REFUSE exits 2 ----
  $FX = Join-Path $WorkDir 'fx'; $FXR = Join-Path $WorkDir 'fxroot'
  foreach ($d in $FX, $FXR) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    [IO.File]::WriteAllText((Join-Path $d 'Existing.pas'), "unit Existing;`r`ninterface`r`nimplementation`r`nend.`r`n", [Text.Encoding]::ASCII)
  }
  function New-MiniPlan([string]$Dir, [string[]]$Step3, [string[]]$Step4) {
    $l = @('## Cycle 1: a <-> b', '', '### Step 3')
    $l += $Step3
    $l += '### Step 4'
    $l += $Step4
    $l += '### Checklist'
    $f = Join-Path $WorkDir ('mini-' + [Guid]::NewGuid().ToString('N') + '.txt')
    [IO.File]::WriteAllText($f, ($l -join "`r`n") + "`r`n", [Text.Encoding]::ASCII)
    return $f
  }
  function Unit3([string]$Dir, [string]$Name) { @(('#### `' + $Name + '` -> `' + (Join-Path $Dir ($Name + '.pas')) + '`'), '```', ('unit ' + $Name + ';'), '```') }
  function Head4([string]$Dir) { ,@(('#### `Existing.pas`  (`' + (Join-Path $Dir 'Existing.pas') + '`)')) }
  $okEdit = @('E1. After line 1 (`unit Existing;`), insert:', '```', '// added', '```')
  function Run-Follow([string]$Plan, [string[]]$More = @()) {
    $o = & pwsh -NoProfile -File $Follow -PlanFile $Plan -Cycle 1 @More 2>&1 | Out-String
    return @{ Exit = $LASTEXITCODE; Out = $o }
  }

  # exactly ONE new unit (+ one edit) followed with -Root
  $p1 = New-MiniPlan $FX (Unit3 $FX 'OnlyNew') (@(Head4 $FX) + $okEdit)
  $r = Run-Follow $p1 @('-Root', $FXR)
  Check '-Root with exactly one new unit and one edit: exit 0' ($r.Exit -eq 0) $r.Out
  Check '-Root one new unit: file created under the new root' (Test-Path (Join-Path $FXR 'OnlyNew.pas'))
  Check '-Root one new unit: original root untouched' (-not (Test-Path (Join-Path $FX 'OnlyNew.pas')))
  # exactly one new unit and no edits
  $p1b = New-MiniPlan $FX (Unit3 $FX 'OnlyNew2') @()
  $r = Run-Follow $p1b @('-Root', $FXR)
  Check '-Root with exactly one new unit and no edits: exit 0' ($r.Exit -eq 0) $r.Out

  # every REFUSE exits 2
  $cases = [ordered]@{
    'unparseable edit step beside a valid one' = (New-MiniPlan $FX @() (@(Head4 $FX) + $okEdit + @('E2. Frobnicate line 3.')))
    'anchor line beyond EOF'                   = (New-MiniPlan $FX @() (@(Head4 $FX) + @('E1. After line 99 (`x`), insert:', '```', '// y', '```')))
    'current-text mismatch'                    = (New-MiniPlan $FX @() (@(Head4 $FX) + @('E1. Replace line 1. Current text:', '```', 'not the text', '```', 'New text:', '```', 'unit Z;', '```')))
    'new unit already exists'                  = (New-MiniPlan $FX (Unit3 $FX 'Existing') @())
    'no mechanical steps'                      = (New-MiniPlan $FX @() @())
  }
  foreach ($k in $cases.Keys) {
    $r = Run-Follow $cases[$k]
    Check "REFUSE exits 2: $k" (($r.Exit -eq 2) -and ($r.Out -match 'REFUSE')) ("exit=" + $r.Exit + " " + $r.Out)
  }
  $r = Run-Follow $p1 @()
  $r = & pwsh -NoProfile -File $Follow -PlanFile $p1 -Cycle 7 2>&1 | Out-String
  Check 'REFUSE exits 2: cycle not in plan' (($LASTEXITCODE -eq 2) -and ($r -match 'REFUSE: cycle 7')) $r
} finally {
  Pop-Location
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
