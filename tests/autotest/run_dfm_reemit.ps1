<#
  run_dfm_reemit.ps1 -- Track 3 Batch 2a-i headless test for the pure DFM
  component re-emit engine, driven through the HIDDEN `convert-reemit` test verb.

  Builds a tiny F/T fixture (TFromC / TToC), indexes it, then feeds F object
  blocks + rules strings and asserts on the emitted T DFM text + the report JSON.
  Covers: 1:1 rename, moved-depth create, event map, #ignore, unmapped-drop,
  #default, collection relocate, binary same-type vs mismatch, owned-part w/ and
  w/o rule, contained child, an identity round-trip, #mapping/#apply, and
  (cases 17-19) #default as a FALLBACK that never clobbers a carried value.
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

  { D2/D3/D4: a pair whose published properties carry `default` clauses, which
    is what makes a .dfm SPARSE. Chosen so the three cases are distinguishable:
      Mode  default dmA  vs  Mode2 default dmC  -- F's default is NOT T's, so
                                                   dropping it CHANGES the value
      Same  default True vs  Same2 default True -- equal, so only an EXPLICIT
                                                   emission proves D3
      Plain no clause    vs  Plain2 no clause   -- always streamed, so absence
                                                   is genuinely UNKNOWN }
  TDefMode = (dmA, dmB, dmC);
  TOptD    = (odA, odB, odC);
  TOptsD   = set of TOptD;

  TFromD = class(TPersistent)
  private
    FMode : TDefMode;
    FSame : Boolean;
    FPlain: Integer;
    FAnchors: TOptsD;
    FGuarded: Integer;
    FVisible: Boolean;
  published
    property Mode : TDefMode read FMode  write FMode  default dmA;
    property Same : Boolean  read FSame  write FSame  default True;
    property Plain: Integer  read FPlain write FPlain;
    { a SET default -- contains a space, so a token-to-first-space reader
      truncates it to `[odA,` and emits a malformed .dfm }
    property Anchors: TOptsD read FAnchors write FAnchors default [odA, odB];
    { a CONDITIONALLY STORED property -- omitted regardless of value, so its
      absence carries no information and there is no usable default }
    property Guarded: Integer read FGuarded write FGuarded stored IsGuardedStored default 7;
    { shares a name with TOldColD.Visible below, and DISAGREES on the default.
      That is what makes the owned-part case a wrong-VALUE test, not just a
      wrong-place test. }
    property Visible: Boolean read FVisible write FVisible default False;
  end;

  TToD = class(TPersistent)
  private
    FMode2 : TDefMode;
    FSame2 : Boolean;
    FPlain2: Integer;
    FAnchors2: TOptsD;
    FGuarded2: Integer;
  published
    property Mode2 : TDefMode read FMode2  write FMode2  default dmC;
    property Same2 : Boolean  read FSame2  write FSame2  default True;
    property Plain2: Integer  read FPlain2 write FPlain2;
    property Anchors2: TOptsD  read FAnchors2 write FAnchors2 default [odC];
    property Guarded2: Integer read FGuarded2 write FGuarded2 default 1;
    { NOTE: TToD deliberately has NO `Shown`. A #link naming Shown belongs to
      the owned part's #convert, and applying it here must emit nothing. }
  end;

  { An owned part with its OWN #convert. Visible/Shown deliberately default
    True, against TFromD.Visible's False, so resolving the part's #link from
    the PARENT's tree produces a visibly wrong value rather than a coincidence. }
  TOldColD = class(TPersistent)
  private
    FWidth  : Integer;
    FVisible: Boolean;
  published
    property Width  : Integer read FWidth   write FWidth;
    property Visible: Boolean read FVisible write FVisible default True;
  end;

  TNewColD = class(TPersistent)
  private
    FWidth: Integer;
    FShown: Boolean;
  published
    property Width: Integer read FWidth write FWidth;
    property Shown: Boolean read FShown write FShown default True;
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

# --- Cases 17-19: #default must NOT clobber a value a rule already carried ---
# D0. Both the rkDefault doc ("set a target property to a value WHEN NO SOURCE
# MAPS") and step 5's own comment ("T-only props") say #default is a FALLBACK.
# The code tested neither: it looped every rkDefault and called PlaceAtPath
# unconditionally, AFTER the step-4 leaf loop had written whatever #link and
# #mapping carried across. Last writer won, and #default was always last -- so
# a rule book stating both `#link X <- X` and `#default X = ...` (the natural
# way to write "use the source value, or Zzz if there isn't one") silently
# discarded the form's real value, exit 0, no warning.
#
# The superseded #default is REPORTED, not skipped in silence: a rule the
# operator wrote that did nothing should say so, on the same reasoning that
# produced notApplied for #mapping.
#
# Case 18 is the POSITIVE CONTROL. Without it, "the source wins" is equally
# satisfied by #default being broken outright.

# 17: source PRESENT -> the SOURCE value wins, and the #default is reported.
$b17 = "object C1: TFromC`r`n  Caption = 'Hi'`r`nend`r`n"
$r17 = "#convert TFromC -> TToC`r`n#link Text <- Caption`r`n#default Text = 'Zzz'`r`n"
$o17 = Reemit $b17 $r17 'ReemitFix.TFromC' 'ReemitFix.TToC'
Check 'default-superseded exit 0' ($script:LastExit -eq 0) "out=$o17"
$j17 = $o17 | ConvertFrom-Json
Check 'default-superseded keeps the SOURCE value Text = ''Hi''' `
  ($j17.dfm -match "Text\s*=\s*'Hi'") "dfm=$($j17.dfm)"
Check 'default-superseded does NOT write the #default value into the DFM' `
  (-not ($j17.dfm -match 'Zzz')) "dfm=$($j17.dfm)"
# Normalise a MISSING key to an EMPTY array. Two traps here, BOTH hit while
# RED-checking this guard against the unfixed build:
#   * indexing $null throws, and under $ErrorActionPreference='Stop' that aborts
#     the whole runner mid-file while STILL exiting 0 -- a guard that cannot
#     report is worse than one that fails;
#   * @($null).Count is 1, not 0, so a bare @() wrapper made "records exactly
#     one" PASS against a build that recorded nothing at all -- an assertion
#     incapable of failing.
# Where-Object drops the $null, so both the count and the index are honest.
$ds17 = @($j17.report.defaultsSuperseded | Where-Object { $null -ne $_ })
$d17  = if ($ds17.Count -gt 0) { $ds17[0] } else { $null }
Check 'default-superseded records exactly one superseded #default' `
  ($ds17.Count -eq 1) "out=$o17"
Check 'default-superseded names the T path' `
  ($null -ne $d17 -and $d17.path -eq 'Text') "out=$o17"
Check 'default-superseded carries the #default rule line (3)' `
  ($null -ne $d17 -and $d17.ruleLine -eq 3) "out=$o17"
Check 'default-superseded carries the value that WON' `
  ($null -ne $d17 -and $d17.existing -match 'Hi') "out=$o17"
Check 'default-superseded carries the ignored default value' `
  ($null -ne $d17 -and $d17.value -match 'Zzz') "out=$o17"

# 18: POSITIVE CONTROL -- a T-only #default with no rule carrying that path is
# the whole point of #default and must still fire, reporting nothing.
$b18 = "object C1: TFromC`r`n  Caption = 'Hi'`r`nend`r`n"
$r18 = "#convert TFromC -> TToC`r`n#link Text <- Caption`r`n#default Enabled = False`r`n"
$o18 = Reemit $b18 $r18 'ReemitFix.TFromC' 'ReemitFix.TToC'
Check 'T-only #default exit 0' ($script:LastExit -eq 0) "out=$o18"
$j18 = $o18 | ConvertFrom-Json
Check 'T-only #default still fires (Enabled = False)' `
  ($j18.dfm -match 'Enabled\s*=\s*False') "dfm=$($j18.dfm)"
Check 'T-only #default keeps the linked Text = ''Hi''' `
  ($j18.dfm -match "Text\s*=\s*'Hi'") "dfm=$($j18.dfm)"
Check 'T-only #default reports nothing superseded' `
  (@($j18.report.defaultsSuperseded | Where-Object { $null -ne $_ }).Count -eq 0) "out=$o18"

# 19: the #link names a source the block does NOT set, so nothing was carried
# and the #default is the only value there is -- it must fire.
$b19 = "object C1: TFromC`r`n  Hint = 'x'`r`nend`r`n"
$r19 = "#convert TFromC -> TToC`r`n#link Text <- Caption`r`n#default Text = 'Zzz'`r`n"
$o19 = Reemit $b19 $r19 'ReemitFix.TFromC' 'ReemitFix.TToC'
Check 'absent-source #default exit 0' ($script:LastExit -eq 0) "out=$o19"
$j19 = $o19 | ConvertFrom-Json
Check 'absent-source #default fires (Text = ''Zzz'')' `
  ($j19.dfm -match "Text\s*=\s*'Zzz'") "dfm=$($j19.dfm)"
Check 'absent-source #default reports nothing superseded' `
  (@($j19.report.defaultsSuperseded | Where-Object { $null -ne $_ }).Count -eq 0) "out=$o19"

# --- Cases 20-21: the same rule, on a DOTTED path -------------------------
# Cases 17-19 only ever name a top-level leaf, so they never exercise the walk.
# A dotted path is where the read-only half of FindAtPath earns its keep: the
# intermediates Style/Active/Font exist ONLY because the #link created them, and
# a presence test that created its own intermediates (as PlaceAtPath does) would
# report every #default as superseded by the node the test itself just made.
# Case 21 is the control that separates "the walk found the carried value" from
# "the walk always finds something".

# 20: dotted #link carried Size = 12; the dotted #default must not overwrite it.
$b20 = "object C1: TFromC`r`n  object Font: TFont2`r`n    Size = 12`r`n  end`r`nend`r`n"
$r20 = "#convert TFromC -> TToC`r`n#link Style.Active.Font.Size <- Font.Size`r`n#default Style.Active.Font.Size = 99`r`n"
$o20 = Reemit $b20 $r20 'ReemitFix.TFromC' 'ReemitFix.TToC'
Check 'dotted default-superseded exit 0' ($script:LastExit -eq 0) "out=$o20"
$j20 = $o20 | ConvertFrom-Json
$ds20 = @($j20.report.defaultsSuperseded | Where-Object { $null -ne $_ })
$d20  = if ($ds20.Count -gt 0) { $ds20[0] } else { $null }
Check 'dotted: the carried Size = 12 survives' ($j20.dfm -match 'Size\s*=\s*12') "dfm=$($j20.dfm)"
Check 'dotted: the #default 99 is NOT written' (-not ($j20.dfm -match 'Size\s*=\s*99')) "dfm=$($j20.dfm)"
Check 'dotted: exactly one superseded #default' ($ds20.Count -eq 1) "out=$o20"
Check 'dotted: the report names the FULL dotted path' `
  ($null -ne $d20 -and $d20.path -eq 'Style.Active.Font.Size') "out=$o20"
Check 'dotted: the report carries the value that won (12)' `
  ($null -ne $d20 -and $d20.existing -match '12') "out=$o20"

# 21: CONTROL -- the same dotted #default with nothing carrying that path must
# still fire, creating the intermediates itself.
$b21 = "object C1: TFromC`r`nend`r`n"
$r21 = "#convert TFromC -> TToC`r`n#default Style.Active.Font.Size = 99`r`n"
$o21 = Reemit $b21 $r21 'ReemitFix.TFromC' 'ReemitFix.TToC'
Check 'dotted control exit 0' ($script:LastExit -eq 0) "out=$o21"
$j21 = $o21 | ConvertFrom-Json
Check 'dotted control: the #default fires (Size = 99)' `
  ($j21.dfm -match 'Size\s*=\s*99') "dfm=$($j21.dfm)"
Check 'dotted control: the intermediates were created' `
  ($j21.dfm -match 'object Style' -and $j21.dfm -match 'object Active') "dfm=$($j21.dfm)"
Check 'dotted control: nothing reported superseded' `
  (@($j21.report.defaultsSuperseded | Where-Object { $null -ne $_ }).Count -eq 0) "out=$o21"

# --- Cases 22-26: a SPARSE .dfm -- an absent property is an UNREAD value ----
# Delphi omits a published property whose value equals the `default` declared on
# it. So a property missing from a block is not missing INFORMATION; the value
# is in the declaration, and D1 resolved it onto the prop tree. These cases pin
# that the engine now reads it (D2/D4) and writes the target EXPLICITLY (D3).
#
# The trap they exist to prevent: F's default and T's default are different
# values that merely share a property name. Carrying nothing across does not
# "keep the default" -- it silently swaps dmA for dmC.

# 22 (D2): the mapping's #when names a value the block does NOT stream, because
# that IS the property's default. The branch must fire.
$rDef = "#mapping DM from ReemitFix.TDefMode to ReemitFix.TToD`r`n" +
        "#mapping DM #when Mode = dmA -> Mode2 = dmB`r`n" +
        "#convert TFromD -> TToD`r`n" +
        "#apply DM`r`n"
$b22 = "object C1: TFromD`r`nend`r`n"
$o22 = Reemit $b22 $rDef 'ReemitFix.TFromD' 'ReemitFix.TToD'
Check 'sparse mapping exit 0' ($script:LastExit -eq 0) "out=$o22"
$j22 = $o22 | ConvertFrom-Json
Check 'sparse mapping: the #when fires on the resolved default (Mode2 = dmB)' `
  ($j22.dfm -match 'Mode2\s*=\s*dmB') "dfm=$($j22.dfm)"
Check 'sparse mapping: no absent-source note is reported' `
  (@($j22.report.mappingNotes | Where-Object { $null -ne $_ }).Count -eq 0) "out=$o22"

# 23 (CONTROL): the same shape on a property with NO default clause. Such a
# property is ALWAYS streamed, so its absence is genuinely unknown -- the engine
# must still refuse to invent a value. Without this, case 22 is equally
# satisfied by "resolve everything absent to something".
$rPlain = "#mapping PM from ReemitFix.TDefMode to ReemitFix.TToD`r`n" +
          "#mapping PM #when Plain = 5 -> Plain2 = 7`r`n" +
          "#convert TFromD -> TToD`r`n" +
          "#apply PM`r`n"
$b23 = "object C1: TFromD`r`nend`r`n"
$o23 = Reemit $b23 $rPlain 'ReemitFix.TFromD' 'ReemitFix.TToD'
Check 'no-default-clause exit 0' ($script:LastExit -eq 0) "out=$o23"
$j23 = $o23 | ConvertFrom-Json
Check 'no-default-clause: NOTHING is invented for Plain2' `
  (-not ($j23.dfm -match 'Plain2')) "dfm=$($j23.dfm)"
Check 'no-default-clause: the absent-source note still fires, and says why' `
  (@($j23.report.mappingNotes) -match 'no default clause') "out=$o23"

# 24 (D4): a #link whose SOURCE is absent-because-default. F defaults to dmA and
# T defaults to dmC, so emitting nothing would silently change the value. The
# resolved value must be written.
$b24 = "object C1: TFromD`r`nend`r`n"
$r24 = "#convert TFromD -> TToD`r`n#link Mode2 <- Mode`r`n"
$o24 = Reemit $b24 $r24 'ReemitFix.TFromD' 'ReemitFix.TToD'
Check 'link-default exit 0' ($script:LastExit -eq 0) "out=$o24"
$j24 = $o24 | ConvertFrom-Json
$dr24 = @($j24.report.defaultsResolved | Where-Object { $null -ne $_ })
Check 'link-default: F''s resolved default is written (Mode2 = dmA)' `
  ($j24.dfm -match 'Mode2\s*=\s*dmA') "dfm=$($j24.dfm)"
Check 'link-default: T''s OWN default is NOT what lands (not dmC)' `
  (-not ($j24.dfm -match 'dmC')) "dfm=$($j24.dfm)"
Check 'link-default: the resolution is reported' ($dr24.Count -eq 1) "out=$o24"
Check 'link-default: the report names source, target and value' `
  ($dr24.Count -eq 1 -and $dr24[0].fromPath -eq 'Mode' -and `
   $dr24[0].toPath -eq 'Mode2' -and $dr24[0].value -eq 'dmA') "out=$o24"
# The blanket 'defaults may diverge' warning fired on EVERY F<>T conversion and
# could not be acted on. With nothing left unresolved it must be silent.
Check 'link-default: the blanket divergence warning is GONE' `
  (-not (@($j24.report.notes) -match 'may diverge')) "notes=$($j24.report.notes -join ' | ')"

# 25 (D3): F's default and T's default are the SAME value here, so leaving the
# property absent would still be correct today -- and would rot the moment
# either declaration changes. It must be emitted EXPLICITLY. Delphi trims it on
# the next save, so verbosity costs nothing.
$b25 = "object C1: TFromD`r`nend`r`n"
$r25 = "#convert TFromD -> TToD`r`n#link Same2 <- Same`r`n"
$o25 = Reemit $b25 $r25 'ReemitFix.TFromD' 'ReemitFix.TToD'
Check 'explicit-emit exit 0' ($script:LastExit -eq 0) "out=$o25"
$j25 = $o25 | ConvertFrom-Json
Check 'explicit-emit: written even though it equals T''s own default' `
  ($j25.dfm -match 'Same2\s*=\s*True') "dfm=$($j25.dfm)"

# 26: the narrowed divergence note. A rule-referenced source that is absent AND
# has no default clause is the one case that genuinely remains unknown -- and
# the note must NAME it rather than gesture at the whole class pair.
$b26 = "object C1: TFromD`r`nend`r`n"
$r26 = "#convert TFromD -> TToD`r`n#link Plain2 <- Plain`r`n"
$o26 = Reemit $b26 $r26 'ReemitFix.TFromD' 'ReemitFix.TToD'
Check 'unresolved-note exit 0' ($script:LastExit -eq 0) "out=$o26"
$j26 = $o26 | ConvertFrom-Json
Check 'unresolved-note: nothing is invented for Plain2' `
  (-not ($j26.dfm -match 'Plain2')) "dfm=$($j26.dfm)"
Check 'unresolved-note: the note names the offending property' `
  (@($j26.report.notes) -match 'Plain') "notes=$($j26.report.notes -join ' | ')"

# --- Cases 27-30: the four ways default-resolution wrote WRONG values --------
# Found by review after cases 22-26 were green, which is the point: every one of
# these emits a bad value into a real form file at exit 0, and cases 22-26 are
# structurally blind to all of them (single-class rule books, no set default, no
# `stored` clause, no #remove).

# 27: an owned part with its OWN #convert. HandleNested re-enters the engine
# with the FULL rule set and the PARENT's trees -- a pure unit cannot rebuild
# them -- so resolving defaults there answered from the wrong class. Three
# distinct wrong emissions came out of this one block:
#   * the parent's Mode2 written INTO the part (TNewColD has no Mode2 -> the
#     form raises EReadError on load);
#   * the part's own `#link Shown <- Visible` resolved against TFromD.Visible
#     (default False) instead of TOldColD.Visible (default True) -- a silently
#     WRONG value, which is worse than a loud one;
#   * `Shown` written onto the PARENT, whose TToD has no such property.
$b27 = "object C1: TFromD`r`n  object Col1: TOldColD`r`n    Width = 5`r`n  end`r`nend`r`n"
$r27 = "#convert TFromD -> TToD`r`n#link Mode2 <- Mode`r`n" +
       "#convert TOldColD -> TNewColD`r`n#link Width <- Width`r`n#link Shown <- Visible`r`n"
$o27 = Reemit $b27 $r27 'ReemitFix.TFromD' 'ReemitFix.TToD'
Check 'owned-part exit 0' ($script:LastExit -eq 0) "out=$o27"
$j27 = $o27 | ConvertFrom-Json
$col27 = [regex]::Match($j27.dfm, '(?s)object Col1: TNewColD(.*?)\r?\n  end')
$col27Body = if ($col27.Success) { $col27.Groups[1].Value } else { '' }
Check 'owned-part: the part block was located' ($col27Body -ne '') "dfm=$($j27.dfm)"
Check 'owned-part: the part keeps its own streamed Width = 5' `
  ($col27Body -match 'Width\s*=\s*5') "part=$col27Body"
Check 'owned-part: the PARENT''s property is NOT injected into the part' `
  (-not ($col27Body -match 'Mode2')) "part=$col27Body"
Check 'owned-part: the part does NOT get a value resolved from the PARENT''s tree' `
  (-not ($col27Body -match 'Shown')) "part=$col27Body"
Check 'owned-part: a part-only target is NOT written onto the parent (TToD has no Shown)' `
  (-not ($j27.dfm -match '(?m)^  Shown\s*=')) "dfm=$($j27.dfm)"
# CONTROL: the parent's OWN link must still resolve, or this case is satisfied
# by default-resolution being switched off everywhere.
Check 'owned-part: CONTROL -- the parent''s own default still resolves (Mode2 = dmA)' `
  ($j27.dfm -match '(?m)^  Mode2\s*=\s*dmA') "dfm=$($j27.dfm)"

# 28: a SET default. `default [odA, odB]` contains a space; reading the value as
# "up to the first space" truncated it to `[odA,`, which is not loadable DFM.
# Assert the WHOLE literal -- a substring match would accept the prefix.
$b28 = "object C1: TFromD`r`nend`r`n"
$r28 = "#convert TFromD -> TToD`r`n#link Anchors2 <- Anchors`r`n"
$o28 = Reemit $b28 $r28 'ReemitFix.TFromD' 'ReemitFix.TToD'
Check 'set-default exit 0' ($script:LastExit -eq 0) "out=$o28"
$j28 = $o28 | ConvertFrom-Json
Check 'set-default: the whole set literal is emitted, not a truncated prefix' `
  ($j28.dfm -match '(?m)^\s*Anchors2\s*=\s*\[odA, odB\]\s*$') "dfm=$($j28.dfm)"

# 29: a CONDITIONALLY STORED source. `stored IsGuardedStored` means the property
# is omitted regardless of its value, so absence does NOT mean "at the default"
# and nothing may be carried. The VCL case this stands for is Color/ParentColor,
# where writing the resolved default also CLEARS the inheritance.
$b29 = "object C1: TFromD`r`nend`r`n"
$r29 = "#convert TFromD -> TToD`r`n#link Guarded2 <- Guarded`r`n"
$o29 = Reemit $b29 $r29 'ReemitFix.TFromD' 'ReemitFix.TToD'
Check 'stored-veto exit 0' ($script:LastExit -eq 0) "out=$o29"
$j29 = $o29 | ConvertFrom-Json
Check 'stored-veto: nothing is carried for a conditionally-stored source' `
  (-not ($j29.dfm -match 'Guarded2')) "dfm=$($j29.dfm)"
Check 'stored-veto: it is REPORTED as unresolved rather than dropped in silence' `
  (@($j29.report.notes) -match 'may diverge.*Guarded') "notes=$($j29.report.notes -join ' | ')"

# 30: #remove must beat default-resolution. RemapLeaf checks it first for a
# streamed leaf; without the same check here a removed property was resurrected
# whenever it happened to sit at its default -- so its fate depended on the
# value it held, which is the one thing #remove is supposed to make irrelevant.
$b30 = "object C1: TFromD`r`nend`r`n"
$r30 = "#convert TFromD -> TToD`r`n#link Mode2 <- Mode`r`n#remove Mode`r`n"
$o30 = Reemit $b30 $r30 'ReemitFix.TFromD' 'ReemitFix.TToD'
Check 'remove-beats-default exit 0' ($script:LastExit -eq 0) "out=$o30"
$j30 = $o30 | ConvertFrom-Json
Check 'remove-beats-default: the removed property is not resurrected' `
  (-not ($j30.dfm -match 'Mode2')) "dfm=$($j30.dfm)"

# --- Bad args ---
$noOut = ((& $Exe convert-reemit 2>&1) -join "`n"); $noExit = $LASTEXITCODE
Check 'no args exit 2' ($noExit -eq 2) "exit=$noExit"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
