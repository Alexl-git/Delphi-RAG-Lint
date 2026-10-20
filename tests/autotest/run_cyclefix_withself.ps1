<#
  run_cyclefix_withself.ps1 -- E18 Task 17b D1: a Self-qualified member inside `with X as TClass do`
  does not refuse recipe R2 (`with-member`).

  WHY (Task 17, ORM3 CLIENT UIConnect.pas:51): inside `with ... as TfrmGageport2 do` the line
  `Memo1.Lines.Add(Self.InBuf);` was refused as `with-member` because both classes declare InBuf.
  `Self.InBuf` is qualified: it binds to the consumer before and after the rewrite. The index
  records `Self.X` as two bare reads (`Self`, `X`, no receiver), so the planner reads the source.

  FIXTURE tests\fixtures\cyclefix\withself: DemoGagePort <-> DemoUIConnect, both classes with an
  InBuf property; DemoUIConnect.OnData reads `Self.InBuf` inside `with pPort as TDemoGagePort do`.

  THE LIBRARY: R2 reads the ancestry of TComponent from a platform library. This runner never
  opens a real library: it indexes a STUB library (System: TObject, IInterface; System.Classes:
  TPersistent, TComponent with Name, TStrings) in its scratch dir and passes that with --library-db.
  -LibraryDb is accepted for the battery's uniform call and ignored.

  (a) the plan cuts demouiconnect -> demogageport by member hand-over; no with-member refusal.
  (a4) `Self.Name` (a member of the ancestor TComponent the interface does not carry) proceeds too.
  (b) POSITIVE CONTROL: the unqualified `Name` there is refused `with-member` (it binds to the port
      today and to the consumer after the rewrite). NOT the unqualified `InBuf`: that one binds to the
      port, so R2 carries it in the interface and correctly proceeds.
  (c) with RAD Studio: `cycles --fix --cycle 1 --apply` on a copy (compile gate on) exits 0, the
      re-indexed copy prints "No circular unit dependencies found.", and the built program still
      prints the CONSUMER's InBuf (`[gageport] data 42`), not the port's (`port-raw`).
#>
[CmdletBinding()]
param(
  [string]$Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-withself-$PID",
  [string]$LibraryDb = 'none'
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
$Exe    = (Resolve-Path $Exe).Path
$Repo   = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Fx     = Join-Path $Repo 'tests\fixtures\cyclefix\withself'
$RsVars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$Ascii  = [Text.Encoding]::ASCII
$Body   = "  with pPort as TDemoGagePort do`r`n    Log.Add('data ' + Self.InBuf);"

function Set-Text([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), $Ascii)
}

# Copies the fixture into pTo, optionally replacing $Body in DemoUIConnect.pas by pNewBody; indexes it.
function New-Copy([string]$Tag, [string]$NewBody = '') {
  $to = Join-Path $WorkDir $Tag
  New-Item -ItemType Directory -Force $to | Out-Null
  Get-ChildItem $Fx -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $to $_.Name) -Force }
  if ($NewBody -ne '') {
    $p = Join-Path $to 'DemoUIConnect.pas'
    $t = [IO.File]::ReadAllText($p)
    if (-not $t.Contains($Body)) { throw "anchor not found in $p" }
    [IO.File]::WriteAllText($p, $t.Replace($Body, $NewBody), $Ascii)
  }
  $db = Join-Path $WorkDir "$Tag.sqlite"
  & $Exe index --project (Join-Path $to 'WithSelf.dproj') --db $db *> (Join-Path $WorkDir "index-$Tag.log")
  return @{ Dir = $to; Dproj = (Join-Path $to 'WithSelf.dproj'); Db = $db; IndexExit = $LASTEXITCODE }
}

