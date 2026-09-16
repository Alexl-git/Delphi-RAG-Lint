<#
  run_hover_interface_implementors.ps1 --
  Hovering an INTERFACE must name the types that implement it.

  THE ASK (owner, 2026-09-15). Hovering `var ABC: ImcSTATIONS;` should answer
  `TmcSTATIONS`. The same fact belongs in the autodocumentation, so it is
  readable without a tool.

  THE STATE IT REPLACES (measured 2026-09-16). `hover --qname
  DRagLint.Core.Interfaces.ISymbolStore --format md` returned Used-by and
  Used-in-units and NOTHING about TSQLiteSymbolStore, while `query descendants
  --of ISymbolStore` answered `TSQLiteSymbolStore` instantly. The data was
  already indexed; no surface carried it. Hover on the CLASS did not carry the
  forward edge either -- `Implements:` is a Phase-1.x doc-only fact, and
  TDocRegions.FormatPhase2FactLines' own header says the non-Phase-2 facts are
  "deliberately out of scope for this helper and for hover."

  WHY THE FACT, NOT THE RENDERER. `document`'s managed block, `hover`'s markdown
  and the LSP all build from ONE TDocFactsBuilder.Build result and format through
  ONE helper -- the v(ADP2 T9) doc/hover consistency lock. Adding the fact once
  is what makes T5 (the doc surface) true by construction rather than by a second
  implementation that can drift.

  THE TWO KINDS ARE LABELLED SEPARATELY, and that is a decision, not a detail.
  A descendant of an interface is either a CLASS that implements it or an
  INTERFACE that extends it. Merging them into one list would report
  `ISuperWorker` as though it were an implementation you could instantiate.

  THE SHIPPING PRIMITIVE CANNOT ANSWER THE SECOND HALF, and that is why this
  guard exists rather than a one-line renderer change:
  TSQLiteSymbolStore.FindDescendantNames filters `s.kind IN ('class','type')`
  and emits only `kind = 'class'` (SQLite.pas:11651-11661), DELIBERATELY -- it
  backs the conversion editor's class pickers, which must not be offered an
  interface. Measured consequence: `query descendants --of IFIBObject` on
  library-Win64 returns `(none)` while the index holds IFIBConnect,
  IFIBSQLObject and IFIBTransaction. That verb's contract is not changed here;
  the new fact uses a kind-aware lookup of its own. Logged as `wrong` in
  stats\draglint-gaps.log, 2026-09-16.

  Run from any CWD, pwsh 7. Builds its own fixture; touches no shared index.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_hover_implementors"
)
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function Write-Ascii($p,$t){ [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }

# Mirrors DRagLint.Doc.Facts.OVERRIDDENBY_CAP. ICrowd below declares CAP+1
# implementors so the truncation assertion cannot pass by accident.
$CAP = 6

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Path $src -Force | Out-Null

$crowdDecls = (1..($CAP + 1) | ForEach-Object { "    TCrowd$_ = class(TInterfacedObject, ICrowd)`r`n    public`r`n      procedure Go;`r`n    end;" }) -join "`r`n"
$crowdImpls = (1..($CAP + 1) | ForEach-Object { "procedure TCrowd$_.Go;`r`nbegin`r`nend;`r`n" }) -join "`r`n"

Write-Ascii (Join-Path $src 'uFix.pas') @"
unit uFix;

interface

type
  IWorker = interface
    ['{11111111-1111-1111-1111-111111111111}']
    function Work: Integer;
  end;

  ISuperWorker = interface(IWorker)
    ['{22222222-2222-2222-2222-222222222222}']
    function Extra: Integer;
  end;

  ILonely = interface
    ['{33333333-3333-3333-3333-333333333333}']
    procedure NobodyImplementsThis;
  end;

  ICrowd = interface
    ['{44444444-4444-4444-4444-444444444444}']
    procedure Go;
  end;

  TWorkerAlpha = class(TInterfacedObject, IWorker)
  public
    function Work: Integer;
  end;

  TWorkerBeta = class(TInterfacedObject, IWorker)
  public
    function Work: Integer;
  end;

$crowdDecls

implementation

function TWorkerAlpha.Work: Integer;
begin
  Result := 1;
end;

function TWorkerBeta.Work: Integer;
begin
  Result := 2;
end;

$crowdImpls

end.
"@

$db = Join-Path $WorkDir 'fx.sqlite'
& $exePath index $src --db $db 2>&1 | Out-Null
Check 'V the fixture index was built' (Test-Path $db) $db

# The call operator, NOT Start-Process -ArgumentList: Start-Process does not
# quote arguments containing spaces, and a mangled argument produces output that
# looks exactly like the missing-fact this guard hunts.
function Hover([string]$QName, [string]$Fmt = 'md') {
  return ((& $exePath hover --qname $QName --db $db --format $Fmt 2>$null) -join "`r`n")
}

# ---- V2 POSITIVE CONTROL: the data really is in the fixture index -----------
# Without this, every assertion below could fail because the FIXTURE is wrong
# rather than because the FEATURE is missing -- the failure mode that cost a
# session on the doc-facts fixture.
$desc = ((& $exePath query descendants --of 'IWorker' --db $db 2>$null) -join ' ')
Check 'V2 POSITIVE CONTROL the index knows TWorkerAlpha descends from IWorker' `
      ($desc -match 'TWorkerAlpha') `
      "query descendants --of IWorker returned: '$desc' -- the fixture, not the feature, is broken"

$hWorker = Hover 'uFix.IWorker'
$hLonely = Hover 'uFix.ILonely'
$hCrowd  = Hover 'uFix.ICrowd'

# ---- P1 POSITIVE CONTROL: hover works at all on this fixture ----------------
Check 'P1 POSITIVE CONTROL hover resolves the interface symbol' `
      ($hWorker -match 'uFix\.IWorker') `
      "hover returned $($hWorker.Length) bytes and does not even name the symbol"

# ---- T1/T2: the feature ----------------------------------------------------
Check 'T1 hover on an interface names its IMPLEMENTING CLASSES' `
      (($hWorker -match 'TWorkerAlpha') -and ($hWorker -match 'TWorkerBeta')) `
      "hover on IWorker is $($hWorker.Length) bytes and names neither implementor"

Check 'T2 the implementors appear under an Implemented-by label' `
      ($hWorker -match '(?i)implemented by:') `
      'the names appear but not under a label, so a reader cannot tell what the list means'

Check 'T3 a DERIVED INTERFACE is reported separately, not as an implementation' `
      (($hWorker -match '(?i)extended by:') -and ($hWorker -match 'ISuperWorker')) `
      'ISuperWorker extends IWorker; merging it into "Implemented by" claims an instantiable type'

Check 'T3b the derived interface is NOT listed as an implementing class' `
      (-not ($hWorker -match '(?i)implemented by:[^\r\n]*ISuperWorker')) `
      'ISuperWorker is on the Implemented-by line -- the two kinds have been merged'

# ---- T4 ABSENCE CONTROL ----------------------------------------------------
# Mandatory per the plan: without it the feature passes against a build that
# lists something for every interface.
Check 'T4 ABSENCE CONTROL an interface with NO implementor does not fabricate one' `
      (-not ($hLonely -match '(?i)implemented by:')) `
      'ILonely has no implementor, yet hover emitted an Implemented-by line'

# ---- T5 CAP CONTROL --------------------------------------------------------
$crowdLine = ([regex]::Match($hCrowd, '(?im)^.*implemented by:.*$')).Value
Check 'T5 CAP CONTROL more implementors than the cap reports the truncation' `
      ($crowdLine -match '\(\+\d+ more\)') `
      "ICrowd has $($CAP + 1) implementors and the line does not say it was shortened: '$crowdLine'"

Check 'T5b CAP CONTROL the shown list really is capped' `
      ((([regex]::Matches($crowdLine, 'TCrowd\d')).Count) -le $CAP) `
      "the line shows more than OVERRIDDENBY_CAP ($CAP) names: '$crowdLine'"

# ---- T6 the doc/hover consistency lock -------------------------------------
# hover --format json is what the IDE's popup consumes. If md and json disagree,
# the fact was added to a renderer instead of to TDocFacts, and the doc surface
# will drift from both.
$jWorker = Hover 'uFix.IWorker' 'json'
Check 'T6 hover --format json carries the same fact as --format md' `
      (($jWorker -match 'TWorkerAlpha') -and ($jWorker -match '(?i)implemented by')) `
      'json omits what md shows -- the fact lives in a renderer, not in TDocFacts'

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
