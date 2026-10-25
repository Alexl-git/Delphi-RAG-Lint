<#
  run_cyclefix_c3_false_positives.ps1 -- plan C3 (docs\superpowers\plans\2026-10-25-cycles-fix-refusal-recipes.md):
  two refusals of `cycles --plan` that fired on text / names the compiler does not see.

  (a) init-order on a COMMENT. The initialization section of tests\fixtures\cyclefix\initorder names the
      routine `Show` only inside a comment: a multi-line `{ }` block, a `(* *)` block, a one-line `{ }`.
      Each variant is cut by routine-call inversion (mechanical, no `init-order`).
      POSITIVE CONTROLS: the shipped fixture (a real `GStartupDrawing.Show;` call) is still refused
      init-order; so is a copy whose comments are closed and a real call follows them.
  (b) edge-still-used on an inherited class member. tests\fixtures\cyclefix\r1stillused: TR1Form calls
      its inherited class method R1Note; the unit routine R1Title.R1Note of the same name is NOT what it
      calls, so the edge is cut (mechanical, no `edge-still-used`).
      POSITIVE CONTROL: the same copy with TR1Form no longer deriving from TR1Base (R1Note is not in the class
      chain): the bare name binds to the unit routine, two routines are on the edge, and the plan stays
      refused (manual-edit). The plan's edge-still-used wording cannot be reached by this variant: the index
      already binds an inherited R1Note to TR1Base, so only the name-based need list was wrong.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-cyclefix-c3-$PID"
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
$Exe   = (Resolve-Path $Exe).Path
$Repo  = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Fx    = Join-Path $Repo 'tests\fixtures\cyclefix'
$Ascii = [Text.Encoding]::ASCII

function Copy-Tree([string]$From, [string]$To) {
  New-Item -ItemType Directory -Force $To | Out-Null
  Get-ChildItem $From -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $To $_.Name) -Force }
}
function Set-Text([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), $Ascii)
}
function Edit-File([string]$Path, [string]$Old, [string]$New) {
  $t = [IO.File]::ReadAllText($Path)
  if (-not $t.Contains($Old)) { throw "fixture edit: text not found in ${Path}: $Old" }
  Set-Text $Path $t.Replace($Old, $New)
}

# Copies a fixture to a case dir, applies pEdit (scriptblock taking the case root), indexes, plans cycle 1.
function Get-Plan([string]$Fixture, [string]$Dproj, [string]$Tag, [scriptblock]$Edit) {
  $root = Join-Path $WorkDir $Tag
  Copy-Tree (Join-Path $Fx $Fixture) $root
  if ($Edit) { & $Edit $root }
  $db = Join-Path $WorkDir "$Tag.sqlite"
  $null | & $Exe index --project (Join-Path $root $Dproj) --db $db *> (Join-Path $WorkDir "index-$Tag.log")
  $o = Join-Path $WorkDir "plan-$Tag.out"
  $dump = Join-Path $WorkDir "dump-$Tag.txt"
  $env:DRAGLINT_TEST_DUMP_PLAN = $dump
  try {
    $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
      -ArgumentList @('cycles', '--db', ('"' + $db + '"'), '--plan', '--library-db', 'none') `
      -RedirectStandardOutput $o -RedirectStandardError (Join-Path $WorkDir "plan-$Tag.err")
  } finally { $env:DRAGLINT_TEST_DUMP_PLAN = $null }
  $verdict = ''; $refusals = ''
  if (Test-Path $dump) {
    foreach ($l in [IO.File]::ReadAllLines($dump)) {
      $h = @{}
      foreach ($kv in ($l -split "`t")) { $i = $kv.IndexOf('='); if ($i -gt 0) { $h[$kv.Substring(0, $i)] = $kv.Substring($i + 1) } }
      if ($h['cycle'] -eq '1') { $verdict = $h['verdict']; $refusals = $h['refusals'] }
    }
  }
  return @{ Exit = $p.ExitCode; Text = [IO.File]::ReadAllText($o); Verdict = $verdict; Refusals = $refusals }
}

# An edit that removes the real `Show` call from DemoBlueprint's initialization and inserts pText after `initialization`.
function New-InitEdit([string]$Text, [bool]$DropShow) {
  return {
    param($r)
    $f = Join-Path $r 'DemoBlueprint.pas'
    if ($DropShow) { Edit-File $f "  GStartupDrawing.Show;`r`n" '' }
    Edit-File $f "initialization`r`n" "initialization`r`n$Text`r`n"
  }.GetNewClosure()
}

function Test-Mechanical([string]$Tag, $Pl, [string]$Kind) {
  Check "$Tag m0 planned (exit 0)" ($Pl.Exit -eq 0) "exit=$($Pl.Exit)"
  Check "$Tag m1 no refused: $Kind" (-not $Pl.Text.Contains("refused: $Kind")) ([regex]::Match($Pl.Text, "(?m)^.*refused: $Kind.*$").Value)
  Check "$Tag m2 verdict mechanical" ($Pl.Verdict -eq 'mechanical') "[$($Pl.Verdict) / $($Pl.Refusals)]"
}
function Test-Refused([string]$Tag, $Pl, [string]$Kind) {
  Check "$Tag r0 planned (exit 0)" ($Pl.Exit -eq 0) "exit=$($Pl.Exit)"
  Check "$Tag r1 refused: $Kind" ($Pl.Text.Contains("refused: $Kind") -and (($Pl.Refusals -split ',') -contains $Kind)) "[$($Pl.Verdict) / $($Pl.Refusals)]"
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  Write-Host '== (a) init-order: the routine is named in a comment only' -ForegroundColor Cyan
  Test-Mechanical 'brace-multi' (Get-Plan 'initorder' 'InitOrder.dproj' 'brace-multi' (New-InitEdit "  { the drawing`r`n    is opened by Show later }" $true)) 'init-order'
  Test-Mechanical 'paren-star'  (Get-Plan 'initorder' 'InitOrder.dproj' 'paren-star'  (New-InitEdit "  (* the drawing`r`n     is opened by Show later *)" $true)) 'init-order'
  Test-Mechanical 'brace-one'   (Get-Plan 'initorder' 'InitOrder.dproj' 'brace-one'   (New-InitEdit '  { Show is called later }' $true)) 'init-order'
  Test-Refused 'real-call' (Get-Plan 'initorder' 'InitOrder.dproj' 'real-call' $null) 'init-order'
  Test-Refused 'comment-then-call' (Get-Plan 'initorder' 'InitOrder.dproj' 'comment-then-call' (New-InitEdit "  { Show is called below }`r`n  (* and again *)" $false)) 'init-order'

  Write-Host '== (b) edge-still-used: an inherited class member is not the unit routine' -ForegroundColor Cyan
  Test-Mechanical 'inherited' (Get-Plan 'r1stillused' 'R1StillUsed.dproj' 'inherited' $null) 'edge-still-used'
  $unlink = {
    param($r)
    Edit-File (Join-Path $r 'R1Form.pas') 'TR1Form = class(TR1Base)' 'TR1Form = class'
  }
  $nc = Get-Plan 'r1stillused' 'R1StillUsed.dproj' 'not-in-chain' $unlink
  Check 'not-in-chain r0 planned (exit 0)' ($nc.Exit -eq 0) ''
  Check 'not-in-chain r1 still refused (R1Note binds to the unit routine: two routines on the edge)' (($nc.Verdict -eq 'refused') -and ($nc.Refusals -ne '')) "[$($nc.Verdict) / $($nc.Refusals)]"
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
