<#
  run_v156_USESFIX.ps1 -- v156 USESFIX: uses-fix moves an interface entry that compiles, whatever
  the shape of its uses clause, and still refuses a move the compiler rejects.

  Defect (docs\INBOX-uses-fix-move-never-verifies.md): with AppMain in the interface uses of the
  Shop demo's Orders.pas, uses-fix answered `skip AppMain (move did not verify / not a clean
  entry)`. Nothing had been compiled: the entry editor took only `Unit,` on its own line, so the
  LAST entry of a clause (`Unit;`) and an entry sharing its line with `uses` never reached verify.

  Every case works on its own COPY of tests\cyclefix\shop:
    A  `uses` / `  AppMain;`             (sole entry on its own line -- the INBOX shape)
    B  `uses AppMain;`                   (sole entry, inline)
    C  `uses System.Classes, AppMain;`   (last entry of a shared line)
    D  `  System.Classes,` / `  AppMain;`(last entry on its own line, after another entry)
       -> dry run prints MOVED, --apply writes it, and the copy is BUILT with dcc64 and RUN
          (real bytes: Shop.exe prints `orders taken: 3`).
    N  NEGATIVE: the index says "implementation only" but the interface needs AppMain (the source
       was edited after the index) -> skipped with `move did not verify` and the compiler's
       message, --apply leaves Orders.pas byte-identical.
    S  SHAPE: `  AppMain; // main form` -> skipped with `not a clean entry`, not "did not verify".
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-v156-usesfix-$PID"
)
. (Join-Path $PSScriptRoot 'lib\WorkDirCleanup.ps1')
try {
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'; $script:Failed = $false; $script:Pass = 0; $script:Fail = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if ($ok) { $script:Pass++ } else { $script:Fail++; $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$RsVars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
if (-not (Test-Path $RsVars)) { Write-Host "FATAL: rsvars.bat not found: $RsVars" -ForegroundColor Red; exit 2 }
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$Shop = (Resolve-Path "$PSScriptRoot\..\cyclefix\shop").Path
$Ascii = [Text.Encoding]::ASCII

function Run([string[]]$a) {
  Push-Location $WorkDir
  try { $o = & { $ErrorActionPreference = 'Continue'; & $Exe @a 2>&1 | ForEach-Object { "$_" } } | Out-String; $rc = $LASTEXITCODE } finally { Pop-Location }
  return @{ Out = $o; Rc = $rc }
}
function Hash([string]$p) { (Get-FileHash $p -Algorithm SHA256).Hash }

# Orders.pas with the given interface uses lines; the implementation keeps System.SysUtils only.
function OrdersText([string[]]$IntfUses, [string]$Decl = 'procedure TakeOrders;', [string]$EndLine = 'end;') {
  $l = @('unit Orders;', '', 'interface', '') + $IntfUses + @('', $Decl, '', 'implementation', '', 'uses', '  System.SysUtils;', '',
         'procedure TakeOrders;', 'begin', '  Inc(AppMainForm.OrderCount, 3);',
         "  AppMainForm.Note('orders taken: ' + IntToStr(AppMainForm.OrderCount));", $EndLine, '', 'end.')
  return (($l -join "`r`n") + "`r`n")
}
function NewCase([string]$Id, [string[]]$IntfUses) {
  $d = Join-Path $WorkDir $Id
  Copy-Item $Shop $d -Recurse
  [IO.File]::WriteAllText((Join-Path $d 'Orders.pas'), (OrdersText $IntfUses), $Ascii)
  $db = Join-Path $d 'Shop.sqlite'
  $null = Run @('index', '--project', (Join-Path $d 'Shop.dproj'), '--db', $db, '--library-db', 'none')
  return @{ Dir = $d; Db = $db; Proj = (Join-Path $d 'Shop.dproj'); Unit = (Join-Path $d 'Orders.pas') }
}
function UsesFix($c, [switch]$Apply) {
  $a = @('uses-fix', $c.Unit, '--project', $c.Proj, '--db', $c.Db, '--platform', 'win64', '--format', 'text')
  if ($Apply) { $a += '--apply' }
  return Run $a
}
# A REAL build of the copy: dcc64 on Shop.dpr, then the exe is run.
function BuildAndRun($c) {
  $out = Join-Path $c.Dir 'out'; New-Item -ItemType Directory $out -Force | Out-Null
  $log = Join-Path $c.Dir 'dcc.log'
  $cmd = "call `"$RsVars`" && cd /d `"$($c.Dir)`" && dcc64 -B -Q -NSSystem -E`"$out`" -NU`"$out`" Shop.dpr > `"$log`" 2>&1"
  $p = Start-Process cmd.exe -ArgumentList '/c', "`"$cmd`"" -Wait -PassThru -WindowStyle Hidden
  $exe = Join-Path $out 'Shop.exe'
  $ran = ''
  if (($p.ExitCode -eq 0) -and (Test-Path $exe)) { $ran = (& $exe 2>&1 | Out-String) }
  return @{ Rc = $p.ExitCode; Built = (Test-Path $exe); Ran = $ran; Log = $log }
}

$Positive = [ordered]@{
  A = @('uses', '  AppMain;')
  B = @('uses AppMain;')
  C = @('uses System.Classes, AppMain;')
  D = @('uses', '  System.Classes,', '  AppMain;')
}
foreach ($id in $Positive.Keys) {
  $c = NewCase $id $Positive[$id]
  $dry = UsesFix $c
  Check "${id}: dry run MOVES AppMain" ($dry.Out -match '(?m)^\s+MOVED\s+AppMain\s+interface -> implementation') ("got: " + ($dry.Out.Trim() -split "`r?`n" | Select-Object -First 2 | Out-String).Trim())
  Check "${id}: no skip line for AppMain" ($dry.Out -notmatch '(?m)^\s+skip\s+AppMain')
  $ap = UsesFix $c -Apply
  Check "${id}: --apply reports 1 move" ($ap.Out -match 'APPLIED 1 move\(s\)')
  $txt = [IO.File]::ReadAllText($c.Unit)
  $impl = $txt.Substring($txt.IndexOf("`r`nimplementation"))
  $intf = $txt.Substring(0, $txt.IndexOf("`r`nimplementation"))
  $live = ($intf -split "`r?`n" | Where-Object { ($_ -notmatch '^\s*//') -and ($_ -match '\bAppMain\b') -and (($_ -replace '\{[^}]*\}', '') -match '\bAppMain\b') })
  Check "${id}: AppMain is gone from the interface and present in the implementation uses" ((-not $live) -and ($impl -match '(?m)^\s*AppMain,\s+\{ drag-lint: moved here \}')) "interface still has: $live"
  Check "${id}: the written file is CRLF, 7-bit" (($txt -notmatch "(?<!`r)`n") -and ($txt -notmatch '[^\x00-\x7F]'))
  $b = BuildAndRun $c
  Check "${id}: the copy BUILDS with dcc64 (Shop.exe written)" ($b.Built -and ($b.Rc -eq 0)) "rc=$($b.Rc) log=$($b.Log)"
  Check "${id}: the built Shop.exe runs" ($b.Ran -match 'orders taken: 3') "got: $($b.Ran.Trim())"
}

# N -- the compiler, not the index, has the last word.
$c = NewCase 'N' @('uses', '  AppMain;')
# Same line count as the indexed text, so every indexed line still points at its entry.
[IO.File]::WriteAllText($c.Unit, (OrdersText @('uses', '  AppMain;') 'procedure TakeOrders; function Main: TAppMain;' 'end; function Main: TAppMain; begin Result:= AppMainForm; end;'), $Ascii)
$ctl = BuildAndRun $c
Check 'N: CONTROL the edited copy builds as it stands (AppMain in the interface)' ($ctl.Built -and ($ctl.Rc -eq 0)) "rc=$($ctl.Rc) log=$($ctl.Log)"
$h0 = Hash $c.Unit
$neg = UsesFix $c -Apply
Check 'N: the move is skipped' (($neg.Out -match '(?m)^\s+skip\s+AppMain') -and ($neg.Out -notmatch 'MOVED')) ("got: " + $neg.Out.Trim())
Check 'N: the reason is the VERIFY half, with the compiler code' ($neg.Out -match 'skip\s+AppMain\s+\(move did not verify: .*E2003') ("got: " + $neg.Out.Trim())
Check 'N: the reason is not the entry shape' ($neg.Out -notmatch 'not a clean entry')
Check 'N: --apply left Orders.pas byte-identical' ((Hash $c.Unit) -eq $h0)

# S -- an entry the editor will not touch says so, and says nothing was compiled.
$c = NewCase 'S' @('uses', '  AppMain; // main form')
$h0 = Hash $c.Unit
$sh = UsesFix $c -Apply
Check 'S: a commented entry line is skipped as "not a clean entry"' ($sh.Out -match 'skip\s+AppMain\s+\(not a clean entry: line 6 ') ("got: " + $sh.Out.Trim())
Check 'S: and is not reported as a failed verify' ($sh.Out -notmatch 'did not verify')
Check 'S: --apply left Orders.pas byte-identical' ((Hash $c.Unit) -eq $h0)

Write-Host ("run_v156_USESFIX: {0} passed, {1} failed" -f $script:Pass, $script:Fail)
if ($script:Failed) { exit 1 } else { exit 0 }
} finally { Remove-WorkDir $WorkDir -Keep:($env:DL_KEEP_WORKDIR -eq '1') }
