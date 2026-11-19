<#
  run_v151_DFMREN_form_rename.ps1 -- wave v151 lane DFMREN (P16): renaming a form's component through the compile gate.

  A published field of a form class is named three ways: the field in the class, every code reference, and the form
  file (`object Name: TType`, `inherited Name: TType` in a descendant, `Prop = Name`). `rename --apply --project` must
  rewrite all of them, write the real bytes, build the project with the gate, and the built program must load every
  form with the field bound. What the proof cannot decide refuses, with a message that says why.

  Fixture: tests\autotest\fixtures\v151-DFMREN\frdemo (FrDemo.dproj, a console program that creates TFrmMain and its
  descendant TFrmKid and prints the names the streaming bound) and ...\vclstub (a miniature platform library: the VCL
  ancestors the proof walks, indexed into its own DB).
    a  the gated rename of FrMain.TFrmMain.BtnGo -> BtnRun: exit 0; the field, the code references in FrMain, FrKid and
       FrUse, `object BtnRun: TButton`, `FocusControl = BtnRun` and the descendant's `inherited BtnRun: TButton` are
       rewritten; the caption 'BtnGo stays' is not; the `compile gate:` report of both builds is on stderr.
    b  the program the gate built runs and prints main=BtnRun focus=BtnRun kid=BtnRun: every form loaded and bound.
    c  a string that names the component (`FindComponent('BtnGo')`): refused [name-in-string], exit 2, nothing
       written. POSITIVE CONTROL: the same name inside a comment on that line is not a second refusal.
    d  a frame's component that a host form overrides under `inline`: refused [dfm-name-unbound], the message names
       the embedded frame.
  RED on 655411523 (GATE tip): a has no `compile gate:` lines on stderr, c applies the rename (exit 0).
  Needs dcc: SKIPs (exit 0) when rsvars.bat is missing.
