<#
  run_const_and_type_detail_guard.ps1 -- a const must carry its TYPE and its
  VALUE in the index, and a class/interface/enum must describe itself in the
  completion popup's type slot.

  THE ASK (owner, live IDE, 2026-08-19): "We have to show the type of the result
  (be it property or something else)."

  run_completion_detail_type_guard.ps1 closed the first half of that ask and
  recorded what it deliberately left open:

      NOT COVERED, DELIBERATELY: a `const` carries no type in the index at all
      (measured -- signature is empty for all 106 consts in this repo's own DB).

  This guard closes it. The two halves are NOT the same kind of change, and the
  split is the whole point of the file:

    CONSTS are an EXTRACTOR change. Nothing in the store carried a const's type
    or its value, so the parser has to emit it and DRAGLINT_EXTRACTOR_VERSION
    has to move. Asserted against the INDEX (`query --json`), because that is
    where the new fact lives; the popup is downstream of it.

    CLASS / RECORD / INTERFACE / ENUM are NOT. Their ancestors have been in the
    `heritage` column since v11 and their enum members are already child
    symbols -- both already reach MakeCompletionItem inside the TSymbol it is
    handed. Filling `signature` for them in the parser would have duplicated
    indexed data and charged a SECOND full re-parse for nothing. Asserted
    against the LSP's `detail`, because that is where the change lives.

  WHAT WAS MEASURED before choosing the const format, rather than assumed --
  801 consts across drag-lint's own src, ORM3 CLIENT/COMMON and YADF:

      typed          `Ratio: Double = 1.5`      24%   declared type, exact
      untyped literal `= 100` / `= 'abc'`       66%   type follows the literal
      untyped expr    `= A * 2` / `= Foo(x)`    10%   not inferable

  So "type AND value", not one or the other. The value is always known and
  always exact; the type is exact for 24%, inferred for 66%, and absent for the
  last 10% -- where the value alone still carries the meaning and the row simply
  renders `const Derived = MaxItems * 2` with no type. Emitting only the type
  would have left that 10% blank, which is what the popup shows today.

  THE ONE PLACE THIS IS GENEROUS, stated rather than hidden: a single-character
  string constant (`const Sep = ','`) is reported as `string`, though Delphi
  will also accept it where a Char is wanted. The value is rendered beside the
  type, so the reader can see which it is -- that is the second reason the
  format carries both.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-const-detail"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function WriteAnsi($path, $text) {
  $t = ($text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($path, $t, (New-Object System.Text.ASCIIEncoding))
}
function Frame($o) {
  $j = $o | ConvertTo-Json -Compress -Depth 10
  $n = [Text.Encoding]::UTF8.GetByteCount($j)
  return "Content-Length: $n`r`n`r`n$j"
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$Src = Join-Path $WorkDir 'src'; New-Item -ItemType Directory $Src | Out-Null

# Every const shape the corpus measurement above found, plus the type kinds
# whose popup row was empty. TBase carries NO ancestor on purpose -- it is the
# control that proves an empty heritage stays empty rather than being invented.
$File = Join-Path $Src 'uConst.pas'
WriteAnsi $File @'
unit uConst;

interface

const
  MaxItems = 100;
  HexMask  = $FF;
  Ratio    = 1.5;
  AppName  = 'drag-lint';
  Enabled  = True;
  NoThing  = nil;
  Derived  = MaxItems * 2;
  Scaled   : Double = 2.5;
  Names    : array[0..1] of string = ('a', 'b');

resourcestring
  SGreeting = 'hello';

type
  TBase = class
  end;

  TThing = class(TBase)
  public
    const Version = 3;
    procedure DoIt;
  end;

  TRec = record
    X: Integer;
  end;

  IFoo = interface(IInterface)
  end;

  TState = (sIdle, sBusy, sDone);

procedure Go;

implementation

procedure TThing.DoIt; begin end;

procedure Go;
var
  T: TThing;
begin
  T := TThing.Create;
  T.DoIt;
  if Supports(T, IFoo) then Exit;
  Writeln(MaxItems);
end;

end.
'@

$Db = Join-Path $WorkDir 'const.sqlite'
& $Exe index $Src --db $Db 2>&1 | Out-Null
Check 'built the fixture index' (Test-Path $Db)

# ---- THE EXTRACTOR CONTRACT ------------------------------------------------
# Asserted against the index, not the popup. If this passes and the popup is
# still blank the fault is downstream; if this fails the popup cannot be right
# whatever the renderer does.
function SigOf([string]$name) {
  $raw = & $Exe query --name $name --db $Db --json 2>&1
  $txt = ($raw | Where-Object { $_ -notmatch '^\(loaded defaults' }) -join "`n"
  try { $o = $txt | ConvertFrom-Json } catch { return '<unparseable>' }
  if ($null -eq $o) { return '<absent>' }
  $rows = @($o) | Where-Object { $_.kind -eq 'const' -and $_.name -eq $name }
  if ($rows.Count -eq 0) { return '<absent>' }
  return [string]$rows[0].signature
}

Write-Host ''
Write-Host 'THE DEFECT: a const carries no type and no value in the index' -ForegroundColor Cyan
foreach ($c in @(
  @{ n = 'MaxItems' ; want = 'Integer = 100'                              ; note = 'untyped integer literal' },
  @{ n = 'HexMask'  ; want = 'Integer = $FF'                              ; note = 'hex literal'             },
  @{ n = 'Ratio'    ; want = 'Extended = 1.5'                             ; note = 'untyped real literal'    },
  @{ n = 'AppName'  ; want = "string = 'drag-lint'"                       ; note = 'untyped string literal'  },
  @{ n = 'Enabled'  ; want = 'Boolean = True'                             ; note = 'untyped boolean'         },
  @{ n = 'NoThing'  ; want = 'Pointer = nil'                              ; note = 'untyped nil'             },
  @{ n = 'Scaled'   ; want = 'Double = 2.5'                               ; note = 'DECLARED type wins'      },
  @{ n = 'Names'    ; want = "array[0..1] of string = ('a', 'b')"         ; note = 'declared array type'     },
  @{ n = 'SGreeting'; want = "string = 'hello'"                           ; note = 'resourcestring'          },
  @{ n = 'Version'  ; want = 'Integer = 3'                                ; note = 'class const'             }
)) {
  $got = SigOf $c.n
  Check ("{0} ({1})" -f $c.n, $c.note) ($got -eq $c.want) "want='$($c.want)' got='$got'"
}

# The 10% that cannot be typed must carry the VALUE and must NOT invent a type.
# Both halves matter: a blank signature is the defect, and a guessed 'Integer'
# would be worse than blank because nothing downstream could tell it was a guess.
$derived = SigOf 'Derived'
Check 'Derived (non-inferable expression) carries its value' ($derived -eq '= MaxItems * 2') "got='$derived'"
Check 'Derived does not invent a type'                       ($derived -notmatch '^\s*\w+\s*=') "got='$derived'"

# ---- THE POPUP -------------------------------------------------------------
$lines = [System.IO.File]::ReadAllLines($File)
$uri   = 'file:///' + ($File -replace '\\', '/')

function CompletionItems([int]$line, [int]$col) {
  $m  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
  $m += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
  $m += Frame @{ jsonrpc='2.0'; id=2; method='textDocument/completion';
                 params=@{ textDocument=@{ uri=$uri }; position=@{ line=$line; character=$col } } }
  $m += Frame @{ jsonrpc='2.0'; id=3; method='shutdown'; params=@{} }
  $inF  = Join-Path $WorkDir 'in.txt'
  $outF = Join-Path $WorkDir 'out.txt'
  [System.IO.File]::WriteAllText($inF, $m, (New-Object System.Text.ASCIIEncoding))
  Start-Process $Exe -ArgumentList @('lsp', '--db', $Db) -WorkingDirectory $WorkDir `
    -RedirectStandardInput $inF -RedirectStandardOutput $outF `
    -RedirectStandardError (Join-Path $WorkDir 'err.txt') -NoNewWindow -Wait | Out-Null
  $items = @()
  foreach ($mm in [regex]::Matches([System.IO.File]::ReadAllText($outF), '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $mm.Value.Trim() | ConvertFrom-Json } catch { continue }
    if ($o.id -eq 2 -and $null -ne $o.result) { $items = @($o.result.items) }
  }
  return $items
}
function DetailIn($items, [string]$label) {
  $it = $items | Where-Object { $_.label -eq $label } | Select-Object -First 1
  if ($null -eq $it) { return '<absent>' }
  return [string]$it.detail
}

# Probe A -- MEMBER completion on `T.`, MID-LINE with text after the caret.
# The editing shape matters: every completion fixture before session 29 put the
# dot at end of line, which structurally hid a caret off-by-one.
$lnA = -1
for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Contains('T.DoIt;')) { $lnA = $i; break } }
Check 'located the member probe' ($lnA -ge 0) "line0=$lnA"
$itemsA = @()
if ($lnA -ge 0) { $itemsA = CompletionItems $lnA ($lines[$lnA].IndexOf('.') + 1) }
Check 'the member completion answered' ($itemsA.Count -gt 0) "count=$($itemsA.Count)"

Write-Host ''
Write-Host 'THE POPUP: a class const describes itself end to end' -ForegroundColor Cyan
$vDetail = DetailIn $itemsA 'Version'
Check 'a class const reaches the popup with type and value' ($vDetail -eq 'Integer = 3') "detail='$vDetail'"

# Probe B -- GLOBAL PREFIX completion, mid-line, with a real prefix typed.
# The prefix has to be one that can actually OFFER the symbols being asserted:
# an earlier draft of this guard probed after `M`, which cannot match a type
# name, so every type assertion read '<absent>' and the two "stays blank"
# controls passed for the wrong reason -- absent is not blank.
$lnB = -1
for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Contains('T := TThing.Create')) { $lnB = $i; break } }
Check 'located the T-prefix probe' ($lnB -ge 0) "line0=$lnB"
$itemsB = @()
if ($lnB -ge 0) { $itemsB = CompletionItems $lnB ($lines[$lnB].IndexOf('TThing') + 1) }
Check 'the T-prefix completion answered' ($itemsB.Count -gt 0) "count=$($itemsB.Count)"

