<#
  run_context_capped_surface_docs.ps1 -- CTX-SURFACE-DOCS (1.42, owner ruling D8)
  When `context` on a whole TYPE engages the body cap, the class surface drops the
  `///` docs of members whose body was omitted by the cap; members whose body is
  kept (focus word / in-type callers) keep their docs. Uncapped output is unchanged.

  CHECKS (fixture TBig, cap 350 keeps Helper + Alpha, omits Beta + Bulky + Focus unless named):
    S1 capped: docs of omitted members (Beta, Bulky) are gone from ## Class surface
    S2 capped: docs of kept members (Helper, Alpha) stay
    S3 a FOCUS word keeps that member's docs
    S4 the declarations of omitted members stay (only the docs go)
  CONTROLS:
    C1 --max-body-tokens 0 keeps every member doc
    C2 a small type under the default cap keeps its docs
    C3 --full-surface keeps every doc even when capped
  Run from any CWD, pwsh 7. Builds its own fixture; touches no shared index.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_context_capped_surface_docs_$PID"
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
    /// DOCHELPER helper doc
    procedure Helper;
    /// DOCALPHA alpha doc
    procedure Alpha;
    /// DOCBETA beta doc
    procedure Beta;
    /// DOCBULKY bulky doc
    procedure Bulky;
    /// DOCFOCUS focus doc
    procedure Focus;
  end;

  TSmall = class
  public
    /// DOCONE one doc
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

function Bundle([string]$Task, [string[]]$Extra = @()) {
  return ((& $exePath context --task $Task --db $db --format markdown @Extra 2>$null) -join "`n")
}
function Section([string]$Text, [string]$Head) {
  if ($Text -match ('(?s)## ' + $Head + '[^\n]*\n(.*?)(\n## |\z)')) { return $Matches[1] }
  return ''
}

$m  = Bundle 'modify uCap.TBig' @('--max-body-tokens', '350')
$cs = Section $m 'Class surface'
Check 'V2 the surface section exists' ($cs -ne '') ($m -replace "`n", ' / ')
Check 'S1 capped: docs of omitted members are dropped' (($cs -notmatch 'DOCBETA') -and ($cs -notmatch 'DOCBULKY')) ($cs -replace "`n", ' / ')
Check 'S2 capped: docs of kept members stay' (($cs -match 'DOCHELPER') -and ($cs -match 'DOCALPHA')) ($cs -replace "`n", ' / ')
Check 'S4 declarations of omitted members stay' (($cs -match 'procedure Beta;') -and ($cs -match 'procedure Bulky;')) ($cs -replace "`n", ' / ')

$f  = Bundle 'modify uCap.TBig Focus' @('--max-body-tokens', '350')
Check 'S3 a focus word keeps that member doc' ((Section $f 'Class surface') -match 'DOCFOCUS') ((Section $f 'Class surface') -replace "`n", ' / ')

$u  = Bundle 'modify uCap.TBig' @('--max-body-tokens', '0')
$us = Section $u 'Class surface'
Check 'C1 CONTROL uncapped keeps every doc' (($us -match 'DOCBETA') -and ($us -match 'DOCBULKY') -and ($us -match 'DOCHELPER')) ($us -replace "`n", ' / ')
$sm = Bundle 'modify uCap.TSmall'
Check 'C2 CONTROL a small type keeps its docs' ((Section $sm 'Class surface') -match 'DOCONE') ((Section $sm 'Class surface') -replace "`n", ' / ')
$fu = Bundle 'modify uCap.TBig' @('--max-body-tokens', '350', '--full-surface')
Check 'C3 CONTROL --full-surface keeps every doc' (((Section $fu 'Class surface') -match 'DOCBETA') -and ((Section $fu 'Class surface') -match 'DOCBULKY')) ((Section $fu 'Class surface') -replace "`n", ' / ')

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_context_capped_surface_docs_$PID")) { if (Test-Path -LiteralPath $d23) { [IO.Directory]::Delete($d23, $true) } }
}