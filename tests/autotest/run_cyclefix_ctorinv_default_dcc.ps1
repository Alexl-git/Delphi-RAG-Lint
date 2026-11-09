<#
  run_cyclefix_ctorinv_default_dcc.ps1 -- E-CTORINV-DEFAULT-PATH (wave 147): three fixes that were behind
  `--ctor-wide` (lane 146 r4) now hold on the DEFAULT constructor inversion, without the flag.
  Tree: docs\examples\cycle-lab LabCtorOwner / LabCtorChild (the B8 `ctor` tree of run_cyclefix_ctorinv_dcc).

  ACCEPTED without the flag (each: untouched copy built and run; `cycles --fix --apply` with the real dcc gate on a
  second copy; the consumer calls the pointer; the applied copy builds; stdout BYTE-identical):
    uc  the consumer's uses clause names a dotted unit whose segment is the slot's name (`Lab.FChild`): a uses
        entry is no use of the slot (Loader2025.FolderProcessor; was a false refusal)
    mc  a multi-line `{ .. }` comment in the consumer spells `Writeln(TObject(FChild).ClassName)` (a cast, which the
        whitelist refuses in code): a comment is no use of the slot
  REFUSED without the flag:
    pb  a published field of the class read through the slot: PullMembers would pull it into the base class as
        PROTECTED (a .dfm streams into the published field of the class that declares it); the plan must say
        `is published`, not mechanical.
  POSITIVE CONTROLS: pc-uc / pc-mc the same edit plus the cast `TObject(FChild)` in CODE still refuses
    ctor-inversion-surface naming THAT line: the accept checks are not blind. pc1: the applied uc tree with the pointer
    assignment removed compiles and its stdout DIFFERS.
  RED: engine 1.46.0-alpha refuses uc and mc (`ctor-inversion-surface` naming the line) and plans pb mechanical.
#>
[CmdletBinding()]
param(
  [string]$Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-ctordef-$PID",
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
$Lab   = Join-Path $Repo 'docs\examples\cycle-lab'
$Ascii = [Text.Encoding]::ASCII

function Set-Text([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), $Ascii)
}
function Edit-File([string]$Path, [string]$Old, [string]$New) {
  $t = [IO.File]::ReadAllText($Path)
  $n = $t.Replace(($Old -replace "`r?`n", "`r`n"), ($New -replace "`r?`n", "`r`n"))
  if ($n -ceq $t) { throw "fixture edit did not apply in $Path : $Old" }
  Set-Text $Path $n
}

$Dpr = @'
program CtorLab;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  Lab.FChild in 'Lab.FChild.pas',
  LabCtorOwner in 'LabCtorOwner.pas',
  LabCtorChild in 'LabCtorChild.pas';
var
  O: TLabCtorOwner;
begin
  try
    O := TLabCtorOwner.Create;
    try
      O.Poke;
    finally
      O.Free;
    end;
  except
    on E: Exception do Writeln('died: ', E.ClassName);
  end;
end.
'@
$DotUnit = @'
unit Lab.FChild;

interface

/// <summary>A unit whose last segment is the slot's name.</summary>
/// <returns>A tag.</returns>
function LabDotTag: string;

implementation

function LabDotTag: string;
begin
  Result := 'dot';
end;

end.
'@