# Probe C -- the interface, which no `T` prefix can reach.
$lnC = -1
for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Contains('Supports(T, IFoo)')) { $lnC = $i; break } }
Check 'located the I-prefix probe' ($lnC -ge 0) "line0=$lnC"
$itemsC = @()
if ($lnC -ge 0) { $itemsC = CompletionItems $lnC ($lines[$lnC].IndexOf('IFoo') + 1) }
Check 'the I-prefix completion answered' ($itemsC.Count -gt 0) "count=$($itemsC.Count)"

Write-Host ''
Write-Host 'THE POPUP: a type kind describes itself' -ForegroundColor Cyan
foreach ($t in @(
  @{ n = 'TThing'; want = 'TBase'               ; note = 'class with an ancestor' },
  @{ n = 'TState'; want = 'sIdle, sBusy, sDone' ; note = 'enum members'           }
)) {
  $got = DetailIn $itemsB $t.n
  Check ("{0} ({1})" -f $t.n, $t.note) ($got -eq $t.want) "want='$($t.want)' got='$got'"
}
$ifoo = DetailIn $itemsC 'IFoo'
Check 'IFoo (interface parent)' ($ifoo -eq 'IInterface') "want='IInterface' got='$ifoo'"

# CONTROL: an absent fact must stay absent. A bare `TBase = class` has no
# declared ancestor and a record has none at all -- reporting 'TObject' would be
# an invention, and the popup draws whatever is here after a colon, so an
# invented value is indistinguishable from an indexed one.
Write-Host ''
Write-Host 'CONTROLS: nothing invented, nothing lost' -ForegroundColor Cyan
# '<absent>' would satisfy a bare -eq '' test by accident, so assert the symbol
# was OFFERED first -- absent is not blank, and only one of the two is the claim.
foreach ($b in @('TBase', 'TRec')) {
  $got = DetailIn $itemsB $b
  Check ("CONTROL: {0} was offered at all" -f $b) ($got -ne '<absent>') "detail='$got'"
  Check ("CONTROL: {0} invents no ancestor"  -f $b) ($got -eq ''        ) "detail='$got'"
}

