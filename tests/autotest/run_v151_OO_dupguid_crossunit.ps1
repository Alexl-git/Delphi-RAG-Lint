<#
  run_v151_OO_dupguid_crossunit.ps1 -- lane OO: duplicate-interface-guid across two units.
  Two units declare interfaces with the SAME GUID literal; a third unit has a dual interface plus a
  dispinterface sharing one GUID (type-library shape, same file) which must NOT be reported.
  Needs an engine whose extractor stores the interface GUID in symbols.signature (1.51, lane EXT).
  Run from a neutral cwd, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "C:\TEMP\draglint_oo_dupguid_$PID"
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }
try {
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }
function Write-Ascii($p,$t){ [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII) }
$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$proj = Join-Path $WorkDir 'proj'
New-Item -ItemType Directory -Path $proj -Force | Out-Null
Write-Ascii (Join-Path $proj 'uA.pas') @'
unit uA;

interface

type
  IAlpha = interface
    ['{11111111-2222-3333-4444-555555555555}']
    procedure Go;
  end;

implementation

end.
'@
Write-Ascii (Join-Path $proj 'uB.pas') @'
unit uB;

interface

type
  IBeta = interface
    ['{11111111-2222-3333-4444-555555555555}']
    procedure Stop;
  end;

implementation

end.
'@
Write-Ascii (Join-Path $proj 'uC.pas') @'
unit uC;

interface

type
  IDual = interface
    ['{99999999-8888-7777-6666-555555555555}']
    procedure Run;
  end;
  IDualDisp = dispinterface
    ['{99999999-8888-7777-6666-555555555555}']
    procedure Run;
  end;

implementation

end.
'@
Write-Ascii (Join-Path $proj 'uD.pas') @'
unit uD;

interface

type
  IUnique = interface
    ['{AAAAAAAA-8888-7777-6666-555555555555}']
    procedure Solo;
  end;

implementation

end.
'@
$db = Join-Path (Join-Path $proj '_D-RAG') 'p.sqlite'
& { $ErrorActionPreference = 'Continue'; & $exePath index $proj --db $db 2>&1 | ForEach-Object { "$_" } } | Out-Null
$out = & { $ErrorActionPreference = 'Continue'; & $exePath lint-all --db $db --rule duplicate-interface-guid 2>$null } | Out-String
$hits = @(($out -split "`r?`n") | Where-Object { $_ -match 'duplicate-interface-guid' })
Check 'A1 cross-unit duplicate GUID is reported (exactly one, on the second unit)' `
  (($hits.Count -eq 1) -and ($hits[0] -match 'uB\.pas')) "hits=$($hits.Count): $($hits -join ' | ')"
Check 'A2 dual+dispinterface in one file is not reported' (-not ($out -match 'uC\.pas')) $out
Check 'A3 unique GUID is not reported' (-not ($out -match 'uD\.pas')) $out
Write-Host ''
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
