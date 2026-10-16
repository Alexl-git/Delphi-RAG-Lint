<#
  run_type_binding_uses_visibility.ps1 -- a type NAME binds only to a unit the
  calling file can see.

  THE PROBLEM (field report, 2026-09-29). UAuxHash.pas uses Vcl.Imaging.jpeg and
  writes `vJpegDestino := TJPEGImage.Create; vJpegDestino.Assign(...)`. A project
  DB holds no library unit, so the only TJpegImage in it was SynGdiPlus's --
  swept into the closure by some OTHER unit -- and ResolveTypeNameToSymbol's last
  rung ("no candidate in scope, exactly one in the DB") bound both calls to it,
  [certain]. The .dcu references Vcl.Imaging.jpeg only. ~956 edges on ProjectA
  took that rung, 744 of them certain.

  THE FIX (resolver 1.11.0-alpha). The rung binds only when the caller's uses
  clause NAMES the candidate's unit -- as written, or as a bare name that the
  namespace prefix completes -- or when the caller has no uses rows at all.

  CONTROLS, so a build that declines everything cannot pass:
    * the same code in a unit that DOES use the candidate's unit binds certain;
    * a bare `uses FixDlg` still reaches Vcl.FixDlg.pas (the target the uses
      graph refuses to infer into a GUI namespace, and which ProjectA's local
      Vcl.Dialogs.pas copy depends on);
    * a unit with no uses clause keeps the old answer.

  Usage: pwsh -File tests/callresolve/run_type_binding_uses_visibility.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_type_uses_visibility_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $tag = if ($Ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("[{0}] {1}{2}" -f $tag, $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
  if (-not $Ok) { $script:fail = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe"; exit 2 }
$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Path $src | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# The ONLY TWidget in the index, as SynGdiPlus.TJpegImage was.
Write-Ascii (Join-Path $src 'uLibA.pas') @'
unit uLibA;

interface

type
  TWidget = class(TObject)
  public
    constructor Create;
    procedure Assign(A: Integer);
  end;

implementation

constructor TWidget.Create;
begin
end;

procedure TWidget.Assign(A: Integer);
begin
end;

end.
'@
Write-Ascii (Join-Path $src 'uOther.pas') @'
unit uOther;

interface

procedure Nop;

implementation

procedure Nop;
begin
end;

end.
'@
# The caller's TWidget comes from a library unit this index does not hold.
$body = @'

procedure UseWidget;
var
  V: TWidget;
begin
  V := TWidget.Create;
  V.Assign(1);
end;

end.
'@
Write-Ascii (Join-Path $src 'uCaller.pas') ("unit uCaller;`n`ninterface`n`nuses`n  uOther, Vcl.Imaging.jpeg;`n`nprocedure UseWidget;`n`nimplementation`n" + $body)
Write-Ascii (Join-Path $src 'uCallerOk.pas') ("unit uCallerOk;`n`ninterface`n`nuses`n  uOther, uLibA;`n`nprocedure UseWidget;`n`nimplementation`n" + $body)
Write-Ascii (Join-Path $src 'uNoUses.pas') ("unit uNoUses;`n`ninterface`n`nprocedure UseWidget;`n`nimplementation`n" + $body)

# Namespace control: a local Vcl.* unit reached through a bare uses name.
Write-Ascii (Join-Path $src 'Vcl.FixDlg.pas') @'
unit Vcl.FixDlg;

interface

type
  TFixDlg = class(TObject)
  public
    procedure Run;
  end;

implementation

procedure TFixDlg.Run;
begin
end;

end.
'@
Write-Ascii (Join-Path $src 'uNsUser.pas') @'
unit uNsUser;

interface

uses
  FixDlg;

procedure UseDlg;

implementation

procedure UseDlg;
var
  D: TFixDlg;
begin
  D.Run;
end;

end.
'@

$db = Join-Path $WorkDir 'vis.sqlite'
& $exePath index $src --db $db --quiet 2>&1 | Out-Null
Check 'precondition: index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

function Callees([string]$QName) { return ((& $exePath find-callees --qname $QName --db $db 2>$null) -join "`n") }

$bad = Callees 'uCaller.UseWidget'
Check 'ASSERT: TWidget.Create does NOT bind to a unit the caller never names' ($bad -notmatch 'uLibA\.TWidget\.Create') "callees: $bad"
Check 'ASSERT: V.Assign does NOT bind either (the local''s type is the same name)' ($bad -notmatch 'uLibA\.TWidget\.Assign') "callees: $bad"

$ok = Callees 'uCallerOk.UseWidget'
Check 'CONTROL: the same code in a unit that USES uLibA binds Create [certain]' ($ok -match 'uLibA\.TWidget\.Create\s+\[certain\]') "callees: $ok"
Check 'CONTROL: ... and Assign [certain]' ($ok -match 'uLibA\.TWidget\.Assign\s+\[certain\]') "callees: $ok"

$ns = Callees 'uNsUser.UseDlg'
Check 'CONTROL: bare `uses FixDlg` still reaches the local Vcl.FixDlg.pas' ($ns -match 'Vcl\.FixDlg\.TFixDlg\.Run') "callees: $ns"

$nu = Callees 'uNoUses.UseWidget'
Check 'CONTROL: a unit with NO uses rows keeps the old single-global answer' ($nu -match 'uLibA\.TWidget\.Create') "callees: $nu"

Write-Host ''
if ($script:fail) { Write-Host 'RESULT: FAIL'; exit 1 }
Write-Host 'RESULT: PASS'; exit 0
} finally {
  foreach ($d in @("$env:TEMP\draglint_type_uses_visibility_$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
