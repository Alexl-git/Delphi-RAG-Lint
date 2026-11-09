<#
  run_cyclefix_cyc_string_literal.ps1 -- B11 (1.44): a plan rewrites CODE on the lines it edits, never a
  string literal or a comment that merely spells the same name. The planners used to run their
  regexes over the raw line, so `Writeln('R1TitleOf says ', R1TitleOf(1))` became
  `Writeln('R1TitleOfPtr says ', R1TitleOfPtr(1))`: it compiled and the program printed something else.

  Trees (each a copy of a fixture with one line changed to spell the name inside a string and a comment):
    r1one  tests\fixtures\cyclefix\r1extend  R1, one routine (PlanRoutineInversion)
    r1two  tests\fixtures\cyclefix\r1two     R1, N routines (PlanRoutinesInversion)
    r2     tests\fixtures\cyclefix\memberwrite  R2: `is`, `as`, a hard cast and a retyped local
    b4f    tests\fixtures\cyclefix\b4fbase   base class hand-over: `as` and `is` switched to the base
  For each: the untouched copy is built and run, a second copy is planned (`cycles --plan`), followed
  with tools\follow-cycle-plan.ps1, built and run. Checks: the code occurrence WAS rewritten (a plan
  that does nothing would pass the rest), the literal and the comment are byte-identical in the followed
  file, the build is clean, stdout is byte-identical to the untouched build's.

  POSITIVE CONTROL: the followed r1one with one byte of its literal changed still compiles and its
  stdout DIFFERS, so the compare can tell a rewritten string from an intact one. The RED run is any
  engine before B11: checks *2 and *4 fail on it.

  The engine never opens the given library in place: -LibraryDb is copied into the $PID scratch dir.
