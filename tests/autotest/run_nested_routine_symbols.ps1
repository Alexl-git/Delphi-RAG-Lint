<#
  run_nested_routine_symbols.ps1 -- a NESTED routine is a symbol, qualified by
  its enclosing routine.

  WHY (the gap, logged in stats\draglint-gaps.log as class `unsupported`)
  --------------------------------------------------------------------------------
  `drag-lint query --name EmitTagged` returns 0 exact matches for a real function
  at src\doc\DRagLint.Doc.Regions.pas:1882, because it is declared inside another
  routine. The parser has always WALKED nested routines (at RoutineDepth > 0) to
  collect their references -- that was a deliberate earlier fix -- but emitted no
  SYMBOL for them, so they are invisible to query / find-callers / the call
  resolver.

  On YADF this is not a curiosity. 4,005 unresolved call refs name no symbol
  anywhere in the index, and two of the loudest -- StartsWordCI (93 refs) and
  EndsWordCI (62) -- are nested routines.

  WHY THE QUALIFIED NAME IS THE POINT, NOT THE SYMBOL
  --------------------------------------------------------------------------------
  YADF.Layout.pas declares StartsWordCI THREE times (lines 1925, 2351, 2900),
  each local to a DIFFERENT enclosing routine, with different parameter names.
  They are three distinct routines that happen to share a name, and the compiler
  tells them apart by scope: an unqualified identifier resolves innermost-first,
  so each call site sees only its own. A flat name-keyed symbol cannot represent
  that -- only Unit.Outer.Nested can. Assertion 2 is that case, and it is the one
  that would silently "pass" under a naive implementation that emits one symbol
  and lets the second overwrite it.

  THE SAFETY PROPERTY (assertion 4)
  --------------------------------------------------------------------------------
  A nested routine is NOT public API and must never be documented by the batch
  modes. That falls out of DRagLint.Doc.Batch's existing public-surface gate
  (Section='interface'), since a nested routine is implementation-section -- but
  it falls out only if the emitted symbol carries the right Section, so it is
  asserted rather than assumed. `document --qname` deliberately bypasses that
  gate, so documenting one ON PURPOSE stays possible.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP 'draglint_nestedsyms'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# TwinHost/TwinGuest each declare a nested SharedName -- the YADF StartsWordCI
# shape. OuterOne's nested Helper is called from its own body, so the ref exists
# and a resolver can later bind it.
Write-Ascii (Join-Path $scratch 'nestsyms.pas') @'
unit nestsyms;

interface

function OuterOne(const A: string): Integer;
procedure TwinHost;
procedure TwinGuest;

implementation

function OuterOne(const A: string): Integer;

  function NestedHelper(const S: string): Integer;
  begin
    Result := Length(S);
  end;

begin
  Result := NestedHelper(A);
end;

procedure TwinHost;

  function SharedName(const HostArg: string): Boolean;
  begin
    Result := HostArg <> '';
  end;

begin
  if SharedName('x') then Exit;
end;

procedure TwinGuest;

  function SharedName(const GuestArg: Integer): Boolean;
  begin
    Result := GuestArg > 0;
  end;

begin
  if SharedName(1) then Exit;
end;

end.
'@

$db = Join-Path $scratch 'nestsyms.sqlite'

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db --quiet 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  function Get-Rows([string]$name) {
    $j = (& $exePath query --name $name --db $db --json 2>$null) -join "`n"
    try { return @($j | ConvertFrom-Json) } catch { return @() }
  }

  # --- 1. the nested routine is a symbol at all ------------------------------
  $nh = Get-Rows 'NestedHelper'
  Check 'NestedHelper is indexed as a symbol' ($nh.Count -ge 1) "rows=$($nh.Count)"
  if ($nh.Count -ge 1) {
    Check 'NestedHelper is qualified by its enclosing routine (nestsyms.OuterOne.NestedHelper)' `
      ($nh[0].qualified_name -match '(?i)nestsyms\.OuterOne\.NestedHelper') "qname=$($nh[0].qualified_name)"
    Check 'NestedHelper is a routine kind' ($nh[0].kind -match '(?i)function|procedure') "kind=$($nh[0].kind)"
  }

  # --- 2. THE DISCRIMINATOR: two same-named nested routines stay distinct ----
  $tw = Get-Rows 'SharedName'
  Check 'both SharedName routines are indexed, not collapsed into one' ($tw.Count -eq 2) "rows=$($tw.Count)"
  if ($tw.Count -eq 2) {
    $q = @($tw | ForEach-Object { $_.qualified_name }) | Sort-Object
    Check 'their qualified names name their DIFFERENT enclosing routines' `
      (($q -join '|') -match '(?i)TwinGuest\.SharedName.*TwinHost\.SharedName') "qnames=$($q -join ', ')"
  }

  # --- 3. the enclosing routines are unharmed --------------------------------
  Check 'OuterOne is still indexed exactly once' ((Get-Rows 'OuterOne').Count -eq 1)

  # --- 4. SAFETY: batch documentation must not touch a nested routine --------
  # Asserted as the public-surface COUNT, not as "the name never appears": the
  # names legitimately appear in their ENCLOSING routine's `Calls:` fact, which
  # is correct output and not a documentation of the nested routine. declCount is
  # exactly what Doc.Batch's Section='interface' gate admits -- the three
  # interface decls -- so a nested routine leaking into the public surface shows
  # up here as 4, 5 or 6 and nowhere else.
  $docJson = (& $exePath document --unit (Join-Path $scratch 'nestsyms.pas') --db $db --json 2>$null) -join "`n"
  $dc = -1; try { $dc = ([int](($docJson | ConvertFrom-Json).declCount)) } catch { }
  Check 'document --unit public surface is still exactly the 3 interface decls' ($dc -eq 3) `
    "declCount=$dc -- a nested routine leaking into the public surface raises this"
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
