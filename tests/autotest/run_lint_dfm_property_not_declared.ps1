<#
run_lint_dfm_property_not_declared.ps1 -- R1's guard.

WAS `pending_*` UNTIL THE RULE SHIPPED. Renamed in the same commit, as its own
header demanded: a pending_ file that outlives its reason is a test nobody runs.

WHAT THE RULE DOES. A .dfm sets a property that the component's class and its
ancestors do not declare -- at runtime an obscure load failure or a silently
dropped setting, and nothing else in the catalog looks at it.

WHY THE NEGATIVES ARE THE HARD PART. The positive case is easy to make fire.
The danger is firing on CORRECT code, in three distinct ways: the property is
declared on an ANCESTOR (most are); an ancestor CANNOT BE RESOLVED, so the
chain is unknown rather than empty; the class name is AMBIGUOUS.

>>> THE MEASUREMENT THAT DECIDES THE DEFAULT-ON RULING (2026-09-10) <<<

Two fixtures, identical except for one token, indexed and linted the same way:

    TBaseThing = class            -> the undeclared property FIRES
    TBaseThing = class(TObject)   -> SILENT, 0 findings

That is not a fixture quirk. `TObject` is not in a project-only index, so it is
an UNRESOLVED ancestor, and gate (b) suppresses the whole class -- correctly, by
its own contract. Every real Delphi class names an explicit ancestor, so:

  ** WITHOUT A LIBRARY INDEX ATTACHED, THIS RULE IS SILENT ON REAL CODE. **

The fixtures below therefore use IMPLICIT roots, which is the only way to
exercise the rule without shipping an RTL index into a test. R3 must measure the
real volume on ORM3 CLIENT **with the platform library DB attached**, and a
run that reports nothing there is far more likely to mean "the library index did
not attach" than "the corpus is clean". Check that before believing a zero.

THE OPT-IN TRAP THIS GUARD ALSO COVERS. The rule is gated on OptedIn as well as
WantRule, and `--enable` feeds the CONFIG FILTER, not the opt-in array -- those
are two different lists. While the id was missing from CLI.pas's OptIn arrays
the rule was UNREACHABLE and answered "0 finding(s)" for every input, which is
indistinguishable from a clean corpus. Case 0 is the positive control for
exactly that: if the rule cannot fire at all, it fails FIRST and every negative
below is exposed as vacuous rather than passing quietly.

MUTATION RESULTS, MEASURED 2026-09-10 against the finished rule:

  M1 the unresolved-ancestor gate removed  -> NEG(b) only
  M2 the WHOLE dotted name checked         -> the dotted NEG only
  M3 ancestors not walked, class only      -> NEG(a), the dotted NEG, and the
                                              collection NEG (all three are
                                              inherited properties)
  M4 the id removed from PROJECT_RULES_OFF_BY_DEFAULT -> NOT CAUGHT, and that
     is recorded rather than fixed. The rule has TWO independent gates and the
     OptIn one fires first: without --enable the rule never RUNS, so there is
     nothing for the print filter to drop and "OFF by default" passes either
     way. The list entry is defence-in-depth for a future caller that opts the
     rule in for its own reasons -- real, but not observable from here. Do not
     add an assertion that appears to cover it; it would be theatre.

Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){
  Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''}))
  if(-not $ok){ $script:fail = $true }
}

