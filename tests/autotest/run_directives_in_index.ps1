<#
  run_directives_in_index.ps1 -- PLAN A (docs\PLAN-routine-directives-in-index.md)
  T2: symbols.directives carries EVERY routine directive, canonical lowercase, in
  declaration order, space-joined.

  WHAT WAS MISSING. Every routine directive was absent from the index.
  symbols.signature is params + return type; symbols.modifiers is visibility plus
  a mirrored `message`; is_virtual collapses virtual/dynamic/override into ONE
  bit. Hover and `document` re-read the declaration LINE with a regex to learn
  deprecated / virtual / abstract, which misses any WRAPPED declaration.

  GRAMMAR FACTS, MEASURED (tools\dumpnode, 2026-09-09, uDirs.pas fixture):
    * 22 directive kinds, each its OWN procAttribute node -- `virtual; abstract;`
      is TWO nodes, not one node with two children.
    * the keyword is ALWAYS the FIRST named child, spelled k<Directive> in
      PascalCase. 28 procAttribute nodes, 0 exceptions to that rule.
    * `external` is NOT a procAttribute: it is a sibling procExternal node whose
      child[0] is kExternal.
    * payloads observed: kDeprecated(literalString), kMessage(literalNumber).
      NOTE the plan predicted kMessage(identifier); the real payload is a NUMBER.
      Immaterial to the design -- only the BARE keyword is stored -- but recorded
      because the plan's stated fact was wrong.

  WHY A NEW COLUMN AND NOT `modifiers`. Four consumers equality-match
  Trim(Modifiers) as THE visibility word, or use Modifiers = '' as "not a
  method": LSP.Server, LSP.Completion, Convert.PropTree and CLI.IsValidTarget
  (Vis in ('published','public')). Appending directive tokens to modifiers breaks
  all four -- IsValidTarget would silently drop members from proptree. This guard
  asserts the modifiers of every method are UNCHANGED, which is the Option B
  promise stated as a test rather than as a comment.

  CASES
    positive  one routine per directive, plus the multi-directive combinations
              that prove ORDER and JOINING (virtual; abstract; / virtual;
              overload; stdcall;), plus `external`.
    negative  `procedure MPlain;` -> directives is PRESENT and EMPTY, never
              absent and never null. This is the case that distinguishes "the
              column exists and this routine has none" from "the column is not
              there", and it is why CLI emits the field unconditionally.
    control   modifiers byte-identical to the pre-change engine for every method;
              is_virtual still true for exactly virtual/dynamic/override/final-
              on-virtual and false otherwise.
    wrapped   a declaration whose directive sits on the NEXT line. This is the
              case the old line-regex could never see, so it is the one that
              proves the column is read from the AST and not from the line.

  MEASURED RED, THEN GREEN -- pre-change engine
  (scratchpad\engine-preA, extractor 1.14.0-alpha, resolver 1.2.0-alpha,
   sha256 C47510745578EB3C4F501EBEB3BCD832E8B3F9A1F3357F0FF8B28EF847B12C34):

    RED: see the header block written by T6 below.

  VERBATIM RED, captured 2026-09-09 22:49 against that engine:

    engine: extractor=1.14.0-alpha resolver=1.2.0-alpha exe=C:\TEMP\claude\c--Projects-Delphi-RAG-lint\46ac75c6-8655-4a1c-9ca4-6ea10187bdad\scratchpad\engine-preA\drag-lint.exe
      [PASS] index exits 0 exit=0
      [FAIL] MVirtual -> 'virtual' got: 'FIELD-ABSENT'
      [FAIL] MDynamic -> 'dynamic' got: 'FIELD-ABSENT'
      [FAIL] MOverride -> 'override' got: 'FIELD-ABSENT'
      [FAIL] MAbstract -> 'virtual abstract' got: 'FIELD-ABSENT'
      [FAIL] MOverload -> 'overload' got: 'FIELD-ABSENT'
      [FAIL] MReintroduce -> 'reintroduce' got: 'FIELD-ABSENT'
      [FAIL] MFinal -> 'virtual final' got: 'FIELD-ABSENT'
      [FAIL] MStatic -> 'static' got: 'FIELD-ABSENT'
      [FAIL] MAssembler -> 'assembler' got: 'FIELD-ABSENT'
      [FAIL] MExport -> 'export' got: 'FIELD-ABSENT'
      [FAIL] MInline -> 'inline' got: 'FIELD-ABSENT'
      [FAIL] MDeprecated -> 'deprecated' got: 'FIELD-ABSENT'
      [FAIL] MPlatform -> 'platform' got: 'FIELD-ABSENT'
      [FAIL] MExperimental -> 'experimental' got: 'FIELD-ABSENT'
      [FAIL] MMessage -> 'message' got: 'FIELD-ABSENT'
      [FAIL] MStdcall -> 'stdcall' got: 'FIELD-ABSENT'
      [FAIL] MCdecl -> 'cdecl' got: 'FIELD-ABSENT'
      [FAIL] MPascal -> 'pascal' got: 'FIELD-ABSENT'
      [FAIL] MRegister -> 'register' got: 'FIELD-ABSENT'
      [FAIL] MSafecall -> 'safecall' got: 'FIELD-ABSENT'
      [FAIL] MWinapi -> 'winapi' got: 'FIELD-ABSENT'
      [FAIL] MVarargs -> 'varargs' got: 'FIELD-ABSENT'
      [FAIL] MCombo -> 'virtual overload stdcall' got: 'FIELD-ABSENT'
      [FAIL] FreeExternal -> 'external' got: 'FIELD-ABSENT'
      [FAIL] MWrapped -> 'virtual' (read from the AST, not the declaration line) got: 'FIELD-ABSENT'
      [FAIL] MPlain has a 'directives' FIELD at all the field must be emitted unconditionally, or the empty case cannot be told from a missing column
      [FAIL] FreePlain has a 'directives' FIELD at all the field must be emitted unconditionally, or the empty case cannot be told from a missing column
      [PASS] MVirtual modifiers is still exactly 'public' got: 'public'
      [PASS] MAbstract modifiers is still exactly 'public' got: 'public'
      [PASS] MCombo modifiers is still exactly 'public' got: 'public'
      [PASS] MPlain modifiers is still exactly 'public' got: 'public'
      [PASS] MStdcall modifiers is still exactly 'public' got: 'public'
      [PASS] MMessage keeps its mirrored ' message' in modifiers (DeadCodeChecks depends on it) got: 'public message'
      [FAIL] MVirtual has an 'is_virtual' field absent means this assertion measures nothing -- see the note above
      [FAIL] MDynamic has an 'is_virtual' field absent means this assertion measures nothing -- see the note above
      [FAIL] MOverride has an 'is_virtual' field absent means this assertion measures nothing -- see the note above
      [FAIL] MAbstract has an 'is_virtual' field absent means this assertion measures nothing -- see the note above
      [FAIL] MPlain has an 'is_virtual' field absent means this assertion measures nothing -- see the note above
      [FAIL] MStdcall has an 'is_virtual' field absent means this assertion measures nothing -- see the note above
    FAIL


  A RED READING THAT PRINTS 1.15.0-alpha IS NOT A RED -- it was taken against the
  fixed build. Every run prints the engine's extractor_version first, so the log
  names what it measured.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-directives-in-index"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# Name the engine under test FIRST, so a RED log cannot be mistaken for a reading
