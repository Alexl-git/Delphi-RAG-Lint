<#
  run_type_qualifier_honoured.ps1 -- a QUALIFIED type name binds only to a
  candidate whose qualified name ends with what was written.

  THE PROBLEM. ResolveTypeNameToSymbol stripped the qualifier and judged the
  last segment alone, so `Vcl.Imaging.jpeg.TJPEGImage.Create` -- a qualifier
  whose whole purpose is to say WHICH TJPEGImage -- could bind to
  SynGdiPlus.TJpegImage in a unit that also used SynGdiPlus. The receiver rung
  handed it only the last segment, and a comment claimed "a wrong unit cannot
  silently bind".

  THE FIX (resolver 1.11.0-alpha). What was written must be a segment-aligned
  suffix of the candidate's qualified name: a unit qualifier (`uLibA.TWidget`,
  the bare `LibA`-less form excluded) and a nesting qualifier (`TOuter.TInner`)
  alike. The receiver rung now passes the whole dotted text.

  Usage: pwsh -File tests/callresolve/run_type_qualifier_honoured.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_type_qualifier_$PID"
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

# The ONLY TWidget in the index, in a unit the caller DOES use -- so the
# visibility rule of 1.11.0 would let a bare `TWidget` bind here.
Write-Ascii (Join-Path $src 'uLibA.pas') @'
unit uLibA;

interface

type
  TWidget = class(TObject)
  public
    constructor Create;
  end;

  TOuter = class(TObject)
  public
    type
      TInner = class(TObject)
      public
        constructor Create;
      end;
  end;

implementation

constructor TWidget.Create;
begin
end;

constructor TOuter.TInner.Create;
begin
end;

end.
'@
Write-Ascii (Join-Path $src 'uCaller.pas') @'
unit uCaller;

interface

uses
  uLibA, Vcl.Imaging.jpeg;

procedure WrongUnit;
procedure RightUnit;
procedure Nested;

implementation

procedure WrongUnit;
begin
  Vcl.Imaging.jpeg.TWidget.Create;
end;

procedure RightUnit;
begin
  uLibA.TWidget.Create;
end;

procedure Nested;
begin
  TOuter.TInner.Create;
end;

end.
'@

$db = Join-Path $WorkDir 'qual.sqlite'
& $exePath index $src --db $db --quiet 2>&1 | Out-Null
Check 'precondition: index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

function Callees([string]$QName) { return ((& $exePath find-callees --qname $QName --db $db 2>$null) -join "`n") }

$w = Callees 'uCaller.WrongUnit'
Check 'ASSERT: Vcl.Imaging.jpeg.TWidget does NOT bind to uLibA.TWidget' ($w -notmatch 'uLibA\.TWidget\.Create') "callees: $w"
$r = Callees 'uCaller.RightUnit'
Check 'CONTROL: uLibA.TWidget.Create binds [certain]' ($r -match 'uLibA\.TWidget\.Create\s+\[certain\]') "callees: $r"
$n = Callees 'uCaller.Nested'
Check 'CONTROL: a NESTING qualifier (TOuter.TInner) still binds' ($n -match 'TOuter\.TInner\.Create') "callees: $n"

Write-Host ''
if ($script:fail) { Write-Host 'RESULT: FAIL'; exit 1 }
Write-Host 'RESULT: PASS'; exit 0
} finally {
  foreach ($d in @("$env:TEMP\draglint_type_qualifier_$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
