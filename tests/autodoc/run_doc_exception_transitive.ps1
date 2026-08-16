<#
  run_doc_exception_transitive.ps1 -- transitive <exception cref> resolution.

  INBOX-exception-cref-transitive-raise: ddExceptionNotRaised graded a routine
  against its OWN body only, so a one-line delegation that documents the
  exception its callee raises was reported as drift. FormsMap.pas:76 (the
  singular GenerateFormsCsv overload) was the worked example.

  The fix resolves ONE hop of callee and mines that callee's raises. Suppression
  requires a POSITIVELY mined raise; every unresolved case still reports.

  Fixture: fixtures\docdrift\transitive.pas.

    RED-A  Go        -- singular overload delegates to the array overload that
                        raises EBoom. The edge is AMBIGUOUS (overloads share a
                        qualified name), so a certain-edges-only fix does NOT
                        clear this one. Both overloads share the qname, and the
                        array overload never reported, so the whole qname must
                        go from 1 finding to 0.
    RED-B  ViaHelper -- delegates to a private helper; the edge is CERTAIN.

  The four controls are the point of this suite. A test that only asserted "the
  false finding is gone" would pass with the rule switched off entirely.

    CONTROL-1 StillWrong   -- documents ENever, which nothing raises. Fails if
                              the rule is weakened to the cheap "calls
                              something, raises nothing itself -> skip" carve-out.
    CONTROL-2 AncestorCref -- cref is the ancestor, callee raises the descendant;
                              exact-name matching must survive.
    CONTROL-3 Unresolved   -- only callee is RTL, unresolved here; absence of
                              information must not suppress.
    CONTROL-4 TwoHops      -- raise is two hops away; one hop is the bound.

  BASELINE against the UNFIXED exe (recorded 2026-08-16, before the fix landed):
    RED-A FAIL, RED-B FAIL, CONTROL-1..4 PASS.
  If a future change makes the controls fail, the rule has been gutted, not fixed.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docdrift\transitive.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_doctransitive'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'transitive.pas'
$db     = Join-Path $scratch 'transitive.sqlite'
Copy-Item $fixture $target -Force

# Parse the JSON-per-line output of `doc-drift --qname X --json`.
function Get-Drift($qname) {
  $out = & $exePath doc-drift --qname $qname --db $db --json 2>$null
  $rows = @()
  foreach ($ln in $out) {
    $t = $ln.Trim()
    if ($t.StartsWith('{')) { $rows += ($t | ConvertFrom-Json) }
  }
  return ,$rows
}
# True when an entry of kind $k is present whose detail mentions $typeName.
function HasEx($rows,$typeName) {
  foreach ($r in $rows) {
    if ($r.kind -eq 'ddExceptionNotRaised' -and $r.detail -match [regex]::Escape($typeName)) { return $true }
  }
  return $false
}
# True when NO ddExceptionNotRaised entry is present at all.
function LacksEx($rows) {
  foreach ($r in $rows) { if ($r.kind -eq 'ddExceptionNotRaised') { return $false } }
  return $true
}

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null

  # Sanity: the engine is actually running on this fixture. Without this, every
  # "Lacks" assertion below would pass vacuously on an empty result set.
  $sw = Get-Drift 'transitive.StillWrong'
  Check 'SANITY: engine produces findings for this fixture' ($sw.Count -ge 1)

  # --- RED-A: ambiguous overload delegation ---
  $go = Get-Drift 'transitive.Go'
  Check 'RED-A: Go -- no ddExceptionNotRaised (singular delegates to the raising overload)' (LacksEx $go)

  # --- RED-B: certain edge to a private helper ---
  $vh = Get-Drift 'transitive.ViaHelper'
  Check 'RED-B: ViaHelper -- no ddExceptionNotRaised (helper raises EBoom)' (LacksEx $vh)

  # --- CONTROL-1: the rule must STILL fire ---
  Check 'CONTROL-1: StillWrong -- ddExceptionNotRaised for ENever STILL reported' (HasEx $sw 'ENever')

  # --- CONTROL-2: exact-name matching preserved ---
  $ac = Get-Drift 'transitive.AncestorCref'
  Check 'CONTROL-2: AncestorCref -- ancestor cref STILL reported (no subtype match)' (HasEx $ac 'Exception')

  # --- CONTROL-3: unresolved callee must not suppress ---
  $un = Get-Drift 'transitive.Unresolved'
  Check 'CONTROL-3: Unresolved -- unresolved callee STILL reports EFoo (fail-safe)' (HasEx $un 'EFoo')

  # --- CONTROL-4: one hop is the bound ---
  $th = Get-Drift 'transitive.TwoHops'
  Check 'CONTROL-4: TwoHops -- two-hop raise STILL reported (depth bound holds)' (HasEx $th 'EBoom')
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
