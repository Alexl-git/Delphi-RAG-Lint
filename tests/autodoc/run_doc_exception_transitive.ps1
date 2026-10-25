<#
  run_doc_exception_transitive.ps1 -- transitive <exception cref> resolution.

  INBOX-exception-cref-transitive-raise: ddExceptionNotRaised graded a routine
  against its OWN body only, so a one-line delegation that documents the
  exception its callee raises was reported as drift. FormsMap.pas:76 (the
  singular GenerateFormsCsv overload) was the worked example.

  The fix walks resolved callees up to THREE hops (H2, 2026-10-25; it was one) and mines
  their raises. Suppression
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
    RED-C  TwoHops   -- raise two hops away (H2 2026-10-25: the bound is THREE hops).
    RED-D  ThreeHops -- raise exactly three hops away.
    CONTROL-4 FourHops     -- raise is four hops away; three hops is the bound.
    CONTROL-5 Ping         -- a Ping/Pong call cycle that raises nothing: the walk terminates
                              and the finding stays.

  Known OS-error raisers (owner ruling D2 a-narrow, 2026-10-25), fixture
  fixtures\docdrift\transitive_osraise.pas. RaiseLastOSError /
  RaiseLastWin32Error / Win32Check / CheckOSError are unresolved RTL calls in a
  project DB; the shared miner maps them to EOSError by call-name text.
    RED-E..H   bare, unit-qualified, Win32Check, CheckOSError -> no drift.
    CONTROL-6  OsNone      -- no raiser call: EOSError STILL reported.
    CONTROL-7  AbortCref   -- Abort is NOT in the table: EAbort STILL reported.
    CONTROL-8  TShadow.Run -- a RESOLVED member named Win32Check: still reported.
    WRITER-1   `document` writes the EOSError cref for a Win32Check caller.
    WRITER-C1  `document` writes no EAbort cref for an Abort caller.
  BASELINE 2026-10-25 against the unfixed exe: RED-E..H and WRITER-1 FAIL, the
  controls PASS.

  BASELINE against the UNFIXED exe (recorded 2026-08-16, before the fix landed):
    RED-A FAIL, RED-B FAIL, CONTROL-1..4 PASS.
  If a future change makes the controls fail, the rule has been gutted, not fixed.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
try {

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docdrift\transitive.pas')).Path
$osFixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docdrift\transitive_osraise.pas')).Path

$scratch = Join-Path C:\TEMP "draglint_doctransitive_$PID"
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

  # --- RED-C / RED-D: two and three hops are within the bound (H2, 2026-10-25) ---
  $th = Get-Drift 'transitive.TwoHops'
  Check 'RED-C: TwoHops -- no ddExceptionNotRaised (raise two hops down, within the bound)' (LacksEx $th)
  $h3 = Get-Drift 'transitive.ThreeHops'
  Check 'RED-D: ThreeHops -- no ddExceptionNotRaised (raise exactly three hops down)' (LacksEx $h3)

  # --- CONTROL-4: three hops is the bound ---
  $h4 = Get-Drift 'transitive.FourHops'
  Check 'CONTROL-4: FourHops -- four-hop raise STILL reported (depth bound holds)' (HasEx $h4 'EBoom')

  # --- CONTROL-5: a call cycle terminates and still reports ---
  $pp = Get-Drift 'transitive.Ping'
  Check 'CONTROL-5: Ping -- Ping/Pong cycle raises nothing, ENever STILL reported' (HasEx $pp 'ENever')

  # --- Known OS-error raisers (owner ruling D2 a-narrow, 2026-10-25) ---
  # Own unit, own folder, own DB: transitive.pas is the writer runner's human
  # fixture and must not gain declarations.
  $osDir = Join-Path $scratch 'os'
  New-Item -ItemType Directory -Path $osDir | Out-Null
  Copy-Item $osFixture (Join-Path $osDir 'transitive_osraise.pas') -Force
  $mainDb = $db; $db = Join-Path $scratch 'os.sqlite'
  try {
    & $exePath index $osDir --db $db 2>$null | Out-Null
    $c6 = Get-Drift 'transitive_osraise.OsNone'
    Check 'OS SANITY: engine produces findings for the OS fixture' ($c6.Count -ge 1)
    Check 'RED-E: OsBare -- RaiseLastOSError justifies cref EOSError' (LacksEx (Get-Drift 'transitive_osraise.OsBare'))
    Check 'RED-F: OsQualified -- System.SysUtils.RaiseLastOSError justifies it' (LacksEx (Get-Drift 'transitive_osraise.OsQualified'))
    Check 'RED-G: OsWin32 -- Win32Check justifies it' (LacksEx (Get-Drift 'transitive_osraise.OsWin32'))
    Check 'RED-H: OsCheck -- CheckOSError justifies it' (LacksEx (Get-Drift 'transitive_osraise.OsCheck'))
    Check 'CONTROL-6: OsNone -- no raiser call, EOSError STILL reported' (HasEx $c6 'EOSError')
    Check 'CONTROL-7: AbortCref -- Abort is not in the table, EAbort STILL reported' (HasEx (Get-Drift 'transitive_osraise.AbortCref') 'EAbort')
    Check 'CONTROL-8: TShadow.Run -- resolved same-name member, EOSError STILL reported' (HasEx (Get-Drift 'transitive_osraise.TShadow.Run') 'EOSError')
    # The WRITER walks the same table: `document --qname` renders the edit.
    $wr = (& $exePath document --qname 'transitive_osraise.OsWriter' --db $db 2>$null | Out-String)
    Check 'WRITER-1: document adds <exception cref="EOSError"> for a Win32Check caller' ($wr -match 'exception cref="EOSError"')
    $wa = (& $exePath document --qname 'transitive_osraise.AbortWriter' --db $db 2>$null | Out-String)
    Check 'WRITER-C1: document adds NO EAbort cref for an Abort caller' (-not ($wa -match 'exception cref="EAbort"'))
    Check 'WRITER-C2: the AbortWriter render is not empty (probe is live)' ($wa.Trim().Length -gt 0)
  } finally { $db = $mainDb }
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  foreach ($d23 in @((Join-Path C:\TEMP "draglint_doctransitive_$PID"))) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
