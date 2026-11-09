<#
  run_cyclefix_ctorwide_dcc.ps1 -- E-CTORINV-LOADER phase 1: `cycles --plan|--fix --ctor-wide`, the wider constructor
  inversion whitelist, OFF by default. Fixture tests\fixtures\cyclefix\ctorwide has the four shapes that refused all 14
  Loader sites, measured 2026-11-06 (docs\superpowers\specs\2026-11-06-ctorinv-loader.md):
    w1 a store to a public field through the slot (`FDm_A  .GId := pId`, the 12 TdmX)
    w2 a dead field named like the segment of a dotted unit in `uses` (`Proc` / `Wide.Proc`, TFolderProcessor)
    w3 an `override` dragged into the base class by an unresolved `.Execute` of another class (TFolderWorker)
    w5 a data module listed in the .dproj with children: the leaf's line must not land inside the element
    w4 `L.Add(TX.Create(..))`, `L[i].InheritedMember`, `L.OwnsObjects := ..`, `var S: TX := L[0]` on a list that switches (TFolderWorker)

  ACCEPTED: untouched copy built and run; `--fix --apply --ctor-wide` (real dcc gate) on a second copy; the applied copy
  builds; stdout BYTE-identical, including the line a .dfm OnCreate prints (the module still streams through the base).
  OFF: without the flag the same tree still refuses ctor-inversion-surface: the default did not move.
  HUB: an implementation edge hub -> module kept: every site still applies and compiles, the cycle STAYS: the three
    counts (planned / applied+compiled / cycle cut) are different numbers, and this asserts so.
  REFUSED with the flag: n1 a library property written through the slot, n2 a temporary, n3 `L.Extract`, n4 `L.First`, n5 a .dfm-streamed field read through the slot.
  POSITIVE CONTROLS: pc1 the applied tree with a pointer assignment removed still compiles and stdout DIFFERS.
    The RED run is any engine without the flag: wide1 fails on it (and on a build with one of w1-w4 taken out).
#>
[CmdletBinding()]
param(
  [string]$Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-ctorwide-$PID",
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win64.sqlite',
  [switch]$KeepWorkDir
)
$ErrorActionPreference = 'Stop'
$RsVars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
if (-not (Test-Path $RsVars)) { Write-Host 'SKIP: RAD Studio not installed' -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $LibraryDb)) { Write-Host "SKIP: no platform library DB at $LibraryDb" -ForegroundColor Yellow; exit 0 }
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
$Fix   = Join-Path $Repo 'tests\fixtures\cyclefix\ctorwide'
$Ascii = [Text.Encoding]::ASCII
$Units = @('Wide.Sink', 'WideDm', 'Wide.Proc', 'Wide.Worker', 'WideHub')

