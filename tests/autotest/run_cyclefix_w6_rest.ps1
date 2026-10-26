<#
  run_cyclefix_w6_rest.ps1 -- plan docs\superpowers\plans\2026-10-25-cycles-fix-refusal-recipes.md, the
  remainder of W6 (lane CYC-C): C2, C4, C6 and the rest of C7. One fixture variant per case, each
  refused (or mis-handled) before the item, each with a CONTROL that stays refused.

  (C6) lexical robustness of the manual-edit refusals
    c6a `end. { eof }` (a block comment after the final `end.`) on r1extend: mechanical. CONTROL: `end. x` stays refused.
    c6b R2 heritage spread over lines (`class(TComponent` / `)`) on r2extend: mechanical, the interface is appended on
        the closing line. CONTROL: heritage on one line (the shipped fixture) is covered by run_cyclefix_r2.ps1;
        here a heritage whose `)` never closes within the declaration still refuses manual-edit.
    c6c a block comment after the class's `end;` on r2extend: mechanical.
#>
[CmdletBinding()]
param(
  [string]$Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-w6-$PID",
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win64.sqlite'
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
if (-not (Test-Path $LibraryDb)) { Write-Host "SKIP: no platform library DB at $LibraryDb" -ForegroundColor Yellow; exit 0 }
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
  $Old = $Old -replace "`r?`n", "`r`n"
  if (-not $t.Contains($Old)) { throw "fixture edit: text not found in ${Path}: $Old" }
  Set-Text $Path $t.Replace($Old, ($New -replace "`r?`n", "`r`n"))
}