$work = Join-Path $env:TEMP ("dl-dfmprop-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $work | Out-Null
function W([string]$p,[string[]]$l){ [IO.File]::WriteAllText($p, (($l -join "`r`n")+"`r`n"), [Text.Encoding]::ASCII) }

# IMPLICIT roots -- see the header. `class(TObject)` here would silence the rule
# entirely and make every assertion below pass for the wrong reason.
W (Join-Path $work 'uBase.pas') @(
  'unit uBase;','','interface','','type','  TBaseThing = class','  private',
  '    FCaption: string;','  published','    property Caption: string read FCaption write FCaption;',
  '    property Font: TObject read FFont write FFont;',
  '    property Columns: TObject read FCols write FCols;',
  '  private','    FFont: TObject;','    FCols: TObject;',
  '  end;','','  TDerivedThing = class(TBaseThing)','  end;','',
  '  TForeignThing = class(TSomethingNotInThisIndex)','  end;','',
  '  TStreamerBase = class','  protected',
  '    procedure DefineProperties(Filer: TObject);',
  '    procedure Decoyer;','  end;','',
  '  TStreamer = class(TStreamerBase)','  end;','',
  'implementation','',
  'procedure TStreamerBase.DefineProperties(Filer: TObject);','begin',
  "    Filer.DefineProperty('Streamed');",'end;','',
  'procedure TStreamerBase.Decoyer;','begin',
  "    WriteLn('Decoy');",'end;','','end.')

W (Join-Path $work 'uForm.pas') @(
  'unit uForm;','','interface','','uses','  uBase;','','type',
  '  TMyForm = class','  published','    Widget: TDerivedThing;',
  '    Alien : TForeignThing;','    Grid  : TDerivedThing;',
  '    Streamy: TStreamer;','  end;','','implementation','','end.')

W (Join-Path $work 'uForm.dfm') @(
  'object MyForm: TMyForm',
  '  object Widget: TDerivedThing',
  "    Caption = 'inherited, must be SILENT'",
  "    Nonsense = 'declared nowhere, must FIRE'",
  '    Font.Height = -11',
  '  end',
  '  object Alien: TForeignThing',
  "    Whatever = 'ancestor unresolved, must be SILENT'",
  '  end',
  '  object Grid: TDerivedThing',
  '    Columns = <',
  '      item',
  "        ItemOnly = 'inside an item block, must be SILENT'",
  '      end>',
  '  end',
  '  object Streamy: TStreamer',
  "    Streamed = 'streamed by an inherited DefineProperties, must be SILENT'",
  "    Bogus = 'neither declared nor streamed, must FIRE'",
  "    Decoy = 'a literal in ANOTHER method, must FIRE'",
  '  end',
  'end')

$db = Join-Path $work 'fx.sqlite'
& $Exe index $work --db $db --rebuild *> $null
Check 'fixture indexed' (Test-Path $db) $db

$out  = (& $Exe lint-all --db $db --quiet --enable dfm-property-not-declared 2>$null | Out-String)
$rows = @($out -split "`r?`n" | Where-Object { $_ -match 'dfm-property-not-declared' })

# 0 -- POSITIVE CONTROL FOR THE WHOLE FILE. Every NEG below is a claim that
# something did NOT appear, and all of them are satisfied by a rule that cannot
# run at all -- which is precisely the state the missing OptIn entry produced.
Check 'CONTROL the rule is reachable and produced at least one row' `
      ($rows.Count -ge 1) `
      "0 rows: the rule is unreachable (check the OptIn arrays in CLI.pas), not the corpus clean"

Check 'POS an undeclared property is reported' `
      (($rows | Where-Object { $_ -match 'Nonsense' }).Count -ge 1) `
      "rows: $($rows.Count)"

Check 'NEG a property inherited from an ancestor is SILENT' `
      (($rows | Where-Object { $_ -match 'Caption' }).Count -eq 0) `
      'flagging inherited Caption would fire on most forms in the corpus'

# A dotted property sets a member of the object the FIRST segment holds. The
# class declares Font, not Font.Height; checking the whole dotted string would
# report every sub-object property in the corpus.
Check 'NEG a DOTTED property is checked by its first segment only' `
      (($rows | Where-Object { $_ -match 'Font\.Height' }).Count -eq 0) `
      'Font is declared; Font.Height is a property of what Font holds'

Check 'NEG an UNRESOLVED ancestor is SILENT, not treated as empty' `
      (($rows | Where-Object { $_ -match 'Whatever' }).Count -eq 0) `
      'treating unresolved as "no such property" reports the whole VCL as undeclared'

# The extractor emits `Columns = <item ... end>` as ONE dfm-prop row whose VALUE
# text contains the item's properties, so ItemOnly never arrives as a property
# name. This asserts that an implementation which split the value text would be
# caught -- ItemOnly is declared nowhere, so it would fire if it were seen.
Check 'NEG a property inside a collection item block is SILENT' `
      (($rows | Where-Object { $_ -match 'ItemOnly' }).Count -eq 0) `
      'the item value is one row; splitting it would report names no class was ever asked about'

Check 'NEG the collection property itself is declared, so Columns is not reported' `
      (($rows | Where-Object { $_ -match '"Columns"' }).Count -eq 0) `
      'Columns is undeclared on TDerivedThing -- if this fires, the fixture, not the rule, is wrong'

# ---- DefineProperties scoping -------------------------------------------
# 226 of the 321 findings on ORM3 CLIENT were `Left`/`Top`, which NEITHER
# TComponent NOR TPersistent declares -- they are streamed by
# TComponent.DefineProperties. A pseudo-property is written by a
# `Filer.DefineProperty('Name')` call in a DefineProperties BODY, so the literal
# names in that body are read and treated as declared members.
#
# THE FIRST PROPOSAL -- "silence the class when an ancestor declares
# DefineProperties" -- WAS REFUTED BY MEASUREMENT: it missed 132 findings whose
# chain has no DefineProperties at all, and would have silenced every visual
# control, since TControl/TWinControl/TCustomForm all declare it. The two checks
# below are what separate the two designs.
Check 'NEG a name streamed by an inherited DefineProperties is SILENT' `
      (($rows | Where-Object { $_ -match 'Streamed' }).Count -eq 0) `
      'Left/Top and 226 of the 321 ORM3 findings are exactly this shape'

Check 'POS a class WITH DefineProperties still reports a name it neither declares nor streams' `
      (($rows | Where-Object { $_ -match 'Bogus' }).Count -ge 1) `
      'THIS is the assertion that refutes "silence the whole class"; without it the fix is indistinguishable from switching the rule off for anything that streams'

Check 'POS a literal OUTSIDE the DefineProperties span still FIRES' `
      (($rows | Where-Object { $_ -match 'Decoy' }).Count -ge 1) `
      'proves the IMPL-SPAN filter rather than "any literal anywhere in the unit"'

# THE DEFAULT FLIPPED ON THE OWNER'S RULING, 2026-09-14: "lets enable all 3 and
# see what happens." The assertion is inverted rather than deleted, because the
# thing worth pinning is the same either way -- that the DEFAULT is what someone
# decided, not what a gate happened to do.
#
# It takes THREE changes to move this rule's default and the first two are not
# enough on their own, which is exactly why this check exists: the catalog's
# default_enabled, removal from PROJECT_RULES_OFF_BY_DEFAULT (the print filter),
# and the OptIn gate in CLI.pas. That third one reads
# `ShouldKeep(id, ADefaultDisabled)` -- passing True means "OFF unless someone
# --enables it". With the first two flipped and the third still True, `rules
# --json` reported the rule ON and a default lint-all still printed NOTHING,
# which is indistinguishable from a clean corpus.
Check 'the rule is ON by default (owner ruling 2026-09-14)' `
      (((& $Exe lint-all --db $db --quiet 2>$null | Out-String) -match 'dfm-property-not-declared')) `
      'all THREE gates must agree: catalog default_enabled, the print filter, and ShouldKeep(id, ADefaultDisabled=False)'

Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
if($fail){ Write-Host 'DFM PROPERTY GUARD: FAIL' -ForegroundColor Red; exit 1 }
else     { Write-Host 'DFM PROPERTY GUARD: PASS' -ForegroundColor Green; exit 0 }