# The ctor tree plus Lab.FChild (named in the program; the consumer's uses names it only in the uc case).
function New-Tree([string]$Dir) {
  New-Item -ItemType Directory -Force $Dir | Out-Null
  $units = @('Lab.FChild', 'LabCtorOwner', 'LabCtorChild')
  foreach ($u in $units[1..2]) { Copy-Item (Join-Path $Lab "$u.pas") (Join-Path $Dir "$u.pas") -Force }
  Set-Text (Join-Path $Dir 'Lab.FChild.pas') $DotUnit
  Set-Text (Join-Path $Dir 'CtorLab.dpr') $Dpr
  $pj = [IO.File]::ReadAllText((Join-Path $Repo 'tests\fixtures\cyclefix\r1extend\R1Extend.dproj'))
  $pj = $pj.Replace('R1Extend', 'CtorLab').Replace('{5A1C7E94-2B6D-4F03-8C9A-7E3B1D0F2A85}', '{4B7D2E19-6A3C-4F58-9E01-3D8C5B7A2F64}')
  $pj = [regex]::Replace($pj, '(?m)^\s*<DCCReference Include="[^"]+"/>\r?\n', '')
  $refs = ($units | ForEach-Object { "<DCCReference Include=`"$_.pas`"/>" }) -join "`r`n        "
  $pj = $pj.Replace('</DelphiCompile>', "</DelphiCompile>`r`n        $refs")
  Set-Text (Join-Path $Dir 'CtorLab.dproj') $pj
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
  $exeP = Join-Path (Split-Path $Dproj) 'Win64\Debug\CtorLab.exe'
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
function Get-Plan([string]$Dproj, [string]$Tag) {
  $db = Invoke-Index $Dproj $Tag
  $o = Join-Path $WorkDir "plan-$Tag.out"
  $null = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
    -ArgumentList @('cycles', '--db', ('"' + $db + '"'), '--plan', '--library-db', ('"' + $Lib + '"')) `
    -RedirectStandardOutput $o -RedirectStandardError (Join-Path $WorkDir "plan-$Tag.err")
  return [IO.File]::ReadAllText($o)
}
function Invoke-Apply([string]$Dproj, [string]$Tag) {
  $db = Invoke-Index $Dproj $Tag
  $o = Join-Path $WorkDir "apply-$Tag.out"
  $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
    -ArgumentList @('cycles', '--fix', '--apply', '--no-backup', '--build-timeout', '600', '--cycle', '1', '--project', ('"' + $Dproj + '"'),
      '--db', ('"' + $db + '"'), '--library-db', ('"' + $Lib + '"')) `
    -RedirectStandardOutput $o -RedirectStandardError (Join-Path $WorkDir "apply-$Tag.err")
  return @{ Exit = $p.ExitCode; Out = [IO.File]::ReadAllText($o); Err = [IO.File]::ReadAllText((Join-Path $WorkDir "apply-$Tag.err")) }
}
function Get-Refusal([string]$Plan) { (([regex]::Match($Plan, '(?m)^.*refused:.*$').Value) -replace '^(.{0,260}).*$', '$1') }

$Own = 'LabCtorOwner.pas'
$Cases = @(
  @{ Tag = 'uc'; Why = 'a dotted uses entry ending in the slot name'
     Prep = { param($d) Edit-File (Join-Path $d $Own) "uses`n  LabCtorChild;" "uses`n  LabCtorChild,`n  Lab.FChild;"
              Edit-File (Join-Path $d $Own) "  Result := 'owner';" "  Result := 'owner ' + LabDotTag;" }
     Ctrl = { param($d) Edit-File (Join-Path $d $Own) "  FChild.Touch;" "  FChild.Touch;`n  Writeln(TObject(FChild).ClassName);" } },
  @{ Tag = 'mc'; Why = 'a multi-line comment spelling a cast of the slot'
     Prep = { param($d) Edit-File (Join-Path $d $Own) "  FChild.Touch;" "  { the old way:`n      Writeln(TObject(FChild).ClassName);`n    is gone }`n  FChild.Touch;" }
     Ctrl = { param($d) Edit-File (Join-Path $d $Own) "  FChild.Touch;" "  FChild.Touch;`n  Writeln(TObject(FChild).ClassName);" } }
)

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  $Lib = Join-Path $WorkDir 'library-copy.sqlite'
  Copy-Item $LibraryDb $Lib

  foreach ($c in $Cases) {
    $t = $c.Tag
    Write-Host "== accepted without the flag: $($c.Why)" -ForegroundColor Cyan
    $base = Join-Path $WorkDir "$t-base"; $edit = Join-Path $WorkDir "$t-edit"
    foreach ($d in $base, $edit) { New-Tree $d; & $c.Prep $d }
    $b0 = Invoke-Build (Join-Path $base 'CtorLab.dproj')
    Check "${t}0 the untouched copy builds" $b0.Ok $b0.Errors
    $out0 = Invoke-Program (Join-Path $base 'CtorLab.dproj')
    $pt = Get-Plan (Join-Path $edit 'CtorLab.dproj') "$t-plan"
    Check "${t}1 the plan says mechanical, by constructor inversion" ($pt.Contains('**Constructor inversion:**') -and -not $pt.Contains('Fix it: not available')) (Get-Refusal $pt)
    $ap = Invoke-Apply (Join-Path $edit 'CtorLab.dproj') "$t-apply"
    Check "${t}2 --fix --apply passes the dcc gate (exit 0)" ($ap.Exit -eq 0) ("exit=$($ap.Exit) " + ((($ap.Out + $ap.Err).Trim() -split "`r?`n" | Select-Object -Last 3) -join ' | '))
    $ft = [IO.File]::ReadAllText((Join-Path $edit $Own))
    Check "${t}3 the consumer calls the pointer" ($ft.Contains('NewTLabCtorChildPtr(Self)')) ''
    $b1 = Invoke-Build (Join-Path $edit 'CtorLab.dproj')
    Check "${t}4 the applied copy builds" $b1.Ok $b1.Errors
    $out1 = Invoke-Program (Join-Path $edit 'CtorLab.dproj')
    Check "${t}5 stdout byte-identical to the untouched build's" (($out0 -ne '<no exe>') -and ($out1 -ceq $out0)) ''
    if (($t -eq 'uc') -and ($ap.Exit -ne 0)) { Check 'pc1 the applied uc tree exists' $false 'nothing was applied' }
    elseif ($t -eq 'uc') {
      Write-Host '== positive control pc1: the applied uc tree with the pointer assignment removed' -ForegroundColor Cyan
      Edit-File (Join-Path $edit 'LabCtorChild.pas') '  NewTLabCtorChildPtr := NewTLabCtorChild;' ''
      $bc = Invoke-Build (Join-Path $edit 'CtorLab.dproj')
      Check 'pc1a it still compiles' $bc.Ok $bc.Errors
      $outC = Invoke-Program (Join-Path $edit 'CtorLab.dproj')
      Check 'pc1b its stdout DIFFERS (the compare has teeth)' (($outC -ne '<no exe>') -and ($outC -cne $out0)) ''
    }
    Write-Host "== positive control pc-${t}: the same tree with the slot's name in code" -ForegroundColor Cyan
    $ctl = Join-Path $WorkDir "$t-ctl"; New-Tree $ctl; & $c.Prep $ctl; & $c.Ctrl $ctl
    $pc = Get-Plan (Join-Path $ctl 'CtorLab.dproj') "$t-ctl"
    $cl = [array]::IndexOf(([IO.File]::ReadAllText((Join-Path $ctl $Own)) -split "`r`n"), '  Writeln(TObject(FChild).ClassName);') + 1
    Check "pc-${t} a real use of the slot (line $cl) still refuses ctor-inversion-surface, naming that line" ($pc -match ('refused: ctor-inversion-surface -- .*LabCtorOwner\.pas:' + $cl + '\b')) (Get-Refusal $pc)
  }

  Write-Host '== refused without the flag: a published field read through the slot' -ForegroundColor Cyan
  $d = Join-Path $WorkDir 'pb-edit'; New-Tree $d
  Edit-File (Join-Path $d 'LabCtorChild.pas') "  public`n    constructor Create(pOwner: TObject);" "  public`n    constructor Create(pOwner: TObject);`n  published`n    Src: TObject;`n  public"
  Edit-File (Join-Path $d $Own) "  FChild.Touch;" "  if FChild.Src = nil then Writeln('[pb] no src');`n  FChild.Touch;"
  $pt = Get-Plan (Join-Path $d 'CtorLab.dproj') 'pb'
  Check 'pb1 the plan is not mechanical' ($pt.Contains('Fix it: not available')) ''
  Check 'pb2 it refuses because the field is published' ($pt -match 'field `Src` is published') (Get-Refusal $pt)
} finally {
  if ((-not $KeepWorkDir) -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