# Copies a fixture, applies pEdit (scriptblock taking the case root), indexes, plans cycle 1 against the library copy.
# Returns the dump fields, the plan text and the case root.
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
      -ArgumentList @('cycles', '--db', ('"' + $db + '"'), '--plan', '--library-db', ('"' + $Lib + '"')) `
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
  return @{ Exit = $p.ExitCode; Text = [IO.File]::ReadAllText($o); Verdict = $verdict; Refusals = $refusals; Root = $root; Out = $o; Dproj = (Join-Path $root $Dproj) }
}
# Applies cycle 1 of a plan with the follower, re-indexes, returns the text `cycles` prints on the result.
function Invoke-FollowAndCycles($Pl, [string]$Tag) {
  $fo = & pwsh -NoProfile -File (Join-Path $Repo 'tools\follow-cycle-plan.ps1') -PlanFile $Pl.Out -Cycle 1 2>&1 | Out-String
  $db = Join-Path $WorkDir "after-$Tag.sqlite"
  $null | & $Exe index --project $Pl.Dproj --db $db *> (Join-Path $WorkDir "index-after-$Tag.log")
  $o = & $Exe cycles --db $db | Out-String
  return @{ Follow = $LASTEXITCODE; Text = $fo; Cycles = $o }
}
function Test-Mechanical( [string]$Tag, $Pl, [string]$Kind) {
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
  $Lib = Join-Path $WorkDir 'library-copy.sqlite'
  Copy-Item $LibraryDb $Lib

  Write-Host '== (c6a) end. followed by a block comment' -ForegroundColor Cyan
  $eofEdit = { param($r) $f = Join-Path $r 'R1Title.pas'; $t = [IO.File]::ReadAllText($f); Set-Text $f ($t.TrimEnd() + " { eof }`r`n") }
  Test-Mechanical 'c6a-eof' (Get-Plan 'r1extend' 'R1Extend.dproj' 'c6a-eof' $eofEdit) 'manual-edit'
  $eofBad = { param($r) $f = Join-Path $r 'R1Title.pas'; $t = [IO.File]::ReadAllText($f); Set-Text $f ($t.TrimEnd() + " x`r`n") }
  Test-Refused 'c6a-eof-bad' (Get-Plan 'r1extend' 'R1Extend.dproj' 'c6a-eof-bad' $eofBad) 'manual-edit'

  Write-Host '== (c6b) R2 heritage over two lines; (c6c) block comment after the class end;' -ForegroundColor Cyan
  $herMulti = { param($r) Edit-File (Join-Path $r 'DemoGagePort.pas') 'TDemoGagePort = class(TComponent)' "TDemoGagePort = class(TComponent`r`n    )" }
  Test-Mechanical 'c6b-heritage' (Get-Plan 'r2extend' 'R2Extend.dproj' 'c6b-heritage' $herMulti) 'manual-edit'
  $herOpen = { param($r) Edit-File (Join-Path $r 'DemoGagePort.pas') 'TDemoGagePort = class(TComponent)' "TDemoGagePort = class(TComponent,`r`n    IUnknown" }
  $herOpenPl = Get-Plan 'r2extend' 'R2Extend.dproj' 'c6b-open' $herOpen
  Check 'c6b-open never mechanical (unbalanced heritage)' ($herOpenPl.Verdict -ne 'mechanical') "[$($herOpenPl.Verdict) / $($herOpenPl.Refusals)]"
  $endCm = { param($r)
    $f = Join-Path $r 'DemoGagePort.pas'; $t = [IO.File]::ReadAllText($f)
    $rx = [regex]'(?m)^  end;'
    Set-Text $f ($rx.Replace($t, '  end; { TDemoGagePort }', 1)) }
  Test-Mechanical 'c6c-endcomment' (Get-Plan 'r2extend' 'R2Extend.dproj' 'c6c-endcomment' $endCm) 'manual-edit'

  Write-Host '== (c2) duplicate-identifier in the leaf: reuse an identical declaration, else the lowest free suffix' -ForegroundColor Cyan
  $ptrSame = {
    param($r)
    Edit-File (Join-Path $r 'R1Title.Untangle.pas') '  TR1TitleStyle = (tsPlain, tsBold);' "  TR1TitleStyle = (tsPlain, tsBold);`n  TR1TitleOfPtr = function(const pId: Integer): string;`nvar`n  R1TitleOfPtr: TR1TitleOfPtr;"
  }
  $c2a = Get-Plan 'r1extend' 'R1Extend.dproj' 'c2a-same' $ptrSame
  Test-Mechanical 'c2a-same' $c2a 'duplicate-identifier'
  Check 'c2a-same reused: the leaf gets no second TR1TitleOfPtr, the consumer calls R1TitleOfPtr' `
    ((-not $c2a.Text.Contains('  TR1TitleOfPtr = function')) -and $c2a.Text.Contains('R1TitleOfPtr(pId)')) ''
  $c2aRun = Invoke-FollowAndCycles $c2a 'c2a'
  Check 'c2a-same followed (exit 0) and no cycle remains' (($c2aRun.Follow -eq 0) -and $c2aRun.Cycles.Contains('No circular unit dependencies found.')) ($c2aRun.Text.Trim() -replace "`r?`n", ' | ')
  $ptrDiff = { param($r) Edit-File (Join-Path $r 'R1Title.Untangle.pas') '  TR1TitleStyle = (tsPlain, tsBold);' "  TR1TitleStyle = (tsPlain, tsBold);`n  TR1TitleOfPtr = Integer;" }
  $c2b = Get-Plan 'r1extend' 'R1Extend.dproj' 'c2b-diff' $ptrDiff
  Test-Mechanical 'c2b-diff' $c2b 'duplicate-identifier'
  Check 'c2b-diff takes the lowest free suffix: TR1TitleOfPtr2 declared, assigned and called' `
    ($c2b.Text.Contains('  TR1TitleOfPtr2 = function(const pId: Integer): string;') -and $c2b.Text.Contains('R1TitleOfPtr2 := R1TitleOf;') -and
     $c2b.Text.Contains('R1TitleOfPtr2(pId)')) ''
  $c2bRun = Invoke-FollowAndCycles $c2b 'c2b'
  Check 'c2b-diff followed (exit 0) and no cycle remains' (($c2bRun.Follow -eq 0) -and $c2bRun.Cycles.Contains('No circular unit dependencies found.')) ($c2bRun.Text.Trim() -replace "`r?`n", ' | ')
  $ptrDiff2 = { param($r) Edit-File (Join-Path $r 'R1Title.Untangle.pas') '  TR1TitleStyle = (tsPlain, tsBold);' "  TR1TitleStyle = (tsPlain, tsBold);`n  TR1TitleOfPtr = Integer;`n  TR1TitleOfPtr2 = Integer;" }
  $c2c = Get-Plan 'r1extend' 'R1Extend.dproj' 'c2c-diff2' $ptrDiff2
  Check 'c2c-diff2 skips a taken suffix: TR1TitleOfPtr3' ($c2c.Text.Contains('  TR1TitleOfPtr3 = function') -and ($c2c.Verdict -eq 'mechanical')) "[$($c2c.Verdict) / $($c2c.Refusals)]"

  Write-Host '== (c4) overloaded-routine: arity-unique binding' -ForegroundColor Cyan
  $ovl = {
    param($r, $extra)
    Edit-File (Join-Path $r 'R1Title.pas') '/// <summary>Title of one item.</summary>' "$extra`n`n/// <summary>Title of one item.</summary>"
  }
  $c4a = Get-Plan 'r1extend' 'R1Extend.dproj' 'c4a-arity' { param($r) & $ovl $r 'function R1TitleOf(const pId, pExtra: Integer): string; overload;' }
  Test-Mechanical 'c4a-arity' $c4a 'overloaded-routine'
  Check 'c4a-arity binds the one-argument overload: type declared with the signature of the call' `
    ($c4a.Text.Contains('  TR1TitleOfPtr = function(const pId: Integer): string;')) ''
  $c4b = Get-Plan 'r1extend' 'R1Extend.dproj' 'c4b-same-arity' { param($r) & $ovl $r 'function R1TitleOf(const pName: string): string; overload;' }
  Test-Refused 'c4b-same-arity' $c4b 'overloaded-routine'
  $c4c = Get-Plan 'r1extend' 'R1Extend.dproj' 'c4c-default' { param($r) & $ovl $r 'function R1TitleOf(const pId, pExtra: Integer; pMore: Integer = 0): string; overload;' }
  Test-Refused 'c4c-default' $c4c 'overloaded-routine'

  Write-Host '== (c7) qualified use and assigned value of the inverted routine' -ForegroundColor Cyan
  $callLine = "  Writeln(Format('[form] %s', [R1TitleOf(pId)]));"
  $addLine = { param($r, $extra) Edit-File (Join-Path $r 'R1Form.pas') "  Writeln(Format('[form] %s', [R1TitleOf(pId)]));" "  Writeln(Format('[form] %s', [R1TitleOf(pId)]));`n$extra" }
  $c7a = Get-Plan 'r1extend' 'R1Extend.dproj' 'c7a-qualified' { param($r) & $addLine $r '  Writeln(R1Title.R1TitleOf(pId + 1));' }
  Test-Mechanical 'c7a-qualified' $c7a 'qualified-ref'
  Check 'c7a-qualified redirected to the pointer' ($c7a.Text.Contains('Writeln(R1TitleOfPtr(pId + 1));')) ''
  $c7aRun = Invoke-FollowAndCycles $c7a 'c7a'
  Check 'c7a-qualified followed (exit 0) and no cycle remains' (($c7aRun.Follow -eq 0) -and $c7aRun.Cycles.Contains('No circular unit dependencies found.')) ($c7aRun.Text.Trim() -replace "`r?`n", ' | ')
  Test-Refused 'c7a-other-member' (Get-Plan 'r1extend' 'R1Extend.dproj' 'c7a-other' { param($r) & $addLine $r '  Writeln(R1Title.R1TitleCount);' }) 'qualified-ref'
  Test-Refused 'c7a-address' (Get-Plan 'r1extend' 'R1Extend.dproj' 'c7a-addr' { param($r) & $addLine $r '  Fn := @R1Title.R1TitleOf;' }) 'qualified-ref'
  $c7b = Get-Plan 'r1extend' 'R1Extend.dproj' 'c7b-value' { param($r) & $addLine $r '  Fn := R1TitleOf;' }
  Test-Mechanical 'c7b-value' $c7b 'routine-not-called'
  Check 'c7b-value redirected to the pointer' ($c7b.Text.Contains('Fn := R1TitleOfPtr;')) ''
  Test-Refused 'c7b-address' (Get-Plan 'r1extend' 'R1Extend.dproj' 'c7b-addr' { param($r) & $addLine $r '  Fn := @R1TitleOf;' }) 'routine-not-called'
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