# ---- THE SAME FACTS, THROUGH THE HOVER ------------------------------------
# Found in a live IDE 2026-08-24: hovering an enum showed only
# `enum FileLockInfo.TRmAppType` -- no members -- while the completion popup
# listed them correctly. The type-kind description had been built inside
# MakeCompletionItem, so it reached exactly one of the two surfaces.
#
# DRagLint.Query.HoverModel's own header says why that was the wrong shape:
# copying an assembly creates a second definition of what a hover says about a
# symbol, and the two drift the first time either is touched. So the fix is ONE
# shared describer called by both, and this block is what stops them separating
# again -- it asserts the hover reports the SAME strings the popup does.
function HoverModelAt([int]$line, [int]$col) {
  $m  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
  $m += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
  $m += Frame @{ jsonrpc='2.0'; id=2; method='draglint/hoverBundle';
                 params=@{ textDocument=@{ uri=$uri }; position=@{ line=$line; character=$col } } }
  $m += Frame @{ jsonrpc='2.0'; id=3; method='shutdown'; params=@{} }
  $inF  = Join-Path $WorkDir 'hin.txt'
  $outF = Join-Path $WorkDir 'hout.txt'
  [System.IO.File]::WriteAllText($inF, $m, (New-Object System.Text.ASCIIEncoding))
  Start-Process $Exe -ArgumentList @('lsp', '--db', $Db) -WorkingDirectory $WorkDir `
    -RedirectStandardInput $inF -RedirectStandardOutput $outF `
    -RedirectStandardError (Join-Path $WorkDir 'herr.txt') -NoNewWindow -Wait | Out-Null
  foreach ($mm in [regex]::Matches([System.IO.File]::ReadAllText($outF), '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $mm.Value.Trim() | ConvertFrom-Json } catch { continue }
    if ($o.id -eq 2 -and $null -ne $o.result) { return $o.result.model }
  }
  return $null
}
function LineOf([string]$needle) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Contains($needle)) { return $i } }
  return -1
}

