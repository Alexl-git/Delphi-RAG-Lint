<#
  run_wiring_form_scoped.ps1 -- `wiring --qname TForm` lists only the DFM
  bindings that can reach THAT form's methods.

  THE PROBLEM (evaluation on ProjectA, 2026-09-28). FindEventHandlersForForm took
  each method of the form class and returned every `event-binding` ref of the
  same NAME, in any DFM of the index. Two forms that both have a btnOKClick
  (every dialog does) each "owned" the other's binding: TFSavePrompt reported 911
  handler bindings, 12 of them its own.

  THE FIX. Only two kinds of DFM are admitted: the form's paired .dfm, and a
  DESCENDANT form's paired .dfm -- an `inherited` form whose component binds the
  ancestor's handler -- unless that descendant declares its own method of the
  name, in which case the binding is the descendant's.

  Usage: pwsh -File tests/autotest/run_wiring_form_scoped.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-wiring-scoped-$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $src | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
function FormUnit([string]$Unit, [string]$Cls, [string]$Parent, [string[]]$Methods) {
  $decl = ($Methods | ForEach-Object { "    procedure ${_}(Sender: TObject);" }) -join "`n"
  $impl = ($Methods | ForEach-Object { "procedure $Cls.${_}(Sender: TObject);`nbegin`nend;`n" }) -join "`n"
  return "unit $Unit;`n`ninterface`n`nuses`n  uBaseForm;`n`ntype`n  $Cls = class($Parent)`n  published`n$decl`n  end;`n`nimplementation`n`n$impl`nend.`n"
}

Write-Ascii (Join-Path $src 'uBaseForm.pas') @'
unit uBaseForm;

interface

type
  TBaseForm = class(TObject)
  end;

implementation

end.
'@
# Two unrelated forms, each with its own btnOKClick.
Write-Ascii (Join-Path $src 'uFormA.pas') (FormUnit 'uFormA' 'TFormA' 'TBaseForm' @('btnOKClick'))
Write-Ascii (Join-Path $src 'uFormA.dfm') "object FormA: TFormA`n  object btnOK: TButton`n    OnClick = btnOKClick`n  end`nend`n"
Write-Ascii (Join-Path $src 'uFormB.pas') (FormUnit 'uFormB' 'TFormB' 'TBaseForm' @('btnOKClick'))
Write-Ascii (Join-Path $src 'uFormB.dfm') "object FormB: TFormB`n  object btnOK: TButton`n    OnClick = btnOKClick`n  end`nend`n"
# A descendant of TFormA whose inherited DFM binds the ANCESTOR's handler...
Write-Ascii (Join-Path $src 'uFormC.pas') ((FormUnit 'uFormC' 'TFormC' 'TFormA' @('Nothing')) -replace 'uses\n  uBaseForm;', "uses`n  uBaseForm, uFormA;")
Write-Ascii (Join-Path $src 'uFormC.dfm') "inherited FormC: TFormC`n  inherited btnOK: TButton`n    OnClick = btnOKClick`n  end`nend`n"
# ...and one that REDECLARES it, so its binding is its own.
Write-Ascii (Join-Path $src 'uFormD.pas') ((FormUnit 'uFormD' 'TFormD' 'TFormA' @('btnOKClick')) -replace 'uses\n  uBaseForm;', "uses`n  uBaseForm, uFormA;")
Write-Ascii (Join-Path $src 'uFormD.dfm') "inherited FormD: TFormD`n  inherited btnOK: TButton`n    OnClick = btnOKClick`n  end`nend`n"

$db = Join-Path $WorkDir 'w.sqlite'
& $Exe index $src --db $db --quiet 2>&1 | Out-Null
Check 'precondition: index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

$w = @(& $Exe wiring --qname TFormA --db $db 2>$null)
$bind = @($w | Where-Object { $_ -match 'btnOKClick <- ' })
Check 'precondition: the index holds four btnOKClick bindings in four DFMs' `
  ((@(& $Exe query find-callers --name btnOKClick --db $db 2>$null) | Where-Object { $_ -match '\.dfm:' }).Count -eq 4) ''
Check 'ASSERT: TFormA''s own DFM binding is listed' (@($bind | Where-Object { $_ -match 'uFormA\.dfm' }).Count -eq 1) ($bind -join ' | ')
Check 'ASSERT: an unrelated form''s same-named binding is NOT (uFormB.dfm)' (@($bind | Where-Object { $_ -match 'uFormB\.dfm' }).Count -eq 0) ($bind -join ' | ')
Check 'ASSERT: an inherited form binding the ANCESTOR''s handler IS listed (uFormC.dfm)' (@($bind | Where-Object { $_ -match 'uFormC\.dfm' }).Count -eq 1) ($bind -join ' | ')
Check 'ASSERT: a descendant that REDECLARES the handler owns its binding (uFormD.dfm not listed)' (@($bind | Where-Object { $_ -match 'uFormD\.dfm' }).Count -eq 0) ($bind -join ' | ')

Write-Host ''
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d in @("$env:TEMP\drag-lint-wiring-scoped-$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
