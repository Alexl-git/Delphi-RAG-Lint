<#
  run_doc_intrinsics_not_calls.ps1 -- COMPILER INTRINSICS are not collaborators
  and do not belong in a "Calls:" fact line.

  WHY
  --------------------------------------------------------------------------------
  The Calls list is built from two sources: resolved call_edges (rendered
  qualified) and a body-scan fallback for bare names that did not resolve.
  Intrinsics can never resolve -- the compiler recognizes them by name and
  compiles them inline, so they are symbols in no index -- and they therefore all
  landed in the fallback bucket. A routine that increments a counter and walks an
  array rendered:

      /// Calls: Assigned, High, Inc, intr.Helper, Low, SetLength

  Five of six entries carry no information about what the routine does, and the
  one real callee is buried among them. Inc and SetLength are not collaborators;
  they are syntax.

  THE SAFETY ARGUMENT, AND THE ASSERTION THAT PINS IT
  --------------------------------------------------------------------------------
  Dropping a name is only safe if it cannot drop a REAL callee. A project may
  legitimately declare a routine called Abs, High or Low. It stays visible,
  because the filter applies ONLY to the unresolved bare-name fallback: a real
  project routine resolves through call_edges and is added QUALIFIED by step 1,
  before the filter is reached.

  TMath.Run is that case, and its assertion is the load-bearing one here. It
  calls Abs -- a name on the intrinsic list -- which binds to the METHOD
  TMath.Abs. If the filter is ever moved earlier (into CollectCallIdents, or
  ahead of the resolved-edge merge) this is what reddens, and nothing else would.

  The name list is deliberately restricted to names virtually never user-defined,
  which is why Copy / Insert / Delete / Pos are absent from it despite being
  intrinsics. Widening it is not a free improvement.

  CONTROL AGAINST OVER-FILTERING
  --------------------------------------------------------------------------------
  'no intrinsics in the line' is trivially satisfied by emitting no line at all,
  or by an empty bucket. NotAnywhereDeclared is a bare call to a routine declared
  nowhere: not intrinsic, never resolvable, and it MUST survive. It is what tells
  "intrinsics were filtered" apart from "the fallback bucket was emptied".

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP ('draglint_doc_intrinsics_' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

Write-Ascii (Join-Path $scratch 'intr.pas') @'
unit intr;

interface

type
  TMath = class
  public
    function Abs(const A: Integer): Integer;
    function Run: Integer;
  end;

function Tally(const AItems: array of Integer): Integer;
procedure Helper;

implementation

procedure Helper;
begin
end;

function TMath.Abs(const A: Integer): Integer;
begin
  Result:= A;
end;

function TMath.Run: Integer;
begin
  Result:= Abs(1);
end;

function Tally(const AItems: array of Integer): Integer;
var
  I  : Integer;
  Buf: string ;
begin
  Result:= 0;
  SetLength(Buf, 10);
  for I:= Low(AItems) to High(AItems) do
    Inc(Result, AItems[I]);
  Helper;
  NotAnywhereDeclared(3);
  if Assigned(Buf) then Exit;
end;

end.
'@

$db = Join-Path $scratch 'i.sqlite'

function Get-CallsLine([string]$qname) {
  $out = (& $exePath document --qname $qname --db $db 2>$null) -join "`n"
  $l = ($out -split "`r?`n" | Where-Object { $_ -match 'Calls:' } | Select-Object -First 1)
  if ($null -eq $l) { return '' }
  return $l.Trim()
}

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db --quiet 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  $tally = Get-CallsLine 'intr.Tally'
  Write-Host ("  Tally    -> " + $tally) -ForegroundColor DarkGray

  # --- CONTROL FIRST: the line exists and the fallback bucket is not empty ----
  # Asserted before the absence checks, because every absence check below is
  # trivially true over a line that was never emitted.
  Check 'CONTROL: a Calls: line was rendered for Tally' ($tally -ne '') $tally
  Check 'CONTROL: the real callee intr.Helper is listed' ($tally -match 'intr\.Helper') $tally
  Check 'CONTROL: a NON-intrinsic unresolved bare call still survives the filter' `
    ($tally -match 'NotAnywhereDeclared') $tally

  # --- the intrinsics are gone ----------------------------------------------
  foreach ($nm in @('Assigned','High','Low','Inc','SetLength')) {
    # \b-anchored so 'Low' cannot be matched inside another entry's text.
    Check "intrinsic '$nm' is NOT listed as a callee" (-not ($tally -match "\b$nm\b")) $tally
  }

  # --- THE SAFETY PIN -------------------------------------------------------
  # A project routine whose NAME is on the intrinsic list must still be listed,
  # because it RESOLVED and is added qualified before the filter applies.
  $run = Get-CallsLine 'intr.TMath.Run'
  Write-Host ("  TMath.Run-> " + $run) -ForegroundColor DarkGray
  Check 'SAFETY: a resolved PROJECT routine named Abs is still listed (qualified)' `
    ($run -match 'intr\.TMath\.Abs') $run
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
