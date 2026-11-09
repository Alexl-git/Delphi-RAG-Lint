<#
  run_cyclefix_dproj_multiline_dcc.ps1 -- E-DPROJ-LEAF-LINEBREAK (wave 147). A form or data module is listed in
  the .dproj with children:
      <DCCReference Include="uX.pas">
          <Form>X</Form>
      </DCCReference>
  The line `cycles --fix` adds for a new unit was a copy of the anchor's OPENING line, inserted right after it:
  inside the element, unclosed, so msbuild cannot read the project and the dcc gate rolls back (lane 146 r4,
  behind --ctor-wide only). Now on the default path, in both writers:
    lf  RegisterLeaves: a CREATED leaf next to its multi-line unit (cycle-lab ctor tree, LabCtorChild is the form)
    rd  RegisterDeclUnit (A2): the declaring unit R1Title, not in the program, joins it after the LAST
        DCCReference, which is multi-line (r1extend, R1Nav is the form)
  Each: untouched copy built and run; `cycles --fix --apply` (real dcc gate, no --ctor-wide) exit 0; the .dproj
  parses as XML; the new unit is a self-closing DCCReference AFTER the element, not nested in it; the applied copy
  builds; stdout BYTE-identical.
  POSITIVE CONTROL pc: the old shape (the opening line copied right after itself) does NOT parse as XML, so the
    XML check can fail.
  RED: engine 1.46.0-alpha, lf2 and rd2 (the gate rolls back: exit <> 0).