function Get-Plan([hashtable]$C, [string]$Tag) {
  $o = Join-Path $WorkDir "plan-$Tag.out"
  $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
    -ArgumentList @('cycles', '--db', ('"' + $C.Db + '"'), '--plan', '--library-db', ('"' + $Stub + '"')) `
    -RedirectStandardOutput $o -RedirectStandardError (Join-Path $WorkDir "plan-$Tag.err")
  return @{ Exit = $p.ExitCode; Text = [IO.File]::ReadAllText($o) }
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  Write-Host '== setup: stub library' -ForegroundColor Cyan
  $stubDir = Join-Path $WorkDir 'stublib'
  New-Item -ItemType Directory -Force $stubDir | Out-Null
  Set-Text (Join-Path $stubDir 'System.pas') "unit System;`n`ninterface`n`ntype`n  TObject = class`n  end;`n`n  IInterface = interface`n  end;`n`nimplementation`n`nend.`n"
  Set-Text (Join-Path $stubDir 'System.Classes.pas') ("unit System.Classes;`n`ninterface`n`ntype`n  TPersistent = class(TObject)`n  end;`n`n" +
    "  TComponent = class(TPersistent, IInterface)`n  private`n    FName: string;`n  public`n    property Name: string read FName;`n  end;`n`n  TStrings = class(TPersistent)`n  end;`n`nimplementation`n`nend.`n")
  $Stub = Join-Path $WorkDir 'stub-library.sqlite'
  & $Exe index $stubDir --db $Stub *> (Join-Path $WorkDir 'index-stub.log')
  Check 's0 the stub library was indexed' (($LASTEXITCODE -eq 0) -and (Test-Path $Stub)) "exit=$LASTEXITCODE"

  Write-Host '== (a) Self.InBuf inside the with: R2 proceeds' -ForegroundColor Cyan
  $a = New-Copy 'a'
  Check 'a0 indexed' ($a.IndexExit -eq 0) "exit=$($a.IndexExit)"
  $pa = Get-Plan $a 'a'
  Check 'a1 plan exit 0' ($pa.Exit -eq 0) "exit=$($pa.Exit)"
  Check 'a2 no with-member refusal' (-not $pa.Text.Contains('refused: with-member')) (($pa.Text -split "`r?`n" | Select-String 'refused:' | Select-Object -First 2) -join ' | ')
  Check 'a3 cut by member hand-over' $pa.Text.Contains('by **member hand-over through an extracted interface**') ''

  $a4 = New-Copy 'a4' "  with pPort as TDemoGagePort do`r`n    Log.Add('data ' + Self.InBuf + Self.Name);"
  $p4 = Get-Plan $a4 'a4'
  Check 'a4 Self.Name (an uncarried ancestor member, qualified) proceeds too' (($p4.Exit -eq 0) -and $p4.Text.Contains('by **member hand-over through an extracted interface**') -and -not $p4.Text.Contains('refused: with-member')) "exit=$($p4.Exit)"

  Write-Host '== (b) positive control: the unqualified Name still refuses' -ForegroundColor Cyan
  $b = New-Copy 'b' "  with pPort as TDemoGagePort do`r`n    Log.Add('data ' + Self.InBuf + Name);"
  Check 'b0 indexed' ($b.IndexExit -eq 0) "exit=$($b.IndexExit)"
  $pb = Get-Plan $b 'b'
  Check 'b1 refused: with-member naming Name' ($pb.Text -match 'refused: with-member -- inside `with \.\.\. as TDemoGagePort do` \(line \d+\), `Name`') ''
  Check 'b2 not cut by member hand-over' (-not $pb.Text.Contains('by **member hand-over through an extracted interface**')) ''

  if (-not (Test-Path $RsVars)) {
    Write-Host '  SKIP (c): RAD Studio not installed' -ForegroundColor Yellow
  } else {
    Write-Host '== (c) compile-gated --apply on a copy' -ForegroundColor Cyan
    $c = New-Copy 'c'
    Check 'c0 indexed' ($c.IndexExit -eq 0) "exit=$($c.IndexExit)"
    $fo = Join-Path $WorkDir 'fix-c.out'
    & $Exe cycles --fix --project $c.Dproj --db $c.Db --library-db $Stub --cycle 1 --apply --no-backup `
      --shadow-out (Join-Path $WorkDir 'c-shadow') *> $fo
    $fx = $LASTEXITCODE
    $ft = [IO.File]::ReadAllText($fo)
    Check 'c1 --fix --apply exit 0 (compile gate passed)' ($fx -eq 0) ("exit=$fx " + (($ft -split "`r?`n" | Select-Object -Last 4) -join ' | '))
    & $Exe index --project $c.Dproj --db $c.Db *> (Join-Path $WorkDir 'index-c2.log')
    $after = (& $Exe cycles --db $c.Db 2>$null | Out-String)
    Check 'c2 re-indexed: No circular unit dependencies found.' $after.Contains('No circular unit dependencies found.') ($after.Trim() -replace "`r?`n", ' | ')
    $exeP = Join-Path $c.Dir 'Win64\Debug\WithSelf.exe'
    if (Test-Path $exeP) {
      $out = (& $exeP | Out-String)
      Check 'c3 the program still prints the consumer''s InBuf' ($out.Contains('[gageport] data 42') -and -not $out.Contains('port-raw')) ($out.Trim() -replace "`r?`n", ' | ')
    } else {
      Check 'c3 the compile gate left a built program to run' $false $exeP
    }
  }
} finally {
  Set-Location -LiteralPath $env:TEMP
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}

if ($script:Failed) { Write-Host 'run_cyclefix_withself: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_cyclefix_withself: PASS' -ForegroundColor Green
exit 0
