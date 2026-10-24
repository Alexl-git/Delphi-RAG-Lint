<#
  run_context_callers_scoped_to_target.ps1 --
  `context --task "modify <Unit.TType.Create>"` must list callers of THAT
  constructor, not every `Create` in the index.

  THE DEFECT (stats\draglint-gaps.log 2026-10-23, re-measured on the W6-Q lane).
  `context --task "modify DragLint.Plugin.DockForm.TDragLintDockFrame.Create"`
  printed `## Callers (5)`: TDragLintWizard.Create, TCriticalSection.Create,
  TFileStream.Create ... -- none of them a call to the dock frame. The bundler
  reduced the target to its LAST segment and asked the store for every ref named
  `Create` (DRagLint.Context.Bundler.pas, Callers section).

  THE RULE. A ref the resolver bound to ANOTHER symbol is not a caller. An
  unresolved ref of a CONSTRUCTOR is kept only when it was written against the
  owning type, unqualified, Self or inherited -- the receiver rule
  FindUnresolvedNameCallers already applies to the Called-from '?' bucket.

  Run from any CWD, pwsh 7. Builds its own fixture; touches no shared index.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_context_callers_scoped_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function Write-Ascii($p,$t){ [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Path $src -Force | Out-Null

Write-Ascii (Join-Path $src 'uA.pas') @"
unit uA;

interface

type
  TAlpha = class(TObject)
  public
    constructor Create;
    procedure Run;
  end;

  TBeta = class(TObject)
  public
    constructor Create;
  end;

implementation

constructor TAlpha.Create;
begin
  inherited Create;
end;

procedure TAlpha.Run;
begin
end;

constructor TBeta.Create;
begin
  inherited Create;
end;

end.
"@

Write-Ascii (Join-Path $src 'uC.pas') @"
unit uC;

interface

procedure UseThem;

implementation

uses
  Classes, uA;

procedure UseThem;
var
  A: TAlpha;
  B: TBeta;
  S: TStringList;
begin
  A := TAlpha.Create; { ALPHA_SITE }
  B := TBeta.Create; { BETA_SITE }
  S := TStringList.Create; { FOREIGN_SITE }
  A.Run; { RUN_SITE }
end;

end.
"@

$db = Join-Path $WorkDir 'fx.sqlite'
& $exePath index $src --db $db 2>&1 | Out-Null
Check 'V the fixture index was built' (Test-Path $db) $db

function Bundle([string]$Task) {
  return ((& $exePath context --task $Task --db $db --format markdown --context 0 2>$null) -join "`r`n")
}
function CallersOf([string]$b) {
  $i = $b.IndexOf('## Callers')
  if ($i -lt 0) { return '' }
  $rest = $b.Substring($i)
  $j = $rest.IndexOf("`r`n## ", 3)
  if ($j -gt 0) { $rest = $rest.Substring(0, $j) }
  return $rest
}

$alpha = CallersOf (Bundle 'modify uA.TAlpha.Create')
$run   = CallersOf (Bundle 'modify uA.TAlpha.Run')

# ---- POSITIVE CONTROLS -------------------------------------------------------
# Without P1 an empty Callers section would pass T1/T2 vacuously.
Check 'P1 POSITIVE CONTROL TAlpha.Create lists its real call site (uC.pas:18)' `
      ($alpha -match 'uC\.pas:18:') "callers section: $alpha"
Check 'P2 POSITIVE CONTROL a non-constructor member keeps its variable-receiver caller (A.Run, uC.pas:21)' `
      ($run -match 'uC\.pas:21:') "callers section: $run"

# ---- the defect ---------------------------------------------------------------
Check 'T1 a Create the resolver bound to ANOTHER type (TBeta.Create, uC.pas:19) is not listed' `
      (-not ($alpha -match 'uC\.pas:19:')) "callers section: $alpha"
Check 'T2 an unresolved Create on a FOREIGN type (TStringList.Create, uC.pas:20) is not listed' `
      (-not ($alpha -match 'uC\.pas:20:')) "callers section: $alpha"

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d in @("C:\TEMP\draglint_context_callers_scoped_$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
