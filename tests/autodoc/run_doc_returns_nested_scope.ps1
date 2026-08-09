<#
  run_doc_returns_nested_scope.ps1 -- '<returns>Observed:' names what the
  DOCUMENTED routine returns, never what its NESTED routines return.

  THE BUG (PLAN-autodoc-phaseC-2026-08-09, item B3; filed by YADF 2026-08-07)
  --------------------------------------------------------------------------------
  YADF.Layout.pas:101, on `function FormatSource(...): string`:

      /// <returns>Observed: Length(InlineRenderRange(Tokens, ...)); '';
      ///          Result + S[i]; Child; nil; True.</returns>

  FormatSource returns a STRING. Every one of those expressions belongs to one of
  the 15 routines nested inside its 603-line implementation -- an Integer, a
  TGroup, nil, a Boolean. The reader is told a string function returns five
  things it cannot return.

  MaskNestedRoutines already exists and already blanks nested scopes from all
  three mined views, so this is NOT a missing feature -- it is a masking pass
  that does not fire on this shape. The fixture below is built to find WHICH
  shape: nested routines declared before the main `begin` (Delphi's only legal
  position), several of them in sequence, one nested inside another, one with a
  `case`/`try` block whose `end` tokens the depth counter must not confuse with
  the routine's own, and a FORWARD-declared nested routine whose header appears
  twice.

  The control matters as much as the assertions: the OUTER routine's own returns
  must still be mined. A mask that swallowed the whole body would empty the tag
  and pass any "no nested expression appears" check on its own.

  WHAT THIS DOES *NOT* EXPLAIN -- and the correction it forces (PHASE C)
  --------------------------------------------------------------------------------
  FormatSource emits NO <returns> today, and that is NOT a residual masking gap.
  Its own body -- everything after its `begin` at YADF.Layout.pas:5441 -- runs a
  ~22-line pipeline of `Result:= SomeStage(Result)`. Result on the RHS is exactly
  what HasResultMutation detects, and it is asked of the DOCUMENTED routine's own
  code, so it fires no matter how perfectly the nested scopes are masked. Under
  the miner's "absence over wrong" policy that routine can never carry a
  <returns>. Any future report that reads its silence as a mask failure is
  reading the wrong cause.

  The mutation shape IS covered here now (InnerAccum), because it was the one
  nested form no fixture exercised: every other nested routine below does a
  whole-Result ASSIGNMENT, which never reaches HasResultMutation at all.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-returns-nested"
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

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# Every NESTED return value is a distinctive token so a leak is unambiguous:
# NestedInt / NestedBool / NestedPtr / NestedDeep / NestedCase / NestedFwd.
# The outer routine returns OuterValue and nothing else.
Write-Ascii (Join-Path $WorkDir 'nested.pas') @'
unit nested;

interface

function Outer(const ASeed: string): string;

implementation

function Outer(const ASeed: string): string;
var
  LTemp: Integer;

  function InnerInt: Integer;
  begin
    Result := NestedInt;
  end;

  function InnerBool: Boolean;
  begin
    Result := NestedBool;
  end;

  function InnerWithNested: Pointer;

    function DeepOne: Pointer;
    begin
      Result := NestedDeep;
    end;

  begin
    Result := NestedPtr;
    if DeepOne = nil then
      Result := NestedPtr;
  end;

  function InnerCase(const AK: Integer): string;
  begin
    case AK of
      0: Result := NestedCase;
    else
      Result := NestedCase;
    end;
    try
      Result := NestedCase;
    finally
      LTemp := 0;
    end;
  end;

  function InnerForward: string; forward;

  function InnerForward: string;
  begin
    Result := NestedFwd;
  end;

  // v(PHASE C): a nested routine that MUTATES Result -- Result on the RHS of
  // its own assignment -- rather than merely assigning it. Every other nested
  // routine above does a whole-Result assignment, which never reaches
  // HasResultMutation, so this shape was entirely uncovered.
  //
  // It is the YADF.Layout.CurrentLineLeadingWS shape (YADF.Layout.pas:5089,
  // `Result:= Result + S[i]`), and it fails DESTRUCTIVELY: the miner asks
  // HasResultMutation of the MASKED code-only view, so a mask that leaks here
  // does not add a wrong value -- it DELETES the outer <returns> outright,
  // because the policy is absence over wrong. The 'OuterValue IS reported'
  // control below is the assertion that catches it; a leak shows up there as
  // silence, which is indistinguishable from "nothing to say" without it.
  function InnerAccum(const S: string): string;
  var
    j: Integer;
  begin
    Result := NestedAccum;
    for j := 1 to Length(S) do
      Result := Result + S[j];
  end;

begin
  LTemp := InnerInt + Length(InnerAccum(ASeed));
  if InnerBool then
    Result := OuterValue
  else
    Result := OuterValue;
end;

end.
'@

$db = Join-Path $WorkDir 'nested.sqlite'
& $Exe index $WorkDir --db $db --quiet 2>&1 | Out-Null

$out = & $Exe document --qname 'nested.Outer' --db $db 2>&1 | Out-String
$ret = ($out -split "`r?`n" | Where-Object { $_ -match '<returns>' }) -join ' '
Write-Host "  rendered: $($ret.Trim())" -ForegroundColor DarkGray
Write-Host ''

Write-Host 'No nested routine''s return value leaks into the outer <returns>' -ForegroundColor Cyan
foreach ($leak in 'NestedInt','NestedBool','NestedPtr','NestedDeep','NestedCase','NestedFwd','NestedAccum') {
  Check "$leak does not appear" (-not ($ret -match $leak))
}

Write-Host ''
Write-Host 'Control -- the outer routine''s OWN return is still mined' -ForegroundColor Cyan
Check 'OuterValue IS reported' ($ret -match 'OuterValue') `
  'else the mask swallowed the whole body and the checks above pass vacuously'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
