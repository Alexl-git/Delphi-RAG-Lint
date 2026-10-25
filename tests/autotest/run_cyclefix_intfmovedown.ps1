<#
  run_cyclefix_intfmovedown.ps1 -- recipe A3-a (plan 2026-10-25-cycles-fix-refusal-recipes.md):
  an INTERFACE uses entry between two units of a cycle whose interface section uses nothing of the
  partner is decided from what the IMPLEMENTATION needs -- moved down to the implementation uses
  (the implementation uses the partner) or removed (nothing uses it) -- instead of refusing Part A
  with `unresolved-edge`. A lexical scan of the interface section runs first: an identifier there
  (outside comments and strings) that names an interface export of the partner keeps the refusal
  and names the identifier and line (the index missed a use: an extractor gap, not a move).

  Fixture tests\fixtures\cyclefix\intfmovedown: Alpha (interface uses Beta, only the implementation
  calls BetaValue) and Beta (implementation uses Alpha). Variants edit Alpha.pas:
    move     -- `Result := BetaValue;`                          -> MOVE, no refusal
    remove   -- `Result := 1;` (nothing of Beta used at all)    -> REMOVE, no refusal
    comment  -- move + `{ BetaLimit }` and `// BetaLimit` in the interface -> still MOVE (a comment
                is not a use)
    code     -- move + `const CAlias = BetaLimit;` inside an inactive `{$IFDEF}` of the interface
                (the index records no ref; the text shows one) -> refused `unresolved-edge`,
                naming `BetaLimit` and its line (read from the SOURCE marker {BAD})
  move and remove are also FOLLOWED (tools\follow-cycle-plan.ps1) on a copy, re-indexed: move leaves
  an implementation-only group, remove leaves no group; and (RAD Studio present) both followed
  copies BUILD and print what the untouched copy prints.
  POSITIVE CONTROL: `code` differs from `move` by one interface edit and must refuse; `move` must
  not -- a rule that moves everything fails `code`, one that refuses everything fails `move`.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-cyclefix-intfmovedown-$PID"
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
$Exe     = (Resolve-Path $Exe).Path
$Repo    = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Fixture = Join-Path $Repo 'tests\fixtures\cyclefix\intfmovedown'
$RsVars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$Ascii   = [Text.Encoding]::ASCII

function Set-Text([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), $Ascii)
}

# Copies the fixture to <WorkDir>\<Tag>, filling Alpha.pas's {IMPL-USE} and {INTF-EXTRA} slots.
function New-Case([string]$Tag, [string]$ImplUse, [string]$IntfExtra) {
  $root = Join-Path $WorkDir $Tag
  New-Item -ItemType Directory -Force $root | Out-Null
  Get-ChildItem $Fixture -File | ForEach-Object { Copy-Item $_.FullName (Join-Path $root $_.Name) -Force }
  $a = Join-Path $root 'Alpha.pas'
  Set-Text $a ([IO.File]::ReadAllText($a).Replace('{IMPL-USE}', $ImplUse).Replace('{INTF-EXTRA}', $IntfExtra))
  return $root
}

function Invoke-Engine([string[]]$Arguments, [string]$Tag) {
  $o = Join-Path $WorkDir "$Tag.out"; $e = Join-Path $WorkDir "$Tag.err"
  $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
    -ArgumentList $Arguments -RedirectStandardOutput $o -RedirectStandardError $e
  return @{ Exit = $p.ExitCode; Out = [IO.File]::ReadAllText($o); File = $o }
}

function Index-Case([string]$Root, [string]$Tag) {
  $db = Join-Path $WorkDir "$Tag.sqlite"
  if (Test-Path $db) { [IO.File]::Delete($db) }
  $ix = Invoke-Engine @('index', '--project', ('"' + (Join-Path $Root 'IntfMoveDown.dproj') + '"'), '--db', ('"' + $db + '"')) "$Tag-index"
  Check "$Tag indexed" ($ix.Exit -eq 0) "exit=$($ix.Exit)"
  return $db
}

