<#
  run_doc_glued_summary_owner.ps1 --
  A `///` doc block whose first line is GLUED onto the end of the previous
  declaration's line belongs to the NEXT declaration, and the previous
  declaration keeps its own block.

  THE DEFECT (stats\draglint-gaps.log 2026-10-30, GAP-CONTEXT).
    context --task "modify TSQLiteSymbolStore.ResolveDispatch"
  showed WriteExternalStores' summary as ResolveDispatch's ## Doc. The source:
      /// <summary>WriteExternalStores ...</summary>
      procedure WriteExternalStores(...);      /// <summary>Implements ResolveDispatch ...
      /// ... </summary>
      procedure ResolveDispatch(...);
  TDocCommentScanner folded every run of `///` lines on consecutive lines into
  ONE region, the trailing `///` included, so the whole run (both blocks) was
  attributed to ResolveDispatch -- whose parse takes the FIRST <summary> -- and
  WriteExternalStores (declared INSIDE the run) got no doc at all.

  THE FIX. A doc-kind line comment that follows code on its own line starts a
  NEW region; it is never folded into the run above it.

  CONTROLS:
    * Gamma, documented the ordinary way, keeps its doc (the fix did not drop
      ordinary blocks) -- and is RIGHT on the base build too, so the checks can
      tell a right summary from a wrong one
    * a COLUMN of trailing one-line docs (K_ONE = 1; /// a  /  K_TWO = 2; /// b)
      does not shift: K_TWO never gets K_ONE's doc (a split there would hand
      each line's doc to the declaration below it -- measured on
      DRagLint.Format.Yadf FMT_* during the first cut of this fix)
    * an invented summary text is absent (the match is not vacuous)

  Run from any CWD, pwsh 7. Builds its own fixture; touches no shared index.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_doc_glued_summary_$PID"
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

Write-Ascii (Join-Path $src 'uGlue.pas') @"
unit uGlue;

interface

type
  TStore = class
  public
    /// <summary>AlphaOwnDoc text.</summary>
    procedure Alpha;      /// <summary>BetaOwnDoc text,
    /// continued here.</summary>
    /// <param name="X">The x.</param>
    procedure Beta(X: Integer);
    /// <summary>GammaOwnDoc text.</summary>
    procedure Gamma;
  end;

const
  K_ONE = 1; /// <summary>KOneDoc text.</summary>
  K_TWO = 2; /// <summary>KTwoDoc text.</summary>

implementation

procedure TStore.Alpha;
begin
end;

procedure TStore.Beta(X: Integer);
begin
end;

procedure TStore.Gamma;
begin
end;

end.
"@

$db = Join-Path $WorkDir 'fx.sqlite'
& $exePath index $src --db $db 2>&1 | Out-Null
Check 'V the fixture index was built' (Test-Path $db) $db

# The `## Doc` section of a context bundle (empty when the symbol has no doc).
function DocOf([string]$QName) {
  $out = ((& $exePath context --task "modify $QName" --db $db --format markdown 2>$null) -join "`n")
  if ($out -match '(?s)## Doc\n(.*?)(\n## |\z)') { return $Matches[1] }
  return ''
}

$a = DocOf 'uGlue.TStore.Alpha'
$b = DocOf 'uGlue.TStore.Beta'
$g = DocOf 'uGlue.TStore.Gamma'

Check 'T1 Alpha (the declaration the trailing /// is glued onto) keeps its OWN doc' ($a -match 'AlphaOwnDoc') ($a -replace "`n", ' / ')
Check 'T2 Beta gets the glued block (BetaOwnDoc)'                               ($b -match 'BetaOwnDoc')  ($b -replace "`n", ' / ')
Check 'T3 Beta does NOT carry Alpha''s summary'                                 (-not ($b -match 'AlphaOwnDoc')) ($b -replace "`n", ' / ')
Check 'C1 CONTROL Gamma, documented the ordinary way, keeps its doc'           ($g -match 'GammaOwnDoc') ($g -replace "`n", ' / ')
$k2 = DocOf 'uGlue.K_TWO'
Check 'C3 CONTROL a trailing one-line doc column does not shift onto the next line' (-not ($k2 -match 'KOneDoc')) ($k2 -replace "`n", ' / ')
Check 'C2 CONTROL an invented summary is absent (the match is not vacuous)'    (-not ($b -match 'ZzNotADoc')) ''

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_doc_glued_summary_$PID")) { if (Test-Path -LiteralPath $d23) { [IO.Directory]::Delete($d23, $true) } }
}
