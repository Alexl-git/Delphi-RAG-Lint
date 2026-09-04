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
# Also (Task 9): TFromC.Fields (a class-typed collection-ish stand-in) for the
# collection-relocate case (o8, relocated to TToC.Data.Fields), TFromC.Layout /
# TToC.Layout SAME type TLayout2 for the binary same-type-copy case (o9). TData2
# is a plain TPersistent-derived holder so proptree can resolve Data.Fields.
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

  TColl2 = class(TPersistent)
  private
    FCount: Integer;
  published
    property Count: Integer read FCount write FCount;
  end;

  TLayout2 = class(TPersistent)
  private
    FCount: Integer;
  published
    property Count: Integer read FCount write FCount;
  end;

  TData2 = class(TPersistent)
  private
    FFields: TColl2;
  published
    property Fields: TColl2 read FFields write FFields;
  end;

  TOldCol2 = class(TPersistent)
  private
    FWidth: Integer;
  published
    property Width: Integer read FWidth write FWidth;
  end;

  TNewCol2 = class(TPersistent)
  private
    FWidth: Integer;
  published
    property Width: Integer read FWidth write FWidth;
  end;

  TFromC = class(TPersistent)
  private
    FCaption: string;
    FFont: TFont2;
    FHint: string;
    FTabOrder: Integer;
    FFields: TColl2;
    FLayout: TLayout2;
  published
    property Caption: string read FCaption write FCaption;
    property Font: TFont2 read FFont write FFont;
    property Hint: string read FHint write FHint;
    property TabOrder: Integer read FTabOrder write FTabOrder;
    property Fields: TColl2 read FFields write FFields;
    property Layout: TLayout2 read FLayout write FLayout;
  end;

  TToC = class(TPersistent)
  private
    FText: string;
    FStyle: TStyle2;
    FEnabled: Boolean;
    FData: TData2;
    FLayout: TLayout2;
  published
    property Text: string read FText write FText;
    property Style: TStyle2 read FStyle write FStyle;
    property Enabled: Boolean read FEnabled write FEnabled;
    property Data: TData2 read FData write FData;
    property Layout: TLayout2 read FLayout write FLayout;
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

# --- Case 8: collection relocate Fields -> Data.Fields, items unchanged + Note ---
$b8 = "object C1: TFromC`r`n  Fields = <`r`n    item`r`n      Name = 'A'`r`n    end>`r`nend`r`n"
$r8 = "#convert TFromC -> TToC`r`n#link Data.Fields <- Fields`r`n"
$o8 = Reemit $b8 $r8 'ReemitFix.TFromC' 'ReemitFix.TToC'
Check 'collection relocate exit 0' ($script:LastExit -eq 0) "out=$o8"
Check 'collection items unchanged (Name A)' ($o8 -match "Name\s*=\s*'A'") "out=$o8"
Check 'collection relocate Note recorded' ($o8 -match '"notes"[^]]*relocated') "out=$o8"

# --- Case 9: binary same-type copied verbatim ---
$b9 = "object C1: TFromC`r`n  Layout = {0A0B0C}`r`nend`r`n"
$r9 = "#convert TFromC -> TToC`r`n#link Layout <- Layout`r`n"
$o9 = Reemit $b9 $r9 'ReemitFix.TFromC' 'ReemitFix.TToC'
Check 'binary same-type copied' ($o9 -match 'Layout\s*=\s*\{0A0B0C\}') "out=$o9"

# --- Case 10: owned part w/o rule -> in ownedParts (via #note owned: marker) ---
$b10 = "object C1: TFromC`r`n  object Col1: TOldCol`r`n    Width = 5`r`n  end`r`nend`r`n"
$r10 = "#convert TFromC -> TToC`r`n#note owned:TOldCol`r`n"
$o10 = Reemit $b10 $r10 'ReemitFix.TFromC' 'ReemitFix.TToC'
Check 'owned-part-no-rule in ownedParts' ($o10 -match '"ownedParts"[^]]*TOldCol') "out=$o10"

# --- Case 11: contained child (no rule, no owned note) -> left alone, NOT flagged ---
$b11 = "object C1: TFromC`r`n  object Btn1: TButton`r`n    Caption = 'OK'`r`n  end`r`nend`r`n"
$r11 = "#convert TFromC -> TToC`r`n"
$o11 = Reemit $b11 $r11 'ReemitFix.TFromC' 'ReemitFix.TToC'
Check 'contained child kept' ($o11 -match 'object Btn1: TButton') "out=$o11"
Check 'contained child NOT in ownedParts' (-not ($o11 -match '"ownedParts"[^]]*TButton')) "out=$o11"

# --- Case 12: owned part WITH its own #convert rule -> recurses and picks ITS
# OWN target class, not the first/parent #convert's target (I-1 regression). Two
# #convert rules are present: the parent TFromC -> TToC, and the owned part's OWN
# TOldCol2 -> TNewCol2. Before the fix, HandleNested's recursive ReemitComponent
# call resolved ToType via "first #convert rule" == TToC (the PARENT's target),
# so the part was mis-emitted as TToC instead of TNewCol2. ---
$b12 = "object C1: TFromC`r`n  object Col1: TOldCol2`r`n    Width = 5`r`n  end`r`nend`r`n"
$r12 = "#convert TFromC -> TToC`r`n#convert TOldCol2 -> TNewCol2`r`n#link Width <- Width`r`n"
$o12 = Reemit $b12 $r12 'ReemitFix.TFromC' 'ReemitFix.TToC'
Check 'owned-part-with-rule exit 0' ($script:LastExit -eq 0) "out=$o12"
Check 'owned-part-with-rule emits OWN target TNewCol2' ($o12 -match 'object Col1: TNewCol2') "out=$o12"
Check 'owned-part-with-rule does NOT emit parent target TToC for the part' (-not ($o12 -match 'object Col1: TToC')) "out=$o12"
Check 'owned-part-with-rule does NOT leave unconverted TOldCol2' (-not ($o12 -match 'object Col1: TOldCol2')) "out=$o12"
Check 'owned-part-with-rule keeps Width = 5' ($o12 -match 'Width\s*=\s*5') "out=$o12"