#>
[CmdletBinding()]
param(
  [string]$Exe       = $(if (Test-Path -LiteralPath "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe") { "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" } else { "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }),
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-strlit-$PID",
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
$Fx    = Join-Path $Repo 'tests\fixtures\cyclefix'
$Ascii = [Text.Encoding]::ASCII

function Copy-Tree([string]$From, [string]$To) {
  New-Item -ItemType Directory -Force $To | Out-Null
  Get-ChildItem $From -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $To $_.Name) -Force }
}

function Edit-File([string]$Path, [string]$Old, [string]$New) {
  $t = [IO.File]::ReadAllText($Path)
  $n = $t.Replace(($Old -replace "`r?`n", "`r`n"), ($New -replace "`r?`n", "`r`n"))
  [IO.File]::WriteAllText($Path, ($n -replace "`r?`n", "`r`n"), $Ascii)
  return ($n -ne $t)
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
  $exeP = Join-Path (Split-Path $Dproj) ('Win64\Debug\' + [IO.Path]::GetFileNameWithoutExtension($Dproj) + '.exe')
  if (-not (Test-Path $exeP)) { return '<no exe>' }
  $o = "$exeP.stdout"
  Start-Process -FilePath $exeP -WorkingDirectory (Split-Path $exeP) -NoNewWindow -Wait `
    -RedirectStandardOutput $o -RedirectStandardError "$exeP.stderr" | Out-Null
  return [Convert]::ToBase64String([IO.File]::ReadAllBytes($o))
}

function Get-PlanFile([string]$Dproj, [string]$Tag) {
  $db = Join-Path $WorkDir "$Tag.sqlite"
  & $Exe index --project $Dproj --db $db *> (Join-Path $WorkDir "index-$Tag.log")
  $o = Join-Path $WorkDir "plan-$Tag.out"
  $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
    -ArgumentList @('cycles', '--db', ('"' + $db + '"'), '--plan', '--library-db', ('"' + $Lib + '"')) `
    -RedirectStandardOutput $o -RedirectStandardError (Join-Path $WorkDir "plan-$Tag.err")
  return @{ Exit = $p.ExitCode; File = $o }
}

$cases = @(
  @{ Tag = 'r1one'; Fixture = 'r1extend'; Dproj = 'R1Extend.dproj'; File = 'R1Form.pas'; Cycle = 1
     Old = "Writeln(Format('[form] %s', [R1TitleOf(pId)]));"
     New = "Writeln(Format('[form] R1TitleOf R1Title.R1TitleOf %s', [R1TitleOf(pId)])); // R1TitleOf stays in this comment { R1TitleOf }"
     Code = 'R1TitleOfPtr(pId)'
     Keep = @("'[form] R1TitleOf R1Title.R1TitleOf %s'", '// R1TitleOf stays in this comment { R1TitleOf }') },
  @{ Tag = 'r1two'; Fixture = 'r1two'; Dproj = 'R1Extend.dproj'; File = 'R1Form.pas'; Cycle = 1
     Old = "Writeln(Format('[form] %d %s', [R1TitleLen(pId), R1TitleOf(pId + 1)]));"
     New = "Writeln(Format('[form] R1TitleLen %d R1TitleOf %s', [R1TitleLen(pId), R1TitleOf(pId + 1)])); { R1TitleLen R1TitleOf }"
     Code = 'R1TitleLenPtr(pId)'
     Keep = @("'[form] R1TitleLen %d R1TitleOf %s'", '{ R1TitleLen R1TitleOf }') },
  @{ Tag = 'r2'; Fixture = 'memberwrite'; Dproj = 'MemberWrite.dproj'; File = 'DemoUIConnect.pas'; Cycle = 1
     Prep = {
       param($u)
       $null = Edit-File $u "    LastGage := 0; // <-- a WRITE through the with: an interface of reads cannot carry it`n" ''
       $null = Edit-File $u ("procedure TDemoUIConnect.Attach;`nbegin`n  if not (Owner is TDemoGagePort) then`n    Exit;`n" +
         "  with Owner as TDemoGagePort do`n    Log.Add(Format('ui connected (last gage %d)', [LastGage]));`nend;") `
         ("procedure TDemoUIConnect.Attach;`nvar`n  Port: TDemoGagePort; // : TDemoGagePort stays in this comment`nbegin`n  Port := nil;`n" +
         "  if Owner is TDemoGagePort then Writeln('Owner is TDemoGagePort');`n" +
         "  if Owner is TDemoGagePort then`n    Port := Owner as TDemoGagePort; Writeln('Owner as TDemoGagePort, TDemoGagePort(Owner).X');`n" +
         "  if not Assigned(Port) or (Port = nil) then`n    Exit;`n" +
         "  Port.Log.Add(Format('ui connected (last gage %d)', [Port.LastGage]));`nend;")
     }
     Code = 'Port := Owner as IDemoGagePortSurface;'
     Keep = @("Writeln('Owner is TDemoGagePort');", "Writeln('Owner as TDemoGagePort, TDemoGagePort(Owner).X');", '// : TDemoGagePort stays in this comment') },
  @{ Tag = 'b4f'; Fixture = 'b4fbase'; Dproj = 'B4fBase.dproj'; File = 'BfCanvas.pas'; Cycle = 1
     Old = "Writeln('paint ', (pShape as TBfShape).Name, ' width ', pWidth);"
     New = "Writeln('paint TBfShape ', (pShape as TBfShape).Name, ' width ', pWidth); // pShape as TBfShape stays"
     Code = '(pShape as TBfShapeBase).Name'
     Keep = @("'paint TBfShape '", '// pShape as TBfShape stays') }
)

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  $Lib = Join-Path $WorkDir 'library-copy.sqlite'
  Copy-Item $LibraryDb $Lib
  foreach ($c in $cases) {
    $t = $c.Tag
    Write-Host "== $t ($($c.Fixture))" -ForegroundColor Cyan
    $base = Join-Path $WorkDir "$t-base"; $edit = Join-Path $WorkDir "$t-edit"
    foreach ($d in $base, $edit) {
      Copy-Tree (Join-Path $Fx $c.Fixture) $d
      $f = Join-Path $d $c.File
      if ($c.Prep) { & $c.Prep $f } else { $null = Edit-File $f $c.Old $c.New }
    }
    Check "${t}0 the fixture edit applied" ([IO.File]::ReadAllText((Join-Path $edit $c.File)).Contains($c.Keep[0])) ''
    $b0 = Invoke-Build (Join-Path $base $c.Dproj)
    Check "${t}0b the untouched copy builds" $b0.Ok $b0.Errors
    $out0 = Invoke-Program (Join-Path $base $c.Dproj)
    $plan = Get-PlanFile (Join-Path $edit $c.Dproj) $t
    $pt = [IO.File]::ReadAllText($plan.File)
    Check "${t}1 the plan rewrites the code occurrence" ($pt.Contains($c.Code)) $c.Code
    $fo = & pwsh -NoProfile -File (Join-Path $Repo 'tools\follow-cycle-plan.ps1') -PlanFile $plan.File -Cycle $c.Cycle -Root $edit 2>&1 | Out-String
    Check "${t}1b the follower applies the cycle (exit 0)" ($LASTEXITCODE -eq 0) ($fo.Trim() -replace "`r?`n", ' | ')
    $ft = [IO.File]::ReadAllText((Join-Path $edit $c.File))
    foreach ($k in $c.Keep) { Check "${t}2 byte-identical in the followed file: $k" ($ft.Contains($k)) '' }
    Check "${t}2b the followed file holds the rewritten code" ($ft.Contains($c.Code)) ''
    $b1 = Invoke-Build (Join-Path $edit $c.Dproj)
    Check "${t}3 the followed copy builds" $b1.Ok $b1.Errors
    $out1 = Invoke-Program (Join-Path $edit $c.Dproj)
    Check "${t}4 its stdout is byte-identical to the untouched build's" (($out0 -ne '<no exe>') -and ($out1 -ceq $out0)) ''
    if ($t -eq 'r1one') {
      Write-Host '== positive control: the followed r1one with its literal changed' -ForegroundColor Cyan
      Check 'pc0 the literal was changed' (Edit-File (Join-Path $edit $c.File) "'[form] R1TitleOf R1Title.R1TitleOf %s'" "'[form] R1TitleOfPtr R1Title.R1TitleOf %s'") ''
      $bc = Invoke-Build (Join-Path $edit $c.Dproj)
      Check 'pc1 it still compiles' $bc.Ok $bc.Errors
      $outC = Invoke-Program (Join-Path $edit $c.Dproj)
      Check 'pc2 its stdout DIFFERS (the compare has teeth)' (($outC -ne '<no exe>') -and ($outC -cne $out0)) ''
    }
  }
} finally {
  if ((-not $KeepWorkDir) -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
