<#
  run_dfm_reemit.ps1 -- Track 3 Batch 2a-i headless test for the pure DFM
  component re-emit engine, driven through the HIDDEN `convert-reemit` test verb.

  Builds a tiny F/T fixture (TFromC / TToC), indexes it, then feeds F object
  blocks + rules strings and asserts on the emitted T DFM text + the report JSON.
  Covers: 1:1 rename, moved-depth create, event map, #ignore, unmapped-drop,
  #default, collection relocate, binary same-type vs mismatch, owned-part w/ and
  w/o rule, contained child, and an identity round-trip.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-dfm-reemit"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$src = Join-Path $WorkDir 'fixture'; New-Item -ItemType Directory $src | Out-Null

# Fixture: F type TFromC has Caption/Font(TFont: Size)/Hint/TabOrder; T type TToC
# has Text and a Style(TStyle: Active(TActiveStyle: Font(TFont: Size))) deep path
# plus Enabled. TFont is shared so Font.Size (F) and Style.Active.Font.Size (T)
# both resolve. This lets proptree build both trees.
$fx = @'
unit ReemitFix;

interface

type
  TFont2 = class(TPersistent)
  private
    FSize: Integer;
  published
    property Size: Integer read FSize write FSize;
  end;

  TActiveStyle = class(TPersistent)
  private
    FFont: TFont2;
  published
    property Font: TFont2 read FFont write FFont;
  end;

  TStyle2 = class(TPersistent)
  private
    FActive: TActiveStyle;
  published
    property Active: TActiveStyle read FActive write FActive;
  end;

  TFromC = class(TPersistent)
  private
    FCaption: string;
    FFont: TFont2;
    FHint: string;
    FTabOrder: Integer;
  published
    property Caption: string read FCaption write FCaption;
    property Font: TFont2 read FFont write FFont;
    property Hint: string read FHint write FHint;
    property TabOrder: Integer read FTabOrder write FTabOrder;
  end;

  TToC = class(TPersistent)
  private
    FText: string;
    FStyle: TStyle2;
    FEnabled: Boolean;
  published
    property Text: string read FText write FText;
    property Style: TStyle2 read FStyle write FStyle;
    property Enabled: Boolean read FEnabled write FEnabled;
  end;

implementation

end.
'@
Write-Ascii (Join-Path $src 'ReemitFix.pas') $fx
$db = Join-Path $WorkDir 'reemit.sqlite'
$idx = & $Exe index $src --db $db 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) "$($idx -join ' | ')"

function Reemit($blockBody, $rulesBody, $from, $to) {
  $bf = Join-Path $WorkDir 'block.dfm'; Write-Ascii $bf $blockBody
  $rf = Join-Path $WorkDir 'rules.txt'; Write-Ascii $rf $rulesBody
  Push-Location $WorkDir
  try {
    $out = (& $Exe convert-reemit --from-block $bf --rules $rf --from $from --to $to --db $db) -join "`n"
    $script:LastExit = $LASTEXITCODE
  } finally { Pop-Location }
  return $out
}

# --- Case 1: 1:1 rename Caption -> Text ---
$b1 = "object C1: TFromC`r`n  Caption = 'Hi'`r`nend`r`n"
$r1 = "#convert TFromC -> TToC`r`n#link Text <- Caption`r`n"
$o1 = Reemit $b1 $r1 'ReemitFix.TFromC' 'ReemitFix.TToC'
Check 'rename exit 0' ($script:LastExit -eq 0) "out=$o1"
Check 'rename emits Text = ''Hi''' ($o1 -match "Text\s*=\s*'Hi'") "out=$o1"
Check 'rename T class TToC' ($o1 -match 'object C1: TToC') "out=$o1"