# of a different build.
$info = (& $Exe info --json 2>$null) -join "`n" | ConvertFrom-Json
Write-Host ("engine: extractor={0} resolver={1} exe={2}" -f $info.extractor_version, $info.resolver_version, $Exe) -ForegroundColor Cyan

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

$work = Join-Path $WorkDir 'fixture'
Write-Ascii (Join-Path $work 'uDirs.pas') @'
unit uDirs;

interface

type
  TDirKit = class(TObject)
  public
    procedure MVirtual; virtual;
    procedure MDynamic; dynamic;
    procedure MOverride; override;
    procedure MAbstract; virtual; abstract;
    procedure MOverload(A: Integer); overload;
    procedure MReintroduce; reintroduce;
    procedure MFinal; virtual; final;
    procedure MStatic; static;
    procedure MAssembler; assembler;
    procedure MExport; export;
    procedure MInline; inline;
    procedure MDeprecated; deprecated 'use MVirtual';
    procedure MPlatform; platform;
    procedure MExperimental; experimental;
    procedure MMessage(var Msg); message 1024;
    procedure MStdcall; stdcall;
    procedure MCdecl; cdecl;
    procedure MPascal; pascal;
    procedure MRegister; register;
    procedure MSafecall; safecall;
    procedure MWinapi; winapi;
    procedure MVarargs; varargs;
    procedure MCombo; virtual; overload; stdcall;
    procedure MPlain;
    procedure MWrapped;
      virtual;
  end;

procedure FreeExternal; external 'kernel32.dll' name 'Beep';
procedure FreePlain;

implementation

procedure FreePlain;
begin
end;

end.
'@

$db = Join-Path $WorkDir 'dirs.sqlite'
$idx = & $Exe index $work --db $db 2>$null
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

# One query, reused: every symbol in the fixture unit.
function Get-Sym([string]$Name) {
  $raw = (& $Exe query --name $Name --exact --json --db $db 2>$null) -join "`n"
  if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
  $rows = @($raw | ConvertFrom-Json)
  return $rows | Where-Object { $_.kind -in @('method','procedure','function') } | Select-Object -First 1
}

# ---------------------------------------------------------------------------
# POSITIVE: one assertion per directive.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'POSITIVE: every directive reaches symbols.directives' -ForegroundColor Cyan

