<#
  run_context_class_qualified_name.ps1 --
  `context --task "modify Class.Member"` must RESOLVE when exactly one symbol's
  qualified name ends with that dotted suffix.

  THE DEFECT (INBOX 2026-09-17, section 1). Three spellings of one symbol:
    modify ApplyInheritedFieldFacts                              -> bundle
    modify DRagLint.Core.Indexer.TIndexer.ApplyInheritedFieldFacts -> bundle
    modify TIndexer.ApplyInheritedFieldFacts                     -> No symbol matched
  The middle form -- the one a reader naturally types after seeing a class
  surface -- resolved LESS readily than either the bare member or the full
  unit-qualified name. Bundler.pas resolved a bare name when unambiguous and a
  full qname when present, and had no step in between: anything with a '.'
  that was not the whole qname was a miss.

  THE POLICY THIS EXTENDS, NOT REPLACES. A bare name resolves ONLY when
  unambiguous; an ambiguous one returns nothing on purpose, because a
  confidently-wrong bundle is worse than an empty one. The suffix step keeps
  that rule: `TFoo.Bar` declared in two units still declines (T2).

  SEGMENT-ALIGNED, NOT SUBSTRING. `orker.UniqueMethod` is a textual suffix of
  `uA.TWorker.UniqueMethod` and must NOT resolve (T5); the match is on whole
  '.'-separated segments. Generic lists are stripped per segment, because
  symbols are stored under BARE names since schema v23 (T4).

  House style follows run_context_bare_name_body.ps1, which pins the sibling
  bare-name rule. Run from any CWD, pwsh 7. Builds its own fixture; touches no
  shared index.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_context_class_qualified"
)
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function Write-Ascii($p,$t){ [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Path $src -Force | Out-Null

# TWorker.UniqueMethod exists ONCE (uA) -- the class-qualified form must resolve.
# TTwin.Shared exists in BOTH units -- the class-qualified form is ambiguous and
# must decline exactly as an ambiguous bare name does.
# TBox<T>.Put carries a generic list -- the input must be stripped per segment.
Write-Ascii (Join-Path $src 'uA.pas') @"
unit uA;

interface

type
  TWorker = class(TObject)
  public
    function UniqueMethod(const AMask: string): Integer;
  end;

  TTwin = class(TObject)
  public
    function Shared: Integer;
  end;

  TBox<T> = class(TObject)
  public
    procedure Put(const AItem: T);
  end;

implementation

function TWorker.UniqueMethod(const AMask: string): Integer;
var
  Scratch: Integer;
begin
  Scratch := Length(AMask);
  if Scratch > 3 then
    Scratch := Scratch * 2;
  Result := Scratch;
end;

function TTwin.Shared: Integer;
begin
  Result := 1;
end;

procedure TBox<T>.Put(const AItem: T);
var
  Marker: Integer;
begin
  Marker := 7;
  if Marker > 0 then
    Marker := Marker - 1;
end;

end.
"@

Write-Ascii (Join-Path $src 'uB.pas') @"
unit uB;

interface

type
  TTwin = class(TObject)
  public
    function Shared: Integer;
  end;

implementation

function TTwin.Shared: Integer;
begin
  Result := 2;
end;

end.
"@

$db = Join-Path $WorkDir 'fx.sqlite'
& $exePath index $src --db $db 2>&1 | Out-Null
Check 'V the fixture index was built' (Test-Path $db) $db

# The call operator, NOT Start-Process -ArgumentList -- see
# run_context_bare_name_body.ps1 for the false reading that cost a diagnosis.
# stdout AND stderr are captured: the "No symbol matched" line and the exit
# code are both part of the contract under test.
function Bundle([string]$Task) {
  $script:lastExit = 0
  $out = ((& $exePath context --task $Task --db $db --format markdown 2>&1) -join "`r`n")
  $script:lastExit = $LASTEXITCODE
  return $out
}

# ---- P1/P2 POSITIVE CONTROLS ------------------------------------------------
$qual = Bundle 'modify uA.TWorker.UniqueMethod'
Check 'P1 POSITIVE CONTROL the unit-qualified name produces an Impl slice with the body' `
      (($qual -match '## Impl slice') -and ($qual -match 'Scratch')) `
      "the qualified bundle has no body, so T1 would prove nothing. Got $($qual.Length) bytes."
$bare = Bundle 'modify UniqueMethod'
Check 'P2 POSITIVE CONTROL the bare name still resolves (the sibling rule is alive)' `
      (($bare -match 'uA\.TWorker\.UniqueMethod') -and ($bare -match 'Scratch')) `
      'the bare-name fallback is broken; this guard cannot tell a new miss from an old one'

# ---- T1: the defect ---------------------------------------------------------
$cq = Bundle 'modify TWorker.UniqueMethod'
Check 'T1 a UNIQUE Class.Member suffix resolves (exit 0, no "No symbol matched")' `
      (($script:lastExit -eq 0) -and -not ($cq -match 'No symbol matched')) `
      "exit=$($script:lastExit): $($cq.Substring(0, [Math]::Min(120, $cq.Length)))"
Check 'T1b the header names the RESOLVED qualified name uA.TWorker.UniqueMethod' `
      ($cq -match '# Context bundle: modify uA\.TWorker\.UniqueMethod') `
      'the header does not say which symbol was chosen -- the reader loses their evidence'
Check 'T1c the class-qualified bundle carries the routine BODY' `
      ($cq -match 'Scratch') `
      'resolved but the body is missing -- the bare-name-body defect all over again'

# ---- T2: the policy that must NOT regress -----------------------------------
$amb = Bundle 'modify TTwin.Shared'
Check 'T2 an AMBIGUOUS Class.Member (declared in two units) still declines with exit 1' `
      (($script:lastExit -eq 1) -and ($amb -match 'No symbol matched: TTwin\.Shared')) `
      "exit=$($script:lastExit): $($amb.Substring(0, [Math]::Min(120, $amb.Length)))"
Check 'T2b and the ambiguous form emits no Impl slice (no confidently-wrong bundle)' `
      (-not ($amb -match '## Impl slice')) `
      'an ambiguous Class.Member now picks one symbol and emits its body'
$ambQual = Bundle 'modify uB.TTwin.Shared'
Check 'T2c CONTROL the same member resolves once the unit disambiguates it' `
      (($script:lastExit -eq 0) -and ($ambQual -match 'uB\.TTwin\.Shared')) `
      "exit=$($script:lastExit)"

# ---- T3: a bare TYPE-shaped suffix has nothing to do with this; a bare class
#          name is still the bare-name rule (unchanged) ------------------------
$cls = Bundle 'modify TWorker'
Check 'T3 CONTROL a bare unique CLASS name still resolves under the bare-name rule' `
      (($script:lastExit -eq 0) -and ($cls -match 'uA\.TWorker')) `
      "exit=$($script:lastExit)"

# ---- T4: generic list on the input is stripped per segment ------------------
$gen = Bundle 'modify TBox<T>.Put'
Check 'T4 a Class<T>.Member suffix resolves to the BARE-named stored symbol uA.TBox.Put' `
      (($script:lastExit -eq 0) -and ($gen -match 'uA\.TBox\.Put') -and ($gen -match 'Marker')) `
      "exit=$($script:lastExit): $($gen.Substring(0, [Math]::Min(120, $gen.Length)))"

# ---- T5: segment-aligned, not substring -------------------------------------
$sub = Bundle 'modify orker.UniqueMethod'
Check 'T5 a textual suffix that is NOT segment-aligned does NOT resolve' `
      (($script:lastExit -eq 1) -and ($sub -match 'No symbol matched: orker\.UniqueMethod')) `
      "exit=$($script:lastExit): a substring match would hand back uA.TWorker.UniqueMethod for a name nobody typed"

# ---- T6: a suffix naming nothing still says so ------------------------------
$none = Bundle 'modify TWorker.NoSuchMember'
Check 'T6 CONTROL an unknown Class.Member still exits 1 with the "No symbol matched" line' `
      (($script:lastExit -eq 1) -and ($none -match 'No symbol matched: TWorker\.NoSuchMember')) `
      "exit=$($script:lastExit)"

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