# --fix dry run (no compile): the refusals of cycle 1 as objects.
function Get-Refusals([string]$Root, [string]$Db, [string]$Tag) {
  $js = Invoke-Engine @('cycles', '--fix', '--project', ('"' + (Join-Path $Root 'IntfMoveDown.dproj') + '"'), '--db', ('"' + $Db + '"'),
    '--no-compile', '--format', 'json') "$Tag-fix"
  try { return @(($js.Out | ConvertFrom-Json).cycles | ForEach-Object { $_.refusals }) } catch { Check "$Tag fix json parses" $false $js.Out; return @() }
}

function Invoke-Build([string]$Root) {
  $bat = Join-Path $WorkDir ('build-' + (Split-Path $Root -Leaf) + '.bat')
  $log = "$bat.log"
  $lines = @('@echo off', ('call "{0}"' -f $RsVars), ('cd /d "{0}"' -f $Root),
    ('msbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal "{0}" > "{1}" 2>&1' -f (Join-Path $Root 'IntfMoveDown.dproj'), $log),
    ('>> "{0}" echo BUILD_EXITCODE=%ERRORLEVEL%' -f $log))
  [IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), $Ascii)
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -NoNewWindow -Wait | Out-Null
  $text = if (Test-Path $log) { [IO.File]::ReadAllText($log) } else { '' }
  $errors = @([regex]::Matches($text, '(?m)^.*\b(error|fatal) [EF]\d{4}\b.*$') | ForEach-Object { $_.Value.Trim() } | Select-Object -Unique)
  $exeP = Join-Path $Root 'Win64\Debug\IntfMoveDown.exe'
  $out = '<no exe>'
  if (Test-Path $exeP) {
    Start-Process -FilePath $exeP -WorkingDirectory (Split-Path $exeP) -NoNewWindow -Wait `
      -RedirectStandardOutput "$exeP.stdout" -RedirectStandardError "$exeP.stderr" | Out-Null
    $out = [IO.File]::ReadAllText("$exeP.stdout")
  }
  return @{ Ok = ($text -match 'BUILD_EXITCODE=0') -and ($errors.Count -eq 0); Errors = ($errors -join ' | '); Out = $out }
}

# A decided case: no refusal, the plan says the verdict, the follower applies it, the re-index shows
# pAfter ('impl' = an implementation-only group, 'none' = no group), and the followed copy builds.
function Test-Decided([string]$Tag, [string]$ImplUse, [string]$IntfExtra, [string]$Verdict, [string]$After) {
  Write-Host "== $Tag (decided: $Verdict)" -ForegroundColor Cyan
  $root = New-Case $Tag $ImplUse $IntfExtra
  $db = Index-Case $root $Tag
  $refs = @(Get-Refusals $root $db $Tag)
  $ue = @($refs | Where-Object { $_.kind -eq 'unresolved-edge' })
  Check "$Tag d1 no unresolved-edge refusal" ($ue.Count -eq 0) (($ue | ForEach-Object { "$($_.symbol): $($_.reason)" }) -join ' | ')
  Check "$Tag d2 no refusal at all" ($refs.Count -eq 0) (($refs | ForEach-Object { "$($_.kind) $($_.symbol)" }) -join ' | ')
  $pl = Invoke-Engine @('cycles', '--db', ('"' + $db + '"'), '--plan', '--library-db', 'none') "$Tag-plan"
  $want = if ($Verdict -eq 'move') { '**move** it from the interface uses to the implementation uses' } else { '**remove** it from the interface uses' }
  Check "$Tag d3 the plan says: $want" ($pl.Out.Contains('`Alpha.pas` / `Beta`') -and $pl.Out.Contains($want)) ''
  if (Test-Path $RsVars) {
    $b0 = Invoke-Build $root
    Check "$Tag d4 the untouched copy builds" $b0.Ok $b0.Errors
  }
  $work = Join-Path $WorkDir "$Tag-followed"
  New-Item -ItemType Directory -Force $work | Out-Null
  Get-ChildItem $root -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } | ForEach-Object { Copy-Item $_.FullName (Join-Path $work $_.Name) -Force }
  $fo = & pwsh -NoProfile -File (Join-Path $Repo 'tools\follow-cycle-plan.ps1') -PlanFile $pl.File -Cycle 1 -Root $work 2>&1 | Out-String
  Check "$Tag d5 the follower applies cycle 1 (exit 0)" ($LASTEXITCODE -eq 0) ($fo.Trim() -replace "`r?`n", ' | ')
  $at = [IO.File]::ReadAllText((Join-Path $work 'Alpha.pas'))
  $implAt = [regex]::Match($at, '(?m)^implementation\b').Index
  $intf = $at.Substring(0, $implAt)
  Check "$Tag d6 Alpha's interface uses no longer names Beta" ($intf -notmatch '(?m)^\s*,?\s*Beta\b') ''
  $implUses = [regex]::IsMatch($at.Substring($implAt), '^implementation\s+uses\s+Beta\s*;')
  Check "$Tag d7 Alpha's implementation uses Beta: $($Verdict -eq 'move')" ($implUses -eq ($Verdict -eq 'move')) ''
  $db2 = Index-Case $work "$Tag-after"
  $cy = Invoke-Engine @('cycles', '--db', ('"' + $db2 + '"'), '--library-db', 'none') "$Tag-after-cycles"
  if ($After -eq 'impl') {
    Check "$Tag d8 an implementation-only group remains" ($cy.Out -match '\[2 units\].*implementation-only') ($cy.Out.Trim() -replace "`r?`n", ' | ')
  } else {
    Check "$Tag d8 no group remains" ($cy.Out -match 'No circular unit dependencies found') ($cy.Out.Trim() -replace "`r?`n", ' | ')
  }
  if (Test-Path $RsVars) {
    $b1 = Invoke-Build $work
    Check "$Tag d9 the followed copy builds" $b1.Ok $b1.Errors
    Check "$Tag d10 it prints what the untouched copy prints" (($b1.Out -ne '<no exe>') -and ($b1.Out -ceq $b0.Out)) "'$($b1.Out.Trim())' vs '$($b0.Out.Trim())'"
  } else { Write-Host '  (RAD Studio not installed: build checks skipped)' -ForegroundColor Yellow }
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  Test-Decided 'move' 'BetaValue' '' 'move' 'impl'
  Test-Decided 'remove' '1' '' 'remove' 'none'
  Test-Decided 'comment' 'BetaValue' "`r`n{ BetaLimit is Beta's; this comment is not a use }`r`n// BetaLimit`r`n" 'move' 'impl'

  Write-Host '== code (refused: the text shows a use the index did not record)' -ForegroundColor Cyan
  $root = New-Case 'code' 'BetaValue' "`r`n{`$IFDEF DRAGLINT_A3_NEVER}`r`nconst`r`n  CAlias = BetaLimit; {BAD}`r`n{`$ENDIF}`r`n"
  $src = [IO.File]::ReadAllLines((Join-Path $root 'Alpha.pas'))
  $bad = 0; for ($k = 0; $k -lt $src.Count; $k++) { if ($src[$k].Contains('{BAD}')) { $bad = $k + 1 } }
  Check 'code ctl the {BAD} marker is in Alpha.pas' ($bad -gt 0) "line=$bad"
  $db = Index-Case $root 'code'
  $q = Invoke-Engine @('query', 'find-callers', '--name', 'BetaLimit', '--db', ('"' + $db + '"')) 'code-q'
  Check 'code ctl the index records no use of BetaLimit in Alpha.pas' ($q.Out -notmatch 'Alpha\.pas') ($q.Out.Trim() -replace "`r?`n", ' | ')
  $refs = @(Get-Refusals $root $db 'code')
  $ue = @($refs | Where-Object { $_.kind -eq 'unresolved-edge' -and $_.symbol -eq 'alpha -> beta' })
  Check 'code r1 alpha -> beta is refused unresolved-edge' ($ue.Count -eq 1) (($refs | ForEach-Object { "$($_.kind) $($_.symbol)" }) -join ' | ')
  if ($ue.Count -eq 1) {
    Check 'code r2 the refusal names BetaLimit' ($ue[0].reason.Contains('`BetaLimit`')) $ue[0].reason
    Check "code r3 the refusal names line $bad" ([int]$ue[0].line -eq $bad) "line=$($ue[0].line)"
  }
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
