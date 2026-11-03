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
    class procedure Build(N: Integer);
  end;

  TBeta = class(TObject)
  public
    constructor Create;
    class procedure Build(N: Integer);
    procedure Go;
  end;

procedure Go;

implementation

constructor TAlpha.Create;
begin
  inherited Create;
end;

procedure TAlpha.Run;
begin
end;

class procedure TAlpha.Build(N: Integer);
begin
end;

class procedure TBeta.Build(N: Integer);
begin
end;

procedure TBeta.Go;
begin
end;

procedure Go;
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
  TAlpha.Build(1); { ALPHA_BUILD_SITE }
  TBeta.Build(2); { BETA_BUILD_SITE }
  Go; { GO_SITE }
  uA.Go; { GO_QUAL_SITE }
  S.Go; { GO_VALUE_SITE }
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
$build = CallersOf (Bundle 'modify uA.TAlpha.Build')
$go    = CallersOf (Bundle 'modify uA.Go')

# ---- POSITIVE CONTROLS -------------------------------------------------------
# Without P1 an empty Callers section would pass T1/T2 vacuously.
Check 'P1 POSITIVE CONTROL TAlpha.Create lists its real call site (uC.pas:18)' `
      ($alpha -match 'uC\.pas:18:') "callers section: $alpha"
Check 'P2 POSITIVE CONTROL a non-constructor member keeps its variable-receiver caller (A.Run, uC.pas:21)' `
      ($run -match 'uC\.pas:21:') "callers section: $run"
Check 'P3 POSITIVE CONTROL a class method lists its own qualified call site (TAlpha.Build(1), uC.pas:22)' `
      ($build -match 'uC\.pas:22:') "callers section: $build"

# ---- the defect ---------------------------------------------------------------
Check 'T1 a Create the resolver bound to ANOTHER type (TBeta.Create, uC.pas:19) is not listed' `
      (-not ($alpha -match 'uC\.pas:19:')) "callers section: $alpha"
Check 'T2 an unresolved Create on a FOREIGN type (TStringList.Create, uC.pas:20) is not listed' `
      (-not ($alpha -match 'uC\.pas:20:')) "callers section: $alpha"

# 1.42 GAP-CALLERS (gaps.log rows 2026-08-10 TQueryRule.Create, 2026-09-29 TManifestIO.Load,
# 2026-10-19 TRoutineVarTable.Build, 2026-10-23 TDragLintDockFrame.Create): a call written
# `TBeta.Build(2)` stores TWO refs on the same token -- the `call` (bound to TBeta.Build) and a
# `member-access` twin the resolver leaves NULL. Rule 1 dropped the call; the unbound twin
# survived and was listed as a [name-only] caller of TAlpha.Build.
Check 'T3 the unbound member-access twin of a call bound to ANOTHER method (TBeta.Build(2), uC.pas:23) is not listed' `
      (-not ($build -match 'uC\.pas:23:')) "callers section: $build"
# T4 (1.42 GAP-CALLERS, gaps.log 2026-09-29 `DRagLint.CLI.Run listed as its own caller`):
# a UNIT-LEVEL routine cannot be reached through a VALUE receiver. `S.Go` (S: TStringList,
# a type with no Go -- the call stays unbound) was listed as a [name-only] caller of uA.Go.
Check 'P4 POSITIVE CONTROL the unit-level Go keeps its bare and unit-qualified sites (uC.pas:24, uC.pas:25)' `
      (($go -match 'uC\.pas:24:') -and ($go -match 'uC\.pas:25:')) "callers section: $go"
Check 'T4 an unbound value-receiver call (S.Go, uC.pas:26) is not a caller of the unit-level uA.Go' `
      (-not ($go -match 'uC\.pas:26:')) "callers section: $go"

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d in @("C:\TEMP\draglint_context_callers_scoped_$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
