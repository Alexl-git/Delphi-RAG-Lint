# run_cyclefix_shop.ps1 -- lane v1521 SHOPDEMO: the circular-uses article's Shop project as a fixture
# (tests\cyclefix\shop: Shop.dpr + AppMain / Orders / Stock / Reports, one hub-shaped implementation-only group).
# Runs the article's commands on fresh copies and asserts what the article shows. Real dcc proves --apply.
#
#   c0  positive control: the cycle IS found before the fix (1 group, 4 units, 6 implementation edges)
#   c1  cycles --hub names appmain as the hub (spoke->hub surface: var AppMainForm 7 refs, 4 member names)
#   c2  --fix --hub-surface dry run: exit 0, Verdict mechanical, no source written
#   c3  --apply: exit 0, 5 files written (1 new), compile ok, prediction verified, 4 backups
#   c4  the fix removes the cycle: cycles prints "No circular unit dependencies found."
#   c5  determinism: a second fresh copy gives byte-identical written sources
#   n1  `with AppMainForm do` in Stock: refused (with-member, hub-surface-group-stays), exit 1, sources unchanged
#   n2  a line calling an undeclared routine: refused dirty-baseline, exit 1, sources unchanged
#   n3  AddThree(AppMainForm.OrderCount) (var parameter): refused member-write (E2197) up front since 1.52, exit 1, sources unchanged
#       (the article's 1.51.2 text had the compile gate catch this; the rollback itself is run_cyclefix_compile_gate.ps1)
#
# Usage: powershell -File run_cyclefix_shop.ps1 [-Exe <drag-lint.exe>] [-WorkDir <dir>] [-CaptureDir <dir>] [-KeepWorkDir]
#   -CaptureDir saves the raw stdout / stderr / exit code of every command (article re-capture).
param(
  [string]$Exe        = '',
  [string]$WorkDir    = "$env:TEMP\drag-lint-cyclefix-shop-$PID",
  [string]$CaptureDir = '',
  [string]$RsVars     = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat',
  [switch]$KeepWorkDir
)
# Defaults that need the script path are resolved HERE, not in param() (PS5 -File leaves $PSScriptRoot empty there).
if (-not $Exe) { $Exe = $(if (Test-Path -LiteralPath "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe") { "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" } else { "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }) }
$ErrorActionPreference = 'Stop'
$script:Failed = $false; $script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $RsVars)) { Write-Host "SKIP: no rsvars.bat ($RsVars)" -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe   = (Resolve-Path $Exe).Path
$Repo  = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Ascii = [Text.Encoding]::ASCII
$script:N = 0
New-Item -ItemType Directory -Force $WorkDir | Out-Null
if ($CaptureDir) { New-Item -ItemType Directory -Force $CaptureDir | Out-Null }

function Edit-Text([string]$Path, [string]$From, [string]$To) {
  $t = [IO.File]::ReadAllText($Path, $Ascii)
  $f = $From -replace "`r?`n", "`r`n"
  if (-not $t.Contains($f)) { throw "patch anchor not found in ${Path}: $From" }
  [IO.File]::WriteAllText($Path, $t.Replace($f, ($To -replace "`r?`n", "`r`n")), $Ascii)
}
function Get-Sha([string]$Path) {
  $h = [Security.Cryptography.SHA256]::Create()
  try { return [BitConverter]::ToString($h.ComputeHash([IO.File]::ReadAllBytes($Path))) } finally { $h.Dispose() }
}
function Get-SrcHash([string]$Dir) {
  return ((Get-ChildItem $Dir -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } | Sort-Object Name |
    ForEach-Object { '{0}={1}' -f $_.Name, (Get-Sha $_.FullName) }) -join ';')
}
# A fresh copy of the fixture (optionally patched), indexed into <copy>\_D-RAG\Shop.sqlite like the article.
function New-Shop([string]$Tag, [scriptblock]$Patch = $null) {
  $root = Join-Path $WorkDir ("{0}-{1}" -f (++$script:N), $Tag)
  New-Item -ItemType Directory -Force "$root\_D-RAG" | Out-Null
  Get-ChildItem (Join-Path $Repo 'tests\cyclefix\shop') -File | ForEach-Object { Copy-Item $_.FullName (Join-Path $root $_.Name) }
  if ($Patch) { & $Patch $root }
  $null = Invoke-Dl $root "$Tag-index" @('index', '--project', 'Shop.dproj', '--db', '_D-RAG\Shop.sqlite', '--library-db', 'none')
  return $root
}
# Runs drag-lint in the project folder; stdout and stderr kept apart (the article shows both).
function Invoke-Dl([string]$Root, [string]$Label, [string[]]$A) {
  $o = Join-Path $WorkDir "$Label.out"; $e = Join-Path $WorkDir "$Label.err"
  $q = ($A | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
  $p = Start-Process -FilePath $Exe -ArgumentList $q -WorkingDirectory $Root -Wait -PassThru -NoNewWindow -RedirectStandardOutput $o -RedirectStandardError $e
  $r = @{ Exit = $p.ExitCode; Out = ([IO.File]::ReadAllText($o)); Err = ([IO.File]::ReadAllText($e)) }
  if ($CaptureDir) {
    [IO.File]::WriteAllText((Join-Path $CaptureDir "$Label.txt"),
      ("drag-lint {0}`r`n--- exit {1}`r`n--- stdout`r`n{2}`r`n--- stderr`r`n{3}" -f $q, $r.Exit, $r.Out, $r.Err), $Ascii)
  }
  return $r
}
function Get-Cycles([string]$Root, [string]$Label, [string[]]$Extra = @()) {
  return (Invoke-Dl $Root $Label (@('cycles', '--db', '_D-RAG\Shop.sqlite', '--format', 'text', '--library-db', 'none') + $Extra))
}
function Invoke-Fix([string]$Root, [string]$Label, [switch]$Apply) {
  $a = @('cycles', '--fix', '--hub-surface', '--project', 'Shop.dproj', '--db', '_D-RAG\Shop.sqlite', '--cycle', '1', '--platform', 'win64', '--library-db', 'none')
  if ($Apply) { $a += '--apply' }
  return (Invoke-Dl $Root $Label $a)
}

try {
  # ---- c0 / c1: the cycle exists before the fix (positive control for every "no cycle" assertion below)
  Write-Host "== before the fix"
  $a = New-Shop 'main'
  $h0 = Get-SrcHash $a
  $c0 = Get-Cycles $a 'step1-cycles'
  Check 'c0 cycle found: 1 group, 4 units, implementation-only' ($c0.Exit -eq 0 -and $c0.Out -match '1 circular unit group\(s\) found' -and $c0.Out -match '\[4 units\] reports <-> stock <-> orders <-> appmain' -and $c0.Out -match 'implementation-only') $c0.Out
  $c0e = Get-Cycles $a 'step1-cycles-edges' @('--edges')
  Check 'c0 six implementation edges' (([regex]::Matches($c0e.Out, '\[implementation\]')).Count -eq 6) $c0e.Out
  $c1 = Get-Cycles $a 'step2-cycles-hub' @('--hub')
  Check 'c1 hub is appmain, AppMainForm surface 7 refs / 4 members' ($c1.Out -match 'hub appmain:' -and $c1.Out -match 'var AppMainForm 7 refs in 3 units \(4 member names: Note 4, OrderCount 3, Log 1, Ready 1\)') $c1.Out
  $null = Invoke-Dl $a 'step3-plan' @('cycles', '--plan', '--project', 'Shop.dproj', '--db', '_D-RAG\Shop.sqlite', '--format', 'text', '--library-db', 'none')
  $null = Invoke-Dl $a 'step3b-fix-older-planner' @('cycles', '--fix', '--project', 'Shop.dproj', '--db', '_D-RAG\Shop.sqlite', '--platform', 'win64', '--format', 'text', '--library-db', 'none')
  $null = Invoke-Dl $a 'step4-causes-json' @('cycles', '--causes', '--format', 'json', '--hub-surface', '--project', 'Shop.dproj', '--db', '_D-RAG\Shop.sqlite', '--library-db', 'none')
  $h1 = Get-SrcHash $a
  Check 'c0 reading and planning wrote no source' ($h0 -eq $h1)

  # ---- c2: dry run
  Write-Host "== dry run"
  $d = Invoke-Fix $a 'step5-fix-dryrun'
  Check 'c2 dry run: exit 0, Verdict mechanical' ($d.Exit -eq 0 -and $d.Out -match 'Verdict: mechanical \(dry run') ($d.Out + $d.Err)
  Check 'c2 dry run wrote no source' ((Get-SrcHash $a) -eq $h0)

  # ---- c3 / c4: apply, then ask again
  Write-Host "== apply"
  $ap = Invoke-Fix $a 'step6-fix-apply' -Apply
  Check 'c3 apply: exit 0, 5 files written (1 new), compile ok' ($ap.Exit -eq 0 -and $ap.Out -match 'Applied: 5 file\(s\) written, 1 new; compile ok') ($ap.Out + $ap.Err)
  Check 'c3 prediction verified by the re-indexed cycles' ($ap.Out -match 'Verified: the re-indexed `cycles` output matches the prediction')
  Check 'c3 four .BCK1 backups and AppMain.Hub.pas' ((Get-ChildItem $a -Filter '*.BCK1').Count -eq 4 -and (Test-Path (Join-Path $a 'AppMain.Hub.pas')))
  $c4 = Get-Cycles $a 'step7-cycles-after'
  Check 'c4 no cycle left after the fix' ($c4.Exit -eq 0 -and $c4.Out -match 'No circular unit dependencies found\.') $c4.Out
  Check 'c4 spokes use AppMain.Hub, not AppMain' (([IO.File]::ReadAllText((Join-Path $a 'Orders.pas'))) -match 'AppMain\.Hub' -and -not (([IO.File]::ReadAllText((Join-Path $a 'Orders.pas'))) -match 'uses\s+System\.SysUtils, AppMain;'))

  # ---- c5: determinism
  Write-Host "== determinism"
  $b = New-Shop 'repeat'
  $null = Invoke-Fix $b 'step8-repeat-dryrun'
  $bp = Invoke-Fix $b 'step8-repeat-apply' -Apply
  $same = $true
  foreach ($f in 'AppMain.pas', 'AppMain.Hub.pas', 'Orders.pas', 'Stock.pas', 'Reports.pas') {
    if ((Get-Sha (Join-Path $a $f)) -ne (Get-Sha (Join-Path $b $f))) { $same = $false }
  }
  Check 'c5 written sources byte-identical on two fresh copies' ($bp.Exit -eq 0 -and $same)

  # ---- refusals: each starts from a fresh copy with one change, runs the full --apply, sources must not change
  Write-Host "== refusals"
  $w = New-Shop 'with' { param($r) Edit-Text (Join-Path $r 'Stock.pas') "  if AppMainForm.Ready then`n    AppMainForm.Note('stock checked');" "  with AppMainForm do`n    if Ready then`n      Note('stock checked');" }
  $hw = Get-SrcHash $w
  $rw = Invoke-Fix $w 'refusal-with-apply' -Apply
  Check 'n1 with-block: refused, exit 1' ($rw.Exit -eq 1 -and $rw.Out -match 'Verdict: refused' -and $rw.Out -match 'with-member' -and $rw.Out -match 'hub-surface-group-stays') ($rw.Out + $rw.Err)
  Check 'n1 sources byte-identical, no AppMain.Hub.pas' ((Get-SrcHash $w) -eq $hw -and -not (Test-Path (Join-Path $w 'AppMain.Hub.pas')))

  $dd = New-Shop 'dirty' { param($r) Edit-Text (Join-Path $r 'Reports.pas') "  AppMainForm.Log.Add('report: ' + IntToStr(AppMainForm.OrderCount) + ' orders');" "  AppMainForm.Log.Add('report: ' + IntToStr(AppMainForm.OrderCount) + ' orders');`n  NoSuchRoutine;" }
  $hd = Get-SrcHash $dd
  $rd = Invoke-Fix $dd 'refusal-dirty-apply' -Apply
  Check 'n2 dirty baseline: refused, exit 1' ($rd.Exit -eq 1 -and $rd.Out -match 'dirty-baseline' -and $rd.Out -match 'NoSuchRoutine') ($rd.Out + $rd.Err)
  Check 'n2 sources byte-identical' ((Get-SrcHash $dd) -eq $hd)

  $vv = New-Shop 'var' { param($r) Edit-Text (Join-Path $r 'Orders.pas') "procedure TakeOrders;`nbegin`n  Inc(AppMainForm.OrderCount, 3);" "procedure AddThree(var pCount: Integer);`nbegin`n  Inc(pCount, 3);`nend;`n`nprocedure TakeOrders;`nbegin`n  AddThree(AppMainForm.OrderCount);" }
  $hv = Get-SrcHash $vv
  $rv = Invoke-Fix $vv 'refusal-var-apply' -Apply
  Check 'n3 var parameter: refused member-write (E2197), group stays, exit 1' ($rv.Exit -eq 1 -and $rv.Out -match 'Verdict: refused' -and $rv.Out -match 'member-write' -and $rv.Out -match 'E2197' -and $rv.Out -match 'hub-surface-group-stays') ($rv.Out + $rv.Err)
  Check 'n3 sources byte-identical, no AppMain.Hub.pas' ((Get-SrcHash $vv) -eq $hv -and -not (Test-Path (Join-Path $vv 'AppMain.Hub.pas')))
}
finally {
  if (-not $KeepWorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { Write-Host "  (work dir not removed: $WorkDir)" } }
}
Write-Host ("`n{0} passed" -f $script:Passed)
if ($script:Failed) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'OK' -ForegroundColor Green
exit 0