#>
[CmdletBinding()]
param(
  [string]$Exe       = $(if (Test-Path -LiteralPath "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe") { "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" } else { "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }),
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-dprojml-$PID",
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
$Fx    = Join-Path $Repo 'tests\fixtures\cyclefix'
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
function Get-MultiLine([string]$Unit, [string]$Form) {
  "<DCCReference Include=`"$Unit.pas`">`r`n            <Form>$Form</Form>`r`n        </DCCReference>"
}

$DprCtor = @'
program CtorLab;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
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
# lf: the ctor tree, LabCtorChild listed with children.
function New-Lf([string]$Dir) {
  New-Item -ItemType Directory -Force $Dir | Out-Null
  foreach ($u in 'LabCtorOwner', 'LabCtorChild') { Copy-Item (Join-Path $Lab "$u.pas") (Join-Path $Dir "$u.pas") -Force }
  Set-Text (Join-Path $Dir 'CtorLab.dpr') $DprCtor
  $pj = [IO.File]::ReadAllText((Join-Path $Fx 'r1extend\R1Extend.dproj'))
  $pj = $pj.Replace('R1Extend', 'CtorLab').Replace('{5A1C7E94-2B6D-4F03-8C9A-7E3B1D0F2A85}', '{8E2A4C61-3F7B-4D95-A0C8-1B6E9D3F5A27}')
  $pj = [regex]::Replace($pj, '(?m)^\s*<DCCReference Include="[^"]+"/>\r?\n', '')
  $pj = $pj.Replace('</DelphiCompile>', "</DelphiCompile>`r`n        <DCCReference Include=`"LabCtorOwner.pas`"/>`r`n        " + (Get-MultiLine 'LabCtorChild' 'LabChildForm'))
  Set-Text (Join-Path $Dir 'CtorLab.dproj') $pj
}
# rd: r1extend, R1Title out of the program (A2 registers it), R1Nav (the last reference) listed with children.
function New-Rd([string]$Dir) {
  New-Item -ItemType Directory -Force $Dir | Out-Null
  Get-ChildItem (Join-Path $Fx 'r1extend') -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $Dir $_.Name) -Force }
  Edit-File (Join-Path $Dir 'R1Extend.dpr') "  R1Title in 'R1Title.pas',`n" ''
  Edit-File (Join-Path $Dir 'R1Extend.dproj') "        <DCCReference Include=`"R1Title.pas`"/>`n" ''
  Edit-File (Join-Path $Dir 'R1Extend.dproj') '<DCCReference Include="R1Nav.pas"/>' (Get-MultiLine 'R1Nav' 'R1NavForm')
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
function Invoke-Apply([string]$Dproj, [string]$Tag) {
  $db = Join-Path $WorkDir "$Tag.sqlite"
  & $Exe index --project $Dproj --db $db *> (Join-Path $WorkDir "index-$Tag.log")
  $o = Join-Path $WorkDir "apply-$Tag.out"
  $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
    -ArgumentList @('cycles', '--fix', '--apply', '--no-backup', '--build-timeout', '600', '--cycle', '1', '--project', ('"' + $Dproj + '"'),
      '--db', ('"' + $db + '"'), '--library-db', ('"' + $Lib + '"')) `
    -RedirectStandardOutput $o -RedirectStandardError (Join-Path $WorkDir "apply-$Tag.err")
  return @{ Exit = $p.ExitCode; Out = [IO.File]::ReadAllText($o); Err = [IO.File]::ReadAllText((Join-Path $WorkDir "apply-$Tag.err")) }
}
function Test-Xml([string]$Text) { try { $null = [xml]$Text; return $true } catch { return $false } }

$Cases = @(
  @{ Tag = 'lf'; New = { param($d) New-Lf $d }; Dproj = 'CtorLab.dproj'; Anchor = 'LabCtorChild'; Added = 'LabCtorChild.Untangle.pas' },
  @{ Tag = 'rd'; New = { param($d) New-Rd $d }; Dproj = 'R1Extend.dproj'; Anchor = 'R1Nav'; Added = 'R1Title.pas' }
)

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  $Lib = Join-Path $WorkDir 'library-copy.sqlite'
  Copy-Item $LibraryDb $Lib

  Write-Host '== positive control: the old shape does not parse' -ForegroundColor Cyan
  $pcd = Join-Path $WorkDir 'pc'; New-Lf $pcd
  $pj = [IO.File]::ReadAllText((Join-Path $pcd 'CtorLab.dproj'))
  Check 'pc0 the multi-line fixture .dproj parses' (Test-Xml $pj) ''
  $old = $pj.Replace('<DCCReference Include="LabCtorChild.pas">', "<DCCReference Include=`"LabCtorChild.pas`">`r`n        <DCCReference Include=`"LabCtorChild.Untangle.pas`">")
  Check 'pc1 the opening line copied inside the element does NOT parse' (($old -cne $pj) -and -not (Test-Xml $old)) ''

  foreach ($c in $Cases) {
    $t = $c.Tag
    Write-Host "== $t : a new unit next to a multi-line DCCReference ($($c.Anchor))" -ForegroundColor Cyan
    $base = Join-Path $WorkDir "$t-base"; $edit = Join-Path $WorkDir "$t-edit"
    & $c.New $base; & $c.New $edit
    $b0 = Invoke-Build (Join-Path $base $c.Dproj)
    Check "${t}0 the untouched copy builds" $b0.Ok $b0.Errors
    $out0 = Invoke-Program (Join-Path $base $c.Dproj)
    $ap = Invoke-Apply (Join-Path $edit $c.Dproj) "$t-apply"
    Check "${t}1 the plan wrote something (not refused before the gate)" (-not ($ap.Out -match 'Fix it: not available')) ''
    Check "${t}2 --fix --apply passes the dcc gate (exit 0)" ($ap.Exit -eq 0) ("exit=$($ap.Exit) " + ((($ap.Out + $ap.Err).Trim() -split "`r?`n" | Select-Object -Last 3) -join ' | '))
    $pj = [IO.File]::ReadAllText((Join-Path $edit $c.Dproj))
    Check "${t}3 the applied .dproj parses as XML" (Test-Xml $pj) ''
    $rx = '(?s)<DCCReference Include="' + [regex]::Escape($c.Anchor) + '\.pas">.*?</DCCReference>\s*<DCCReference Include="' + [regex]::Escape($c.Added) + '"/>'
    Check "${t}4 the new unit is self-closing, after the element" ($pj -match $rx) $c.Added
    $b1 = Invoke-Build (Join-Path $edit $c.Dproj)
    Check "${t}5 the applied copy builds" $b1.Ok $b1.Errors
    $out1 = Invoke-Program (Join-Path $edit $c.Dproj)
    Check "${t}6 stdout byte-identical to the untouched build's" (($out0 -ne '<no exe>') -and ($out1 -ceq $out0)) ''
  }
} finally {
  if ((-not $KeepWorkDir) -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