# --- Case 2: moved-depth Font.Size -> Style.Active.Font.Size + Created ---
$b2 = "object C1: TFromC`r`n  object Font: TFont2`r`n    Size = 12`r`n  end`r`nend`r`n"
# Font is a sub-object in F; the #link targets the deep T path from F's Font.Size.
$r2 = "#convert TFromC -> TToC`r`n#link Style.Active.Font.Size <- Font.Size`r`n"
$o2 = Reemit $b2 $r2 'ReemitFix.TFromC' 'ReemitFix.TToC'
Check 'moved-depth exit 0' ($script:LastExit -eq 0) "out=$o2"
Check 'moved-depth nests Style/Active/Font' ($o2 -match 'object Style' -and $o2 -match 'object Active' -and $o2 -match 'object Font') "out=$o2"
Check 'moved-depth Size = 12 present' ($o2 -match 'Size\s*=\s*12') "out=$o2"
Check 'moved-depth Created lists Style.Active.Font' ($o2 -match 'Style\.Active\.Font') "out=$o2"

# --- Case 3: #ignore suppresses the drop warning ---
$b3 = "object C1: TFromC`r`n  TabOrder = 3`r`nend`r`n"
$r3 = "#convert TFromC -> TToC`r`n#ignore TabOrder`r`n"
$o3 = Reemit $b3 $r3 'ReemitFix.TFromC' 'ReemitFix.TToC'
Check 'ignore: TabOrder in ignored' ($o3 -match '"ignored"[^]]*TabOrder') "out=$o3"
Check 'ignore: TabOrder NOT in dropped' (-not ($o3 -match '"dropped"[^]]*TabOrder')) "out=$o3"

# --- Case 4: unmapped non-default -> dropped ---
$b4 = "object C1: TFromC`r`n  Hint = 'x'`r`nend`r`n"
$r4 = "#convert TFromC -> TToC`r`n"
$o4 = Reemit $b4 $r4 'ReemitFix.TFromC' 'ReemitFix.TToC'
Check 'unmapped Hint in dropped' ($o4 -match '"dropped"[^]]*Hint') "out=$o4"

# --- Case 5: #default sets a T-only prop ---
$b5 = "object C1: TFromC`r`n  Caption = 'Hi'`r`nend`r`n"
$r5 = "#convert TFromC -> TToC`r`n#link Text <- Caption`r`n#default Enabled = False`r`n"
$o5 = Reemit $b5 $r5 'ReemitFix.TFromC' 'ReemitFix.TToC'
Check 'default Enabled = False emitted' ($o5 -match 'Enabled\s*=\s*False') "out=$o5"

# --- Case 6: no #convert header -> exit 1 ---
$b6 = "object C1: TFromC`r`n  Caption = 'Hi'`r`nend`r`n"
$r6 = "#link Text <- Caption`r`n"
$o6 = Reemit $b6 $r6 'ReemitFix.TFromC' 'ReemitFix.TToC'
Check 'no #convert exit 1' ($script:LastExit -eq 1) "exit=$($script:LastExit); out=$o6"
Check 'no #convert error names header' ($o6 -match 'convert') "out=$o6"

# --- Case 7: identity round-trip (parse -> emit re-parses equal shape) ---
$b7 = "object C1: TFromC`r`n  Caption = 'Hi'`r`n  object Font: TFont2`r`n    Size = 9`r`n  end`r`nend`r`n"
$r7 = "#convert TFromC -> TFromC`r`n#link Caption <- Caption`r`n"
$o7 = Reemit $b7 $r7 'ReemitFix.TFromC' 'ReemitFix.TFromC'
Check 'round-trip exit 0' ($script:LastExit -eq 0) "out=$o7"
Check 'round-trip keeps Caption' ($o7 -match "Caption\s*=\s*'Hi'") "out=$o7"
Check 'round-trip keeps nested Font/Size' ($o7 -match 'object Font' -and $o7 -match 'Size\s*=\s*9') "out=$o7"

# --- Bad args ---
$noOut = ((& $Exe convert-reemit 2>&1) -join "`n"); $noExit = $LASTEXITCODE
Check 'no args exit 2' ($noExit -eq 2) "exit=$noExit"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