#>
param(
  [string]$Exe    = '',
  [string]$Rsvars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Continue'  # native stderr must not terminate; every call is checked by exit code
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "  ok   $Name" } else { $script:Failed = $true; Write-Host "  FAIL $Name $Detail" -ForegroundColor Red }
}
if (-not (Test-Path $Rsvars)) { Write-Host "SKIP: no rsvars.bat ($Rsvars)" -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Fx  = (Resolve-Path "$PSScriptRoot\fixtures\v151-DFMREN").Path
$Tmp = Join-Path $env:TEMP ('v151_dfmren_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($Tmp) | Out-Null
$Lib = Join-Path $Tmp 'lib.sqlite'
$null = ($null | & { $ErrorActionPreference = 'Continue'; $input | & $Exe index (Join-Path $Fx 'vclstub') --db $Lib --library-db none 2>&1 | ForEach-Object { "$_" } } | Out-String)

function New-Case([string]$Tag, [scriptblock]$Edit = $null) {
  $d = Join-Path $Tmp $Tag
  Copy-Item (Join-Path $Fx 'frdemo') $d -Recurse
  if ($Edit) { & $Edit $d }
  $db = Join-Path $d 'p.sqlite'
  $null = ($null | & { $ErrorActionPreference = 'Continue'; $input | & $Exe index --project (Join-Path $d 'FrDemo.dproj') --db $db --library-db none 2>&1 | ForEach-Object { "$_" } } | Out-String)
  if ($LASTEXITCODE -ne 0) { throw "index $Tag exit $LASTEXITCODE" }
  return @{ Dir = $d; Db = $db; Proj = (Join-Path $d 'FrDemo.dproj') }
}
function Rename($C, [string]$QName, [string]$To, [string[]]$Mode) {
  $errFile = Join-Path $Tmp 'stderr.txt'
  $a = @('rename', '--kind', 'symbol', '--name', $QName, '--to', $To, '--db', $C.Db, '--library-db', $Lib) + $Mode
  $out = ($null | & { $ErrorActionPreference = 'Continue'; $input | & $Exe @a 2> $errFile } | Out-String)
  $code = $LASTEXITCODE
  return @{ Code = $code; Out = $out; Err = [IO.File]::ReadAllText($errFile) }
}
function Txt($C, [string]$Name) { return [IO.File]::ReadAllText((Join-Path $C.Dir $Name)) }
function Hashes($C) { return ((Get-ChildItem $C.Dir -Include '*.pas', '*.dfm' -Recurse | Sort-Object Name | Get-FileHash -Algorithm SHA1).Hash -join ',') }

try {
  $gate = @('--project', '', '--rsvars', $Rsvars, '--build-timeout', '600', '--apply', '--no-backup')

  # a: the gated rename rewrites the field, the code, the form and its descendant
  $A = New-Case 'a'
  $gate[1] = $A.Proj
  $r = Rename $A 'FrMain.TFrmMain.BtnGo' 'BtnRun' $gate
  Check 'a1 applied: exit 0' ($r.Code -eq 0) "exit $($r.Code) $($r.Out) $($r.Err)"
  Check 'a2 the field' ((Txt $A 'FrMain.pas') -match 'BtnRun: TButton;') (Txt $A 'FrMain.pas')
  Check 'a3 the method body' ((Txt $A 'FrMain.pas') -match 'BtnRun\.Caption:= ''poked''') (Txt $A 'FrMain.pas')
  Check 'a4 the descendant''s code' ((Txt $A 'FrKid.pas') -match 'Result:= BtnRun\.Caption') (Txt $A 'FrKid.pas')
  Check 'a5 the other unit''s qualified refs' ((Txt $A 'FrUse.pas') -match 'M\.BtnRun\.Name' -and (Txt $A 'FrUse.pas') -match 'K\.BtnRun\.Name') (Txt $A 'FrUse.pas')
  Check 'a6 object header in the form' ((Txt $A 'FrMain.dfm') -match 'object BtnRun: TButton') (Txt $A 'FrMain.dfm')
  Check 'a7 property value in the form' ((Txt $A 'FrMain.dfm') -match 'FocusControl = BtnRun') (Txt $A 'FrMain.dfm')
  Check 'a8 a caption string stays' ((Txt $A 'FrMain.dfm') -match 'Caption = ''BtnGo stays''') (Txt $A 'FrMain.dfm')
  Check 'a9 the descendant form''s inherited header' ((Txt $A 'FrKid.dfm') -match 'inherited BtnRun: TButton') (Txt $A 'FrKid.dfm')
  Check 'a10 no BtnGo token is left outside the caption' (-not ((Txt $A 'FrMain.pas') + (Txt $A 'FrKid.pas') + (Txt $A 'FrUse.pas') + (Txt $A 'FrKid.dfm') -match '\bBtnGo\b')) ''
  Check 'a11 compile gate report of build 1 on stderr' ($r.Err -match 'compile gate: build 1 \(before the write\): 0 error') $r.Err
  Check 'a12 compile gate report of build 2 on stderr' ($r.Err -match 'compile gate: build 2 \(after the write\): 0 error') $r.Err

  # b: the program the gate built loads every form with the renamed field bound
  $prog = Join-Path $A.Dir 'Win64\Debug\FrDemo.exe'
  Check 'b1 the gate built the program' (Test-Path $prog) $prog
  if (Test-Path $prog) {
    $o = (& { $ErrorActionPreference = 'Continue'; & $prog 2>&1 | ForEach-Object { "$_" } } | Out-String)
    Check 'b2 every form loads, the field and FocusControl bound' ($LASTEXITCODE -eq 0 -and $o -match 'main=BtnRun focus=BtnRun kid=BtnRun') $o
  }

  # c: a string that names the component refuses; a comment does not
  $C = New-Case 'c' {
    param($d)
    $u = Join-Path $d 'FrUse.pas'
    $t = [IO.File]::ReadAllText($u).Replace("    M.Poke;`r`n", "    M.Poke;`r`n    if M.FindComponent('BtnGo') = nil then Writeln('lost'); // 'BtnGo' in a comment`r`n")
    [IO.File]::WriteAllText($u, $t, [Text.Encoding]::ASCII)
  }
  $hc = Hashes $C
  $gate[1] = $C.Proj
  $r = Rename $C 'FrMain.TFrmMain.BtnGo' 'BtnRun' $gate
  Check 'c1 refused: exit 2' ($r.Code -eq 2) "exit $($r.Code) $($r.Out)"
  Check 'c2 [name-in-string] at the FindComponent literal' ($r.Out -match 'FrUse\.pas:19:\d+: refused \[name-in-string\]') $r.Out
  Check 'c3 the comment is not a refusal (one occurrence only)' (([regex]::Matches($r.Out, 'refused \[name-in-string\]')).Count -eq 1) $r.Out
  Check 'c4 nothing written' ((Hashes $C) -eq $hc) ''

  # d: a frame's component overridden in a host form under `inline` refuses with a message naming the frame
  $D = New-Case 'd'
  $r = Rename $D 'FrFrame.TFrmFrame.BtnF' 'BtnFx' @('--plan')
  Check 'd1 [dfm-name-unbound] in the host form' ($r.Out -match 'FrMain\.dfm:\d+:\d+: refused \[dfm-name-unbound\]') $r.Out
  Check 'd2 the message names the embedded frame' ($r.Out -match 'embedded frame') $r.Out
}
finally {
  if (-not $script:Failed) { try { [IO.Directory]::Delete($Tmp, $true) } catch { } }
  else { Write-Host "  work kept: $Tmp" }
}
if ($script:Failed) { Write-Host 'run_v151_DFMREN_form_rename: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_v151_DFMREN_form_rename: PASS' -ForegroundColor Green
exit 0
