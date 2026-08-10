<#
  run_doc_ctor_bodyless.ps1 -- two doc-drift SCOPE fixes, and the controls that
  prove neither one disabled the rule it narrows.

  WHY
  --------------------------------------------------------------------------------
  Both bugs are the house pattern: a CHECKER whose fact scope is narrower than
  the contract it grades, so it reports the gap between itself and the writer
  instead of reporting the code.

  (1) A CONSTRUCTOR IS NOT A FUNCTION WITH A MISSING <returns>.
      TDocDrift counted skConstructor as "has a return value", so every
      documented constructor drew `function returns a value but has no
      <returns> tag`. But a constructor declares NO return type, so
      Facts.ReturnType is empty, so the writer emits no <returns> -- and no
      `--apply` run could ever clear the finding. It was unsatisfiable by
      construction: 7 of drag-lint's own 13 residual doc-drift findings, every
      one of them a constructor.

      OWNER RULING (2026-08-10): stop demanding <returns> on a constructor, and
      instead have the engine SAY `constructor` in the generated documentation,
      with the linter verifying that instead. The marker goes in the managed
      facts block beside `abstract` / `virtual` -- the one region the engine
      fully owns and already regenerates -- so it self-heals through the normal
      `--apply` path rather than needing a second ownership rule.

  (2) A BODYLESS DECLARATION HAS NO BODY TO GRADE.
      `documented <exception cref="X"> but the body never raises it` was fired
      at INTERFACE METHODS. TDocFactsBuilder only scans for raises when
      ASym.ImplStartLine > 0, so for an interface method Facts.Raises is empty
      BY CONSTRUCTION -- the rule was not observing an absent raise, it was
      observing that it never looked. An interface method's <exception> tag is
      the contract its IMPLEMENTORS must honour; it is the one place the tag is
      most correct and the rule punished exactly that.

  THE CONTROLS ARE THE LOAD-BEARING HALF
  --------------------------------------------------------------------------------
  Both fixes narrow a rule, and the cheapest way to make a narrowing "pass" is
  to narrow it to nothing. So this file pins the other side too: a real function
  with no <returns> must STILL be reported, and a routine WITH a body that
  documents an exception it never raises must STILL be reported. Without those
  two, deleting each rule outright would turn this file green.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP ('draglint_doc_ctorbody_' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
function Get-FileMd5([string]$p) { (Get-FileHash -Algorithm MD5 -Path $p).Hash }

$src = Join-Path $scratch 'ctorbody.pas'
$db  = Join-Path $scratch 'c.sqlite'

Write-Ascii $src @'
unit ctorbody;

interface

type
  IThing = interface
    /// <summary>Removes every row. Implementors talk to the database.</summary>
    /// <exception cref="EDatabaseError">Raised when the delete cannot be applied.</exception>
    function ClearAll: Integer;
  end;

  TThing = class(TInterfacedObject, IThing)
  public
    /// <summary>Builds an empty thing.</summary>
    constructor Create;
    destructor Destroy; override;
    function ClearAll: Integer;
    /// <summary>A real function, documented, with no returns tag.</summary>
    function Named: string;
    /// <summary>Documents an exception its body demonstrably never raises.</summary>
    /// <exception cref="ENeverRaised">Claimed by a human, raised by nobody.</exception>
    function Bogus: Integer;
  end;

implementation

constructor TThing.Create;
begin
  inherited Create;
end;

destructor TThing.Destroy;
begin
  inherited;
end;

function TThing.ClearAll: Integer;
begin
  Result:= 0;
end;

function TThing.Named: string;
begin
  Result:= 'x';
end;

function TThing.Bogus: Integer;
begin
  Result:= 1;
end;

end.
'@

# One doc-drift analysis for a single qualified name. Rows carry .kind/.detail
# -- DETAIL, not 'message': the lint-all JSON calls the text 'message' and this
# engine verb calls it 'detail', and reading the wrong one silently yields an
# array of nulls, which makes every "reports nothing" assertion pass VACUOUSLY.
# That is exactly how this test first went green against an unfixed engine.
function Get-Drift($qname) {
  $out = & $exePath doc-drift --qname $qname --db $db --json 2>$null
  $rows = @()
  foreach ($ln in $out) { $t = "$ln".Trim(); if ($t.StartsWith('{')) { $rows += ($t | ConvertFrom-Json) } }
  return ,$rows
}
function Messages($rows) { return @($rows | ForEach-Object { $_.detail }) }

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db --quiet 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  # =========================================================================
  # PHASE 1 -- grade the HAND-WRITTEN docs, BEFORE the engine completes them.
  #
  # Order is load-bearing. `document --apply` gives every function a
  # <returns>, so a control asserting "a real function with no <returns> is
  # still reported" can only be meaningful BEFORE that runs. Every decl in the
  # fixture carries a human <summary> so doc-drift grades it at all (it skips
  # undocumented declarations entirely, which would make each "reports
  # nothing" assertion below pass vacuously).
  # =========================================================================
  $ctor = Get-Drift 'ctorbody.TThing.Create'
  Check 'FIX 1: constructor draws NO "no <returns> tag" finding' `
    ((Messages $ctor | Where-Object { $_ -like '*no <returns> tag*' }).Count -eq 0) `
    ((Messages $ctor) -join ' | ')

  $iface0 = Get-Drift 'ctorbody.IThing.ClearAll'
  Check 'FIX 2: interface method draws NO "body never raises it" finding' `
    ((Messages $iface0 | Where-Object { $_ -like '*never raises it*' }).Count -eq 0) `
    ((Messages $iface0) -join ' | ')

  $named0 = Get-Drift 'ctorbody.TThing.Named'
  Check 'CONTROL: a real function with no <returns> is STILL reported' `
    ((Messages $named0 | Where-Object { $_ -like '*no <returns> tag*' }).Count -ge 1) `
    ((Messages $named0) -join ' | ')

  $bogus0 = Get-Drift 'ctorbody.TThing.Bogus'
  Check 'CONTROL: a routine WITH a body that never raises its documented cref is STILL reported' `
    ((Messages $bogus0 | Where-Object { $_ -like '*ENeverRaised*' }).Count -ge 1) `
    ((Messages $bogus0) -join ' | ')

  # =========================================================================
  # PHASE 2 -- the engine's own output, and the constructor marker it writes.
  # =========================================================================
  & $exePath document --unit $src --db $db --apply 2>$null | Out-Null
  Check 'document --apply exits 0' ($LASTEXITCODE -eq 0)
  $md5First = Get-FileMd5 $src
  $text = [IO.File]::ReadAllText($src)
  Write-Host '--- applied file ---' -ForegroundColor DarkGray
  Write-Host $text -ForegroundColor DarkGray

  # === FIX 1b: the engine SAYS "constructor" in the documentation it writes ===
  # Scoped to the constructor's own doc block, not the whole file: the word
  # appears in the source text `constructor TThing.Create` regardless, so a
  # file-wide match would pass without the engine having written anything.
  $lines   = [IO.File]::ReadAllLines($src)
  $ctorIdx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*constructor Create;\s*$') { $ctorIdx = $i; break } }
  Check 'SETUP: found the constructor declaration' ($ctorIdx -ge 0)
  $ctorDoc = ''
  if ($ctorIdx -gt 0) {
    for ($j = $ctorIdx - 1; $j -ge 0; $j--) {
      if ($lines[$j] -notmatch '^\s*///') { break }
      $ctorDoc = $lines[$j] + "`n" + $ctorDoc
    }
  }
  # The fixture hands the constructor a <summary>, deliberately: doc-drift only
  # grades DOCUMENTED declarations, so an undocumented constructor draws no
  # finding at all and every assertion below would pass against a broken engine.
  Check 'the constructor has a doc block' ($ctorDoc.Trim() -ne '') $ctorDoc
  Check 'and that block identifies it as a constructor' `
    ($ctorDoc -match '(?i)constructor') $ctorDoc

  # CONTROL: the marker is kind-selected, not sprayed on every member.
  $namedIdx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*function Named: string;\s*$') { $namedIdx = $i; break } }
  $namedDoc = ''
  if ($namedIdx -gt 0) {
    for ($j = $namedIdx - 1; $j -ge 0; $j--) {
      if ($lines[$j] -notmatch '^\s*///') { break }
      $namedDoc = $lines[$j] + "`n" + $namedDoc
    }
  }
  Check 'CONTROL: a plain function gets NO constructor marker' `
    (-not ($namedDoc -match '(?i)constructor')) $namedDoc

  Check 'the interface method keeps its hand-written <exception cref> verbatim' `
    ($text -match '<exception cref="EDatabaseError">Raised when the delete cannot be applied\.</exception>') $text

  # === idempotency ==========================================================
  & $exePath index $scratch --db $db --quiet 2>$null | Out-Null
  & $exePath document --unit $src --db $db --apply 2>$null | Out-Null
  Check 'IDEMPOTENT: reindex + a second --apply is byte-identical' `
    ((Get-FileMd5 $src) -eq $md5First) ("first=$md5First second=" + (Get-FileMd5 $src))

  # The constructor finding must stay gone after a second round-trip -- the
  # original bug was unsatisfiable ACROSS runs, so one run proves little.
  $ctor2 = Get-Drift 'ctorbody.TThing.Create'
  Check 'constructor is still clean after a second apply' `
    ((Messages $ctor2 | Where-Object { $_ -like '*no <returns> tag*' }).Count -eq 0) `
    ((Messages $ctor2) -join ' | ')

  Check 'every emitted /// line is 7-bit ASCII' `
    (@([IO.File]::ReadAllLines($src) | Where-Object { $_ -match '^\s*///' -and ($_.ToCharArray() | Where-Object { [int]$_ -gt 126 }) }).Count -eq 0)
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