Write-Host ''
Write-Host 'THE HOVER: the same facts, or the two surfaces have drifted' -ForegroundColor Cyan
foreach ($h in @(
  @{ decl = 'TState = ('        ; sym = 'TState'; want = 'sIdle, sBusy, sDone'; note = 'enum members'  },
  @{ decl = 'TThing = class('   ; sym = 'TThing'; want = 'TBase'              ; note = 'class ancestor'},
  @{ decl = 'IFoo = interface(' ; sym = 'IFoo'  ; want = 'IInterface'         ; note = 'interface parent' }
)) {
  $ln = LineOf $h.decl
  if ($ln -lt 0) { Check ("located the {0} declaration" -f $h.sym) $false; continue }
  $mdl = HoverModelAt $ln ($lines[$ln].IndexOf($h.sym) + 1)
  $got = if ($null -eq $mdl) { '<no model>' } else { [string]$mdl.signature }
  Check ("HOVER: {0} ({1})" -f $h.sym, $h.note) ($got -eq $h.want) "want='$($h.want)' got='$got'"
}

# CONTROL: the hover must not invent what the popup does not. Same claim, other
# direction -- a describer that returns something for everything would satisfy
# the three assertions above and be wrong here.
$lnB2 = LineOf 'TBase = class'
if ($lnB2 -ge 0) {
  $mdlB = HoverModelAt $lnB2 ($lines[$lnB2].IndexOf('TBase') + 1)
  $gotB = if ($null -eq $mdlB) { '<no model>' } else { [string]$mdlB.signature }
  Check 'CONTROL: HOVER invents no ancestor for a bare class' ($gotB -eq '') "signature='$gotB'"
}

# CONTROL: the previous guard's win must survive. The cheapest wrong way to make
# the assertions above pass is to start falling back to the qualified name again
# for anything blank -- which is exactly the defect P3 fixed.
$doIt = DetailIn $itemsA 'DoIt'
Check 'CONTROL: a parameterless procedure still reports no qualified name' ($doIt -notmatch '\.DoIt') "detail='$doIt'"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
