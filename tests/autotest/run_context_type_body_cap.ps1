<#
  run_context_type_body_cap.ps1 -- CTX-TYPECAP (1.41)
  `context` on a whole TYPE caps its method bodies at --max-body-tokens
  (default 20000; 0 = uncapped); the rest are listed as header + line range.
  Spec: docs\superpowers\specs\2026-11-03-ctx-typecap-design.md.

  THE DEFECT. `context --task "modify TSQLiteSymbolStore"` emitted ~262k
  estimated tokens: 204 method bodies (150k) plus the class declaration a
  second time (67k) beside the class surface (47k).

  CHECKS (fixture TBig: Helper is called by three siblings and is the LARGEST
  of the small bodies, so a pure size-ascending pick would drop it):
    T1 the cap engages: an `## Omitted bodies` section with the cap note
    T2 in-type callers beat size: Helper + Alpha kept, Beta dropped
    T3 the omitted list carries the header line and a line range
    T4 the class-decl chunk is dropped while capped (surface present)
    T5 a FOCUS word after the type name keeps that body even past the cap
    T6 json carries body_cap / bodies_omitted / omitted_bodies
  CONTROLS:
    C1 --max-body-tokens 0 restores every body and the class-decl chunk
    C2 a MEMBER target is never cut, whatever the cap
    C3 a small type under the default cap is unchanged (no Omitted section)
    C4 the focus phrase still resolves the TYPE (header names TBig)

  Run from any CWD, pwsh 7. Builds its own fixture; touches no shared index.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_context_type_body_cap_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function Write-Ascii($p,$t){ [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }
function Body([int]$Lines, [string]$Extra) {
  $b = "begin`n"
  if ($Extra) { $b += "  $Extra`n" }
  for ($i = 0; $i -lt $Lines; $i++) { $b += "  FX := FX + 1;`n" }
  return $b + "end;`n"
}

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Path $src -Force | Out-Null

$impl = "procedure TBig.Helper;`n" + (Body 40 '') + "`n" +
        "procedure TBig.Alpha;`n"  + (Body 25 'Helper;') + "`n" +
        "procedure TBig.Beta;`n"   + (Body 25 'Helper;') + "`n" +
        "procedure TBig.Bulky;`n"  + (Body 100 '') + "`n" +
        "procedure TBig.Focus;`n"  + (Body 100 'Helper;') + "`n" +
        "procedure TSmall.One;`nbegin`nend;`n`nprocedure TSmall.Two;`nbegin`nend;`n"
Write-Ascii (Join-Path $src 'uCap.pas') @"
unit uCap;

interface

type
  TBig = class
  private
    FX: Integer;
  public
    procedure Helper;
    procedure Alpha;
    procedure Beta;
    procedure Bulky;
    procedure Focus;
  end;

  TSmall = class
  public
    procedure One;
    procedure Two;
  end;

implementation

$impl
end.
"@

$db = Join-Path $WorkDir 'fx.sqlite'
& $exePath index $src --db $db 2>&1 | Out-Null
Check 'V the fixture index was built' (Test-Path $db) $db

function Bundle([string]$Task, [string[]]$Extra = @(), [string]$Fmt = 'markdown') {
  return ((& $exePath context --task $Task --db $db --format $Fmt @Extra 2>$null) -join "`n")
}
function Section([string]$Text, [string]$Head) {
  if ($Text -match ('(?s)## ' + $Head + '[^\n]*\n(.*?)(\n## |\z)')) { return $Matches[1] }
  return ''
}

$m  = Bundle 'modify uCap.TBig' @('--max-body-tokens', '350')
$sl = Section $m 'Impl slice'
$om = Section $m 'Omitted bodies'
Check 'T1 the cap engages: ## Omitted bodies + cap note' (($om -ne '') -and ($om -match 'omitted by cap 350; rerun with --max-body-tokens 0')) ($m -replace "`n", ' / ')
Check 'T2 in-type callers beat size: Helper and Alpha kept, Beta dropped' `
      (($sl -match 'procedure TBig\.Helper;') -and ($sl -match 'procedure TBig\.Alpha;') -and -not ($sl -match 'procedure TBig\.Beta;')) ($sl -replace "`n", ' / ')
Check 'T3 the omitted list names header + line range' `
      (($om -match '`procedure TBig\.Bulky;` -- L\d+-\d+') -and ($om -match 'procedure TBig\.Beta;') -and ($om -match 'procedure TBig\.Focus;')) ($om -replace "`n", ' / ')
Check 'T4 the class-decl chunk is dropped while capped' ((-not ($sl -match '--- class-decl ---')) -and ($om -match 'class declaration')) ($sl -replace "`n", ' / ')

$f  = Bundle 'modify uCap.TBig Focus' @('--max-body-tokens', '350')
$fs = Section $f 'Impl slice'
Check 'T5 a focus word keeps that body past the cap' (($fs -match 'procedure TBig\.Focus;') -and -not ($fs -match 'procedure TBig\.Bulky;')) ($f -replace "`n", ' / ')
Check 'C4 CONTROL the focus phrase still resolves the type' ($f -match '# Context bundle: modify uCap\.TBig\s*\n') (($f -split "`n")[0])

$j = Bundle 'modify uCap.TBig' @('--max-body-tokens', '350') 'json'
$jo = $null; try { $jo = $j | ConvertFrom-Json } catch { }
Check 'T6 json carries the body-cap keys' (($null -ne $jo) -and ($jo.body_cap -eq 350) -and ($jo.bodies_omitted -eq 3) -and (@($jo.omitted_bodies).Count -eq 4) -and (@($jo.omitted_bodies | Where-Object { $_.signature -eq 'procedure TBig.Bulky;' -and $_.start_line -gt 0 }).Count -eq 1)) $j.Substring(0, [Math]::Min(400, $j.Length))

$u  = Bundle 'modify uCap.TBig' @('--max-body-tokens', '0')
$us = Section $u 'Impl slice'
Check 'C1 CONTROL --max-body-tokens 0 restores every body + class-decl' `
      ((($us | Select-String -Pattern 'procedure TBig\.\w+;' -AllMatches).Matches.Count -ge 5) -and ($us -match '--- class-decl ---') -and ((Section $u 'Omitted bodies') -eq '')) ($us -replace "`n", ' / ')
$mm = Bundle 'modify uCap.TBig.Bulky' @('--max-body-tokens', '10')
Check 'C2 CONTROL a member target is never cut' (((Section $mm 'Impl slice') -match 'procedure TBig\.Bulky;') -and ((Section $mm 'Omitted bodies') -eq '')) ($mm -replace "`n", ' / ')
$sm = Bundle 'modify uCap.TSmall'
Check 'C3 CONTROL a small type is unchanged under the default cap' `
      (((Section $sm 'Impl slice') -match 'procedure TSmall\.Two;') -and ((Section $sm 'Impl slice') -match '--- class-decl ---') -and ((Section $sm 'Omitted bodies') -eq '')) ($sm -replace "`n", ' / ')

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_context_type_body_cap_$PID")) { if (Test-Path -LiteralPath $d23) { [IO.Directory]::Delete($d23, $true) } }
}