function Edit-File([string]$Path, [string]$Old, [string]$New) {
  $t = [IO.File]::ReadAllText($Path)
  $n = $t.Replace(($Old -replace "`r?`n", "`r`n"), ($New -replace "`r?`n", "`r`n"))
  if ($n -ceq $t) { throw "fixture edit did not apply in $Path : $Old" }
  [IO.File]::WriteAllText($Path, $n, $Ascii)
}
function New-Tree([string]$Dir) {
  New-Item -ItemType Directory -Force $Dir | Out-Null
  Copy-Item (Join-Path $Fix '*') $Dir -Force
  $pj = [IO.File]::ReadAllText((Join-Path $Repo 'tests\fixtures\cyclefix\r1extend\R1Extend.dproj'))
  $pj = $pj.Replace('R1Extend', 'CtorWide').Replace('{5A1C7E94-2B6D-4F03-8C9A-7E3B1D0F2A85}', '{2E6D1F70-8B3C-4A59-9D21-6C7F0A4E3B18}')
  $pj = [regex]::Replace($pj, '(?m)^\s*<DCCReference Include="[^"]+"/>\r?\n', '')
  $refs = ($Units | ForEach-Object { if ($_ -ceq 'WideDm') { "<DCCReference Include=`"$_.pas`">`r`n            <Form>WideDmInst</Form>`r`n            <DesignClass>TDataModule</DesignClass>`r`n        </DCCReference>" } else { "<DCCReference Include=`"$_.pas`"/>" } }) -join "`r`n        "
  $pj = $pj.Replace('</DelphiCompile>', "</DelphiCompile>`r`n        $refs")
  [IO.File]::WriteAllText((Join-Path $Dir 'CtorWide.dproj'), ($pj -replace "`r?`n", "`r`n"), $Ascii)
}
function Invoke-Build([string]$Dproj) {
  $dir = Split-Path $Dproj
  $bat = Join-Path $WorkDir ('build-' + (Split-Path $dir -Leaf) + '.bat')
  $log = "$bat.log"
  $lines = @('@echo off', ('call "{0}"' -f $RsVars), ('cd /d "{0}"' -f $dir),
    ('msbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal "{0}" > "{1}" 2>&1' -f $Dproj, $log),
    ('>> "{0}" echo BUILD_EXITCODE=%ERRORLEVEL%' -f $log))
  [IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), $Ascii)
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -NoNewWindow -Wait | Out-Null
  $text = if (Test-Path $log) { [IO.File]::ReadAllText($log) } else { '' }
  $errors = @([regex]::Matches($text, '(?m)^.*\b(error|fatal) [EF]\d{4}\b.*$') | ForEach-Object { $_.Value.Trim() } | Select-Object -Unique)
  return @{ Ok = ($text -match 'BUILD_EXITCODE=0') -and ($errors.Count -eq 0); Errors = ($errors -join ' | ') }
}
function Invoke-Program([string]$Dproj) {
  $exeP = Join-Path (Split-Path $Dproj) 'Win64\Debug\CtorWide.exe'
  if (-not (Test-Path $exeP)) { return '<no exe>' }
  $o = "$exeP.stdout"
  Start-Process -FilePath $exeP -WorkingDirectory (Split-Path $exeP) -NoNewWindow -Wait `
    -RedirectStandardOutput $o -RedirectStandardError "$exeP.stderr" | Out-Null
  return [Convert]::ToBase64String([IO.File]::ReadAllBytes($o))
}
function Invoke-Index([string]$Dproj, [string]$Tag) {
  $db = Join-Path $WorkDir "$Tag.sqlite"
  & $Exe index --project $Dproj --db $db *> (Join-Path $WorkDir "index-$Tag.log")
  return $db
}
function Get-Plan([string]$Dproj, [string]$Tag, [string[]]$Extra) {
  $db = Invoke-Index $Dproj $Tag
  $o = Join-Path $WorkDir "plan-$Tag.out"
  $null = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
    -ArgumentList (@('cycles', '--db', ('"' + $db + '"'), '--plan', '--library-db', ('"' + $Lib + '"')) + $Extra) `
    -RedirectStandardOutput $o -RedirectStandardError (Join-Path $WorkDir "plan-$Tag.err")
  return [IO.File]::ReadAllText($o)
}
function Invoke-Apply([string]$Dproj, [string]$Tag) {
  $db = Invoke-Index $Dproj $Tag
  $o = Join-Path $WorkDir "apply-$Tag.out"
  $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
    -ArgumentList @('cycles', '--fix', '--apply', '--ctor-wide', '--no-backup', '--build-timeout', '600', '--cycle', '1', '--project', ('"' + $Dproj + '"'),
      '--db', ('"' + $db + '"'), '--library-db', ('"' + $Lib + '"')) `
    -RedirectStandardOutput $o -RedirectStandardError (Join-Path $WorkDir "apply-$Tag.err")
  return @{ Exit = $p.ExitCode; Out = [IO.File]::ReadAllText($o); Err = [IO.File]::ReadAllText((Join-Path $WorkDir "apply-$Tag.err")) }
}
function Get-CyclesText([string]$Dproj, [string]$Tag) {
  $db = Invoke-Index $Dproj $Tag
  return ((& $Exe cycles --db $db 2>&1) | Out-String)
}
$CtorRx = '\*\*Constructor inversion:\*\* `(\w+)\.'
function Get-Sites([string]$Plan) { @([regex]::Matches($Plan, $CtorRx) | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique) }

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  $Lib = Join-Path $WorkDir 'library-copy.sqlite'
  Copy-Item $LibraryDb $Lib

  Write-Host '== off: no flag, the default whitelist' -ForegroundColor Cyan
  $d = Join-Path $WorkDir 'off'; New-Tree $d
  $pt = Get-Plan (Join-Path $d 'CtorWide.dproj') 'off' @()
  Check 'off1 without the flag the plan refuses ctor-inversion-surface' ($pt.Contains('Fix it: not available -- ctor-inversion-surface')) ''

  Write-Host '== wide: the flag on the four shapes' -ForegroundColor Cyan
  $base = Join-Path $WorkDir 'wide-base'; $edit = Join-Path $WorkDir 'wide-edit'
  New-Tree $base; New-Tree $edit
  $b0 = Invoke-Build (Join-Path $base 'CtorWide.dproj')
  Check 'wide0 the untouched copy builds' $b0.Ok $b0.Errors
  $out0 = Invoke-Program (Join-Path $base 'CtorWide.dproj')
  Check 'wide0b the untouched run prints the line of the .dfm OnCreate' ([Text.Encoding]::ASCII.GetString([Convert]::FromBase64String($out0)).Contains('[dm] streamed TWideDm Src')) ''
  $pt = Get-Plan (Join-Path $edit 'CtorWide.dproj') 'wide-plan' @('--ctor-wide')
  Check 'wide1 the plan says mechanical, by constructor inversion' ($pt.Contains('**Constructor inversion:**') -and -not $pt.Contains('Fix it: not available')) (([regex]::Match($pt, '(?m)^.*refused:.*$').Value) -replace '^(.{0,260}).*$', '$1')
  $sites = Get-Sites $pt
  Check 'wide2 three classes go through a pointer' (($sites -join ',') -ceq 'TWideDm,TWideProc,TWideWorker') ($sites -join ',')
  $ap = Invoke-Apply (Join-Path $edit 'CtorWide.dproj') 'wide-apply'
  Check 'wide3 --fix --apply passes the dcc gate (exit 0)' ($ap.Exit -eq 0) ("exit=$($ap.Exit) " + ((($ap.Out + $ap.Err).Trim() -split "`r?`n" | Select-Object -Last 4) -join ' | '))
  $hub = [IO.File]::ReadAllText((Join-Path $edit 'WideHub.pas')); $prc = [IO.File]::ReadAllText((Join-Path $edit 'Wide.Proc.pas'))
  Check 'wide4 w4 the list holds the base class and Add takes the pointer' ($hub.Contains('FWorkers.Add(NewTWideWorkerPtr(I, FSink))') -and ($hub -match 'TObjectList<TWideWorkerBase>')) ''
  Check 'wide5 w1 the store through the slot stands' ($prc -match 'FDm_A\s*\.GId := pId') ''
  $lf = [IO.File]::ReadAllText((Join-Path $edit 'WideDm.Untangle.pas'))
  Check 'wide5b w1 the stored field is public in the base class' ($lf -match '(?s)public.*GId\s*:') ''
  Check 'wide6 w3 Execute stays an override in the class' ([IO.File]::ReadAllText((Join-Path $edit 'Wide.Worker.pas')).Contains('procedure Execute; override;')) ''
  $cy = Get-CyclesText (Join-Path $edit 'CtorWide.dproj') 'wide-after'
  Check 'wide7 the cycle is gone' ($cy -match 'No circular|0 circular|no circular') (($cy.Trim() -split "`r?`n" | Select-Object -First 2) -join ' | ')
  $b1 = Invoke-Build (Join-Path $edit 'CtorWide.dproj')
  Check 'wide8 the applied copy builds' $b1.Ok $b1.Errors
  $out1 = Invoke-Program (Join-Path $edit 'CtorWide.dproj')
  Check 'wide9 stdout byte-identical to the untouched build''s' (($out0 -ne '<no exe>') -and ($out1 -ceq $out0)) ''

  Write-Host '== positive control: the applied tree with a pointer assignment removed' -ForegroundColor Cyan
  Edit-File (Join-Path $edit 'Wide.Worker.pas') '  NewTWideWorkerPtr := NewTWideWorker;' ''
  $bc = Invoke-Build (Join-Path $edit 'CtorWide.dproj')
  Check 'pc1a it still compiles' $bc.Ok $bc.Errors
  $outC = Invoke-Program (Join-Path $edit 'CtorWide.dproj')
  Check 'pc1b its stdout DIFFERS (the compare has teeth)' (($outC -ne '<no exe>') -and ($outC -cne $out0)) ''

  Write-Host '== --part all forwards the flag to its child runs' -ForegroundColor Cyan
  $pa = Join-Path $WorkDir 'pa-edit'; New-Tree $pa
  # --unit does not take a dotted stem (a separate defect, reported), and --part all iterates by --unit: undotted names here
  foreach ($pf in Get-ChildItem $pa -File) {
    $pt = [IO.File]::ReadAllText($pf.FullName).Replace('Wide.Sink', 'WideSink').Replace('Wide.Proc', 'WideProc').Replace('Wide.Worker', 'WideWorker')
    [IO.File]::WriteAllText($pf.FullName, $pt, $Ascii)
    if ($pf.Name -match '^Wide\.') { Move-Item -LiteralPath $pf.FullName (Join-Path $pa ($pf.Name.Replace('Wide.', 'Wide'))) }
  }
  $padb = Invoke-Index (Join-Path $pa 'CtorWide.dproj') 'pa'
  $o = Join-Path $WorkDir 'pa.out'
  $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
    -ArgumentList @('cycles', '--fix', '--apply', '--part', 'all', '--ctor-wide', '--no-backup', '--project', ('"' + (Join-Path $pa 'CtorWide.dproj') + '"'),
      '--db', ('"' + $padb + '"'), '--library-db', ('"' + $Lib + '"')) `
    -RedirectStandardOutput $o -RedirectStandardError (Join-Path $WorkDir 'pa.err')
  Check 'pa1 --part all applies through the flag' ([IO.File]::ReadAllText((Join-Path $pa 'WideHub.pas')).Contains('NewTWideWorkerPtr(')) ("exit=$($p.ExitCode)")
  Write-Host '== hub: an implementation edge hub -> module: sites apply, the cycle stays' -ForegroundColor Cyan
  $h = Join-Path $WorkDir 'hub-edit'; New-Tree $h
  Edit-File (Join-Path $h 'WideHub.pas') "implementation`n`nuses`n  System.SysUtils;" "implementation`n`nuses`n  System.SysUtils,`n  WideDm;"
  Edit-File (Join-Path $h 'WideHub.pas') "  FSink := TWideSink.Create;" "  FSink := TWideSink.Create;`n  Writeln(TWideDm.ClassName);"
  $hbase = Join-Path $WorkDir 'hub-base'; New-Tree $hbase
  Copy-Item (Join-Path $h 'WideHub.pas') $hbase -Force
  $hb = Invoke-Build (Join-Path $hbase 'CtorWide.dproj')
  $hout = Invoke-Program (Join-Path $hbase 'CtorWide.dproj')
  Check 'hub0 the untouched copy builds' $hb.Ok $hb.Errors
  $pt = Get-Plan (Join-Path $h 'CtorWide.dproj') 'hub-plan' @('--ctor-wide')
  $hs = Get-Sites $pt
  Write-Host ("  planned sites: {0} ({1})" -f $hs.Count, ($hs -join ','))
  $ap = Invoke-Apply (Join-Path $h 'CtorWide.dproj') 'hub-apply'
  $hb1 = Invoke-Build (Join-Path $h 'CtorWide.dproj')
  $cy = Get-CyclesText (Join-Path $h 'CtorWide.dproj') 'hub-after'
  Check 'hub1 sites applied and the tree compiles' ($hb1.Ok -and [IO.File]::ReadAllText((Join-Path $h 'WideHub.pas')).Contains('NewTWideWorkerPtr(')) ("exit=$($ap.Exit) " + $hb1.Errors)
  Check 'hub2 the cycle is NOT gone (planned <> cut)' (-not ($cy -match 'No circular|0 circular|no circular')) (($cy.Trim() -split "`r?`n" | Select-Object -First 1) -join ' | ')
  $hout1 = Invoke-Program (Join-Path $h 'CtorWide.dproj')
  Check 'hub3 stdout byte-identical' (($hout -ne '<no exe>') -and ($hout1 -ceq $hout)) ''

  $refused = @(
    @{ Tag = 'n1'; Why = 'a library property written through the slot'; F = 'Wide.Proc.pas'; Old = '  FDm_A  .Free;'; New = "  FDm_A  .Tag := 1;`n  FDm_A  .Free;"; Line = 'Wide.Proc.pas:' },
    @{ Tag = 'n2'; Why = 'a temporary'; F = 'Wide.Proc.pas'; Old = '  FDm_A  .Free;'; New = "  TWideDm.Create(nil).Free;`n  FDm_A  .Free;"; Line = 'Wide.Proc.pas:' },
    @{ Tag = 'n5'; Why = 'a published (dfm-streamed) field read through the slot'; F = 'Wide.Proc.pas'; Old = '  FDm_A  .Free;'; New = "  Writeln(FDm_A.Src.Name);`n  FDm_A  .Free;"; Line = 'is published' },
    @{ Tag = 'n3'; Why = 'the list handing an element out by Extract'; F = 'WideHub.pas'; Old = '    FWorkers.OwnsObjects := True;'; New = "    FWorkers.Extract(W);`n    FWorkers.OwnsObjects := True;"; Line = 'WideHub.pas:' },
    @{ Tag = 'n4'; Why = 'the list handing an element out by First'; F = 'WideHub.pas'; Old = '    FWorkers.OwnsObjects := True;'; New = "    W := FWorkers.First;`n    FWorkers.OwnsObjects := True;"; Line = 'WideHub.pas:' }
  )
  foreach ($r in $refused) {
    Write-Host "== refused with the flag: $($r.Why)" -ForegroundColor Cyan
    $d = Join-Path $WorkDir "$($r.Tag)-edit"; New-Tree $d
    Edit-File (Join-Path $d $r.F) $r.Old $r.New
    $pt = Get-Plan (Join-Path $d 'CtorWide.dproj') $r.Tag @('--ctor-wide')
    Check "$($r.Tag)1 the plan refuses ctor-inversion-surface" ($pt -match 'refused: ctor-inversion-surface -- ') ''
    Check "$($r.Tag)2 it names the file" ($pt -match ('ctor-inversion-surface -- .*' + [regex]::Escape($r.Line))) ''
  }
} finally {
  if ((-not $KeepWorkDir) -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }