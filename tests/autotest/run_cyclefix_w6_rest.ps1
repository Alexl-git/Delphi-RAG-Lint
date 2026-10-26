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
  return @{ Exit = $p.ExitCode; Text = [IO.File]::ReadAllText($o); Verdict = $verdict; Refusals = $refusals; Root = $root }
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
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