$expected = [ordered]@{
  MVirtual      = 'virtual'
  MDynamic      = 'dynamic'
  MOverride     = 'override'
  MAbstract     = 'virtual abstract'
  MOverload     = 'overload'
  MReintroduce  = 'reintroduce'
  MFinal        = 'virtual final'
  MStatic       = 'static'
  MAssembler    = 'assembler'
  MExport       = 'export'
  MInline       = 'inline'
  MDeprecated   = 'deprecated'
  MPlatform     = 'platform'
  MExperimental = 'experimental'
  MMessage      = 'message'
  MStdcall      = 'stdcall'
  MCdecl        = 'cdecl'
  MPascal       = 'pascal'
  MRegister     = 'register'
  MSafecall     = 'safecall'
  MWinapi       = 'winapi'
  MVarargs      = 'varargs'
  MCombo        = 'virtual overload stdcall'
  FreeExternal  = 'external'
}

$sawField = $false
foreach ($name in $expected.Keys) {
  $sym = Get-Sym $name
  if ($null -eq $sym) { Check "$name is indexed" $false 'symbol not found'; continue }
  $hasField = $null -ne ($sym.PSObject.Properties.Name | Where-Object { $_ -eq 'directives' })
  if ($hasField) { $sawField = $true }
  $got = if ($hasField) { [string]$sym.directives } else { 'FIELD-ABSENT' }
  Check "$name -> '$($expected[$name])'" ($got -eq $expected[$name]) "got: '$got'"
}

# ---------------------------------------------------------------------------
# The wrapped declaration -- the case a line regex structurally cannot see.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'WRAPPED: a directive on the following line' -ForegroundColor Cyan
$w = Get-Sym 'MWrapped'
$wHas = ($null -ne $w) -and ($null -ne ($w.PSObject.Properties.Name | Where-Object { $_ -eq 'directives' }))
$wGot = if ($wHas) { [string]$w.directives } else { 'FIELD-ABSENT' }
Check "MWrapped -> 'virtual' (read from the AST, not the declaration line)" ($wGot -eq 'virtual') "got: '$wGot'"

# ---------------------------------------------------------------------------
# NEGATIVE: present and empty, never absent, never null.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'NEGATIVE: a routine with no directives' -ForegroundColor Cyan
foreach ($n in @('MPlain','FreePlain')) {
  $s = Get-Sym $n
  if ($null -eq $s) { Check "$n is indexed" $false 'symbol not found'; continue }
  $has = $null -ne ($s.PSObject.Properties.Name | Where-Object { $_ -eq 'directives' })
  Check "$n has a 'directives' FIELD at all" $has "the field must be emitted unconditionally, or the empty case cannot be told from a missing column"
  if ($has) {
    Check "$n directives is EMPTY, not null" (([string]$s.directives) -eq '') "got: '$($s.directives)' (null? $($null -eq $s.directives))"
  }
}

# ---------------------------------------------------------------------------
# CONTROL: Option B's promise -- modifiers is untouched.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'CONTROL: modifiers unchanged (the reason a NEW column was chosen)' -ForegroundColor Cyan
foreach ($n in @('MVirtual','MAbstract','MCombo','MPlain','MStdcall')) {
  $s = Get-Sym $n
  if ($null -eq $s) { continue }
  Check "$n modifiers is still exactly 'public'" (([string]$s.modifiers).Trim() -eq 'public') "got: '$($s.modifiers)'"
}
$msg = Get-Sym 'MMessage'
if ($null -ne $msg) {
  Check "MMessage keeps its mirrored ' message' in modifiers (DeadCodeChecks depends on it)" (([string]$msg.modifiers) -match 'message') "got: '$($msg.modifiers)'"
}

# is_virtual (v12) must keep its exact meaning: the new column is ADDITIVE, and
# AstChecks/ProjectRules/SQLite still read the bit.
#
# THIS CONTROL WAS INEFFECTIVE AS FIRST WRITTEN, and the fix is the point.
# `query --json` did not emit is_virtual at all, so `[bool]$s.is_virtual` read an
# ABSENT property as $false -- MVirtual "failed" with got:False while the bit in
# the database was perfectly correct. An assertion whose subject is not in the
# output is not a weak test, it is a fabricated one. PLAN A therefore also emits
# is_virtual in query --json (one line, additive, same function as `directives`),
# which is what makes this invariant observable from a guard at all.
# Presence is asserted BEFORE value, so an absent field can never masquerade as
# a false value again.
Write-Host ''
Write-Host 'CONTROL: is_virtual keeps its v12 meaning' -ForegroundColor Cyan
foreach ($pair in @(@('MVirtual',$true), @('MDynamic',$true), @('MOverride',$true), @('MAbstract',$true), @('MPlain',$false), @('MStdcall',$false))) {
  $s = Get-Sym $pair[0]
  if ($null -eq $s) { continue }
  $has = $null -ne ($s.PSObject.Properties.Name | Where-Object { $_ -eq 'is_virtual' })
  Check "$($pair[0]) has an 'is_virtual' field" $has "absent means this assertion measures nothing -- see the note above"
  if ($has) {
    Check "$($pair[0]) is_virtual = $($pair[1])" (([bool]$s.is_virtual) -eq $pair[1]) "got: $([bool]$s.is_virtual)"
  }
}

if (-not $sawField) {
  Write-Host ''
  Write-Host '  NOTE: no symbol carried a `directives` field at all -- this is the expected RED shape before PLAN A lands.' -ForegroundColor Yellow
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
