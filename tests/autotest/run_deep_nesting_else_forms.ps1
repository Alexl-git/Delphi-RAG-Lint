# Guard: deep-nesting must count an if-with-else, and must NOT count an else-if chain.
#
# docs\INBOX-deep-nesting-silent-on-trailing-else-call.md.
#
# An if WITH an else parses as `exprIf` in this grammar. There is no `ifElse`
# node at all -- MaxNest's list counted 'if' and 'ifElse', so the else form
# scored ZERO and the chain-continuation branch was dead code keyed on a node
# type the parser never produces. One trailing else on the innermost statement
# therefore cost a whole level: a routine nested 6 deep measured 5 and, against
# the default max of 5, said nothing at all.
#
# Same family as the kAt / kVar / exprIf "keywords are NAMED nodes" bugs already
# fixed in this tree: code matching on a node type that does not exist.
#
# THE THREE-ARM ISOLATION IS THE POINT. A single silent fixture proves nothing --
# it may simply be under threshold. Six plain / six-with-else / seven plain, side
# by side, is what makes the else the only variable. An earlier triage pass built
# only the middle arm and could not attribute the silence.
#
# AND THE CHAIN ARM MUST EXCEED THE THRESHOLD. `else if` chains are not deeper
# nesting, and the guard that keeps them flat only counts as tested if the chain
# is long enough to fire without it -- a 3-long chain would be silent either way.
#
# Usage: pwsh -File tests/autotest/run_deep_nesting_else_forms.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $RulesDir = "$PSScriptRoot\..\..\rules",
    [string] $WorkDir = "$env:TEMP\drag-lint-deep-nesting-else"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
    $status = if ($Ok) {'PASS'} else {'FAIL'}
    $color  = if ($Ok) {'Green'} else {'Red'}
    Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
    if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
New-Item -ItemType Directory -Force $WorkDir | Out-Null

$Fixture = @'
unit uDN;
interface
procedure SixPlain;
procedure SixTrailingElse;
procedure SevenPlain;
procedure LongElseIfChain;
implementation
procedure SixPlain;
begin
  if A1 then
    if A2 then
      if A3 then
        if A4 then
          if A5 then
            if A6 then Go1;
end;
procedure SixTrailingElse;
begin
  if A1 then
    if A2 then
      if A3 then
        if A4 then
          if A5 then
            if A6 then Go1 else Go2;
end;
procedure SevenPlain;
begin
  if A1 then
    if A2 then
      if A3 then
        if A4 then
          if A5 then
            if A6 then
              if A7 then Go1;
end;
procedure LongElseIfChain;
begin
  if A1 then Go1
  else if A2 then Go2
  else if A3 then Go3
  else if A4 then Go4
  else if A5 then Go5
  else if A6 then Go6
  else if A7 then Go7
  else if A8 then Go8
  else Go9;
end;
end.
'@
$file = Join-Path $WorkDir 'uDN.pas'
[System.IO.File]::WriteAllText($file, (($Fixture -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII)

$out = & $Exe lint $file --rules-dir $RulesDir 2>&1 | Out-String
function DepthOf([string]$Routine) {
  $m = [regex]::Match($out, [regex]::Escape($Routine) + ' nests control structures (\d+) deep')
  if ($m.Success) { [int]$m.Groups[1].Value } else { 0 }
}
$plain6 = DepthOf 'SixPlain'; $else6 = DepthOf 'SixTrailingElse'
$plain7 = DepthOf 'SevenPlain'; $chain = DepthOf 'LongElseIfChain'
Write-Host ("  depths: SixPlain={0} SixTrailingElse={1} SevenPlain={2} LongElseIfChain={3}" -f $plain6,$else6,$plain7,$chain) -ForegroundColor DarkGray

# BASELINE ARMS -- if these stop firing the fixture is under threshold and every
# other arm below becomes meaningless.
Check 'six plain ifs report 6 deep' ($plain6 -eq 6) "got $plain6"
Check 'seven plain ifs report 7 deep' ($plain7 -eq 7) "got $plain7"

# THE DEFECT -- the else form must count exactly the same as the plain form.
Check 'six ifs ending in an if-with-else ALSO report 6 deep' ($else6 -eq 6) "got $else6"
Check 'the else form is not scored lower than the plain form' ($else6 -eq $plain6) "$else6 vs $plain6"

# THE OPPOSITE ERROR -- an else-if chain is not nesting. Deliberately 8 long, so
# it would fire against the default max of 5 if the chain guard regressed.
Check 'an 8-long else-if chain is NOT reported as deep nesting' ($chain -eq 0) "got $chain"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
