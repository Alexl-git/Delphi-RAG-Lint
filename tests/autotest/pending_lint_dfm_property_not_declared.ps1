<#
pending_lint_dfm_property_not_declared.ps1 -- R1's failing test, written BEFORE
the rule.

PENDING BY DESIGN. Named `pending_*` so the battery, which enumerates `run_*.ps1`,
does not pick up a guard whose rule does not exist. RENAME TO `run_*` IN THE SAME
COMMIT THAT SHIPS THE RULE -- a pending_ file that outlives its reason is a test
nobody runs, and this repo already has one of those.

WHAT THE RULE MUST DO. A `.dfm` sets a property that the component's class and
its ancestors do not declare. That is a real defect -- the form fails to load at
runtime with an obscure error, or silently loses the setting -- and no rule
covers it today.

WHY THE NEGATIVES ARE THE HARD PART. The positive case is easy to make fire; the
danger is a rule that fires on correct code, and there are three distinct ways
that happens:

  (a) the property is declared on an ANCESTOR, not the class itself. A rule that
      only looks at the immediate class flags every inherited Caption in the
      codebase -- which is most of them.

  (b) an ancestor CANNOT BE RESOLVED (the library index is absent, or the class
      derives from something outside the closure). The chain is then unknown,
      not empty, and the honest answer is SILENCE. A rule that treats
      "unresolved" as "no such property" reports the entire VCL as undeclared.

  (c) the row sits inside a collection `item` block, where the owning class is a
      collection-item type the DFM never names. Also silence.

Case (b) is the one that decides whether this rule is shippable at all, which is
why it is asserted here rather than left to the R3 audit to discover on 700
files.

WHAT THIS DOES NOT COVER. Tier B ("the property exists but is not published")
needs the `{$M+}` default-section rule and is a separate assertion set; both of
its extractor prerequisites landed in 7f4720c, so it is buildable, but it is not
this file's job.

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

# A base class declaring Caption, a descendant declaring nothing, and a class
# whose ancestor is OUTSIDE this index (unresolvable on purpose).
W (Join-Path $work 'uBase.pas') @(
  'unit uBase;','','interface','','type','  TBaseThing = class(TObject)','  private',
  '    FCaption: string;','  published','    property Caption: string read FCaption write FCaption;',
  '  end;','','  TDerivedThing = class(TBaseThing)','  end;','',
  '  TForeignThing = class(TSomethingNotInThisIndex)','  end;','','implementation','','end.')

W (Join-Path $work 'uForm.pas') @(
  'unit uForm;','','interface','','uses','  uBase;','','type',
  '  TMyForm = class(TObject)','  published','    Widget: TDerivedThing;',
  '    Alien : TForeignThing;','  end;','','implementation','','end.')

# POS: Nonsense is declared nowhere.   NEG(a): Caption comes from TBaseThing.
# NEG(b): the Alien class has an unresolvable ancestor.
# NEG(c): the row inside an item block has no nameable owning class.
W (Join-Path $work 'uForm.dfm') @(
  'object MyForm: TMyForm',
  '  object Widget: TDerivedThing',
  "    Caption = 'inherited, must be SILENT'",
  "    Nonsense = 'declared nowhere, must FIRE'",
  '  end',
  '  object Alien: TForeignThing',
  "    Whatever = 'ancestor unresolved, must be SILENT'",
  '  end',
  '  object Grid: TDerivedThing',
  '    Columns = <',
  '      item',
  "        Caption = 'inside an item block, must be SILENT'",
  '      end>',
  '  end',
  'end')

$db = Join-Path $work 'fx.sqlite'
& $Exe index $work --db $db --rebuild *> $null
Check 'fixture indexed' (Test-Path $db) $db

$out = (& $Exe lint-all --db $db --quiet --enable dfm-property-not-declared 2>$null | Out-String)
$rows = @($out -split "`r?`n" | Where-Object { $_ -match 'dfm-property-not-declared' })

Check 'POS an undeclared property is reported' `
      (($rows | Where-Object { $_ -match 'Nonsense' }).Count -ge 1) `
      "rows: $($rows.Count)"
Check 'NEG a property inherited from an ancestor is SILENT' `
      (($rows | Where-Object { $_ -match 'inherited' -or $_ -match "Caption" }).Count -eq 0) `
      'flagging inherited Caption would fire on most forms in the corpus'
Check 'NEG an UNRESOLVED ancestor is SILENT, not treated as empty' `
      (($rows | Where-Object { $_ -match 'Whatever' }).Count -eq 0) `
      'treating unresolved as "no such property" reports the whole VCL as undeclared'
Check 'NEG a row inside a collection item block is SILENT' `
      (($rows | Where-Object { $_ -match 'item' }).Count -eq 0) `
      'the owning class of an item row is not nameable from the DFM'
Check 'the rule is OFF by default (R3 audits before it ships ON)' `
      (((& $Exe lint-all --db $db --quiet 2>$null | Out-String) -notmatch 'dfm-property-not-declared')) `
      'a new project-wide rule must not default ON before its volume is measured'

Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
if($fail){ Write-Host 'DFM PROPERTY GUARD: FAIL' -ForegroundColor Red; exit 1 }
else     { Write-Host 'DFM PROPERTY GUARD: PASS' -ForegroundColor Green; exit 0 }