# --- Cases 13-15: #mapping / #apply -----------------------------------------
# A #mapping is a named conditional value map applied by '#apply'. The three
# cases below are the whole contract: a matching #when, the #else fallback, and
# a value that matches neither.
#
# The mapping pass runs BEFORE the leaf loop. That ordering is load-bearing and
# case 13 is what pins it: if it ran after, RemapLeaf would already have
# recorded Mode as Dropped, and 'no bare Mode =' could not hold.
$rMap = "#mapping ModeMap from U.TMode to U.TDst`r`n" +
        "#mapping ModeMap #when Mode = omB -> Mode2 = nmB`r`n" +
        "#mapping ModeMap #else -> Mode2 = nmDefault`r`n" +
        "#convert TFromC -> TToC`r`n" +
        "#apply ModeMap`r`n"

# 13: the #when matches. The T side gets the mapped value, and the F leaf is
# CONSUMED -- it must not also be re-emitted raw.
$b13 = "object C1: TFromC`r`n  Mode = omB`r`nend`r`n"
$o13 = Reemit $b13 $rMap 'ReemitFix.TFromC' 'ReemitFix.TToC'
Check 'mapping #when exit 0' ($script:LastExit -eq 0) "out=$o13"
Check 'mapping #when emits the mapped value Mode2 = nmB' ($o13 -match 'Mode2\s*=\s*nmB') "out=$o13"
Check 'mapping #when consumes the F leaf (no bare Mode =)' `
  (-not ($o13 -match '(?m)^\s*Mode\s*=')) "out=$o13"
Check 'mapping #when reports nothing NOT-applied' ($o13 -match '"notApplied":\[\]') "out=$o13"

# 14: no #when matches, but the source leaf is PRESENT -- the #else fires.
$b14 = "object C1: TFromC`r`n  Mode = omA`r`nend`r`n"
$o14 = Reemit $b14 $rMap 'ReemitFix.TFromC' 'ReemitFix.TToC'
Check 'mapping #else exit 0' ($script:LastExit -eq 0) "out=$o14"
Check 'mapping #else emits the fallback value Mode2 = nmDefault' `
  ($o14 -match 'Mode2\s*=\s*nmDefault') "out=$o14"
Check 'mapping #else reports nothing NOT-applied' ($o14 -match '"notApplied":\[\]') "out=$o14"

# 15: no #when matches and there is NO #else -- REMAINDER. notApplied must name
# the mapping, the #apply line, the path and the unmatched value, because that
# is exactly what a human needs to fix the rule book.
$rNoElse = "#mapping ModeMap from U.TMode to U.TDst`r`n" +
           "#mapping ModeMap #when Mode = omB -> Mode2 = nmB`r`n" +
           "#convert TFromC -> TToC`r`n" +
           "#apply ModeMap`r`n"
$b15 = "object C1: TFromC`r`n  Mode = omZ`r`nend`r`n"
$o15 = Reemit $b15 $rNoElse 'ReemitFix.TFromC' 'ReemitFix.TToC'
Check 'mapping unmatched exit 0' ($script:LastExit -eq 0) "out=$o15"
Check 'mapping unmatched records notApplied naming the mapping' `
  ($o15 -match '"mapName"\s*:\s*"ModeMap"') "out=$o15"
Check 'mapping unmatched notApplied carries the unmatched value' `
  ($o15 -match '"value"\s*:\s*"omZ"') "out=$o15"
Check 'mapping unmatched notApplied carries the source path' `
  ($o15 -match '"path"\s*:\s*"Mode"') "out=$o15"
Check 'mapping unmatched notApplied carries the #apply rule line (4)' `
  ($o15 -match '"ruleLine"\s*:\s*4') "out=$o15"
Check 'mapping unmatched emits NO invented Mode2' (-not ($o15 -match 'Mode2')) "out=$o15"

# 16: an #apply whose source path is absent from THIS block is informational,
# not remainder -- and the #else must NOT fire, or it would invent a T value
# from an F property the form never set.
$b16 = "object C1: TFromC`r`n  Caption = 'x'`r`nend`r`n"
$o16 = Reemit $b16 $rMap 'ReemitFix.TFromC' 'ReemitFix.TToC'
Check 'mapping absent-source exit 0' ($script:LastExit -eq 0) "out=$o16"
Check 'mapping absent-source records a mappingNote' `
  ($o16 -match '"mappingNotes"\s*:\s*\[\s*"[^"]*ModeMap') "out=$o16"
Check 'mapping absent-source reports nothing NOT-applied' ($o16 -match '"notApplied":\[\]') "out=$o16"
Check 'mapping absent-source does NOT fire the #else' (-not ($o16 -match 'nmDefault')) "out=$o16"

# --- Bad args ---
$noOut = ((& $Exe convert-reemit 2>&1) -join "`n"); $noExit = $LASTEXITCODE
Check 'no args exit 2' ($noExit -eq 2) "exit=$noExit"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
