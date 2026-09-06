<#
  run_doc_drift_order_insensitive.ps1 --
  docs\INBOX-called-from-order-is-not-deterministic.md

  OWNER RULING 2026-09-06: "Autodoc used-by -- Order is not important. We should
  compare parts. I.e. all parts (lines) are there and not missing, then the
  Documentation is OK. If unit is used by several projects then the order might
  change and this is OK."

  WHAT PROMPTED IT. `document --apply` rewrote a facts block by SWAPPING TWO
  `Used by:` entries and changing nothing else. doc-drift then called the block
  stale and FIXABLE while `document --qname` said "up to date (no change)" --
  checker and writer disagreeing about a block whose CONTENT was never wrong.
  Two earlier sessions chased a stable WRITER order instead; session 70
  implemented the prescribed bucket sort in full and measured it as
  indistinguishable. The ruling moves the fix to the COMPARISON.

  WHAT THIS GUARD PINS -- the permission AND the three things it must not cost:

    1. reordering entries in an inbound list is NOT drift          (the ruling)
    2. an entry MISSING from the stored list IS drift             (control)
    3. an EXTRA entry the fresh render does not know IS drift     (control)
    4. a change to a NON-inbound line (Calls:) IS still drift     (control)

  Controls 2-4 are what stop this from being "the checker stopped checking".
  Without them the whole file passes against an engine whose drift rule was
  simply deleted.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  Write-Host ("  [{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]), $n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if (-not $ok -and $d) { Write-Host "        $d" -ForegroundColor DarkGray }
  if (-not $ok) { $script:Failed = $true }
}
function WriteAscii([string]$Path, [string]$Text) {
  [System.IO.File]::WriteAllText($Path, (($Text -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII)
}

$exePath = (Resolve-Path $Exe).Path
$work = 'C:\TEMP\draglint_drift_order'
if (Test-Path $work) { [System.IO.Directory]::Delete($work, $true) }
New-Item -ItemType Directory $work | Out-Null
$src = Join-Path $work 'ordfix.pas'
$db  = Join-Path $work 'ordfix.sqlite'

# TThing is used by TWO routines, so its `Used by:` list has entries to reorder.
WriteAscii $src @'
unit ordfix;

interface

type
  TThing = record
    Value: Integer;
  end;

procedure UserOne;
procedure UserTwo;

implementation

procedure UserOne;
var
  T: TThing;
begin
  T.Value := 1;
end;

procedure UserTwo;
var
  T: TThing;
begin
  T.Value := 2;
end;

end.
'@

# doc-drift reads the doc from the INDEX, so every source edit needs a reindex.
function Reindex { & $exePath index $work --db $db 2>&1 | Out-Null }
function IsStale {
  $out = & $exePath doc-drift --qname 'ordfix.TThing' --db $db --json 2>$null | Out-String
  return ($out -match 'ddFactsBlockStale')
}
function UsedByLine { return (Get-Content $src | Where-Object { $_ -match 'Used by:' } | Select-Object -First 1) }
function ReplaceLine([string]$Old, [string]$New) {
  $all = [System.IO.File]::ReadAllText($src)
  if (-not $all.Contains($Old)) { throw "anchor not found: $Old" }
  WriteAscii $src $all.Replace($Old, $New)
}

Push-Location C:\TEMP
try {
  Reindex
  & $exePath document --unit $src --db $db --apply --no-backup 2>&1 | Out-Null
  Reindex

  $orig = UsedByLine
  Check 'SETUP: the fixture produced a Used by: line' ($null -ne $orig) `
    'no inbound list to reorder -- every assertion below would be vacuous'
  if ($null -eq $orig) { throw 'cannot continue without a Used by: line' }
  Write-Host "        $($orig.Trim())" -ForegroundColor DarkGray

  Check 'SETUP: the freshly written block is NOT stale' (-not (IsStale)) `
    'the block drifts immediately after being written -- the fixture, not the ruling, is wrong'

  # --- 1. THE RULING: reordering is not drift ------------------------------
  $body  = ($orig -split 'Used by:\s*', 2)[1] -replace '</para>\s*$', ''
  $parts = @($body -split ',\s*') | Where-Object { $_.Trim() -ne '' }
  Check 'SETUP: the list has at least two entries to swap' ($parts.Count -ge 2) `
    ("only {0} entr(y/ies) -- nothing to reorder" -f $parts.Count)
  if ($parts.Count -ge 2) {
    $swapped = @($parts[1], $parts[0]) + $parts[2..($parts.Count-1)] | Where-Object { $_ -ne $null }
    $newLine = $orig.Replace($body, ($swapped -join ', '))
    ReplaceLine $orig $newLine
    Reindex
    Check 'REORDERED entries are NOT drift (the ruling)' (-not (IsStale)) `
      'the same entries in a different order are still reported stale -- this is what the ruling forbids'
    ReplaceLine $newLine $orig   # restore
    Reindex
  }

  # --- 2. CONTROL: a MISSING entry is still drift --------------------------
  if ($parts.Count -ge 2) {
    $short   = @($parts[0..($parts.Count-2)]) -join ', '
    $cutLine = $orig.Replace($body, $short)
    ReplaceLine $orig $cutLine
    Reindex
    Check 'CONTROL a DROPPED entry IS drift' (IsStale) `
      'an entry the fresh render finds and the source lacks must always be drift -- that is how a new caller gets recorded'
    ReplaceLine $cutLine $orig
    Reindex
  }

  # --- 3. CONTROL: an EXTRA entry is still drift ---------------------------
  $extraLine = $orig.Replace($body, ($body + ', ordfix.GhostCaller (ordfix.pas)'))
  ReplaceLine $orig $extraLine
  Reindex
  Check 'CONTROL an INVENTED extra entry IS drift' (IsStale) `
    'this unit is not dl:shared, so a stored-only entry is a STALE entry, not a foreign one'
  ReplaceLine $extraLine $orig
  Reindex

  # --- 3b. CONTROL: a DUPLICATED label falls back to the byte compare ------
  # ParseBlock keys its map by LABEL, so a block carrying the same inbound label
  # twice collapses to ONE entry set and the other <para> disappears from the
  # comparison. A whole-block byte compare never cared; a set compare would go
  # quiet. BlockDrifted therefore detects the duplicate and falls back, which is
  # this unit's documented fail-safe direction.
  #
  # This is not hypothetical: run_doc_drift_unseen_units' CONTROL-1 plants
  # exactly this shape and went RED on the first battery after the set compare
  # landed. Pinned here too, because THIS file is where the set-comparison
  # contract is written down.
  $dupLine = $orig + "`r`n" + ($orig -replace 'Used by:.*</para>', 'Used by: ordfix.GhostUser (ordfix.pas)</para>')
  ReplaceLine $orig $dupLine
  Reindex
  Check 'CONTROL a DUPLICATED inbound label IS drift (byte-compare fallback)' (IsStale) `
    'two <para> elements with the same label cannot be set-compared, so the block must fall back to the byte compare rather than go quiet'
  ReplaceLine $dupLine $orig
  Reindex

  # --- 4. CONTROL: a non-inbound line still byte-compares ------------------
  # Order-insensitivity was ruled for inbound lists only. Nothing about it makes
  # a wrong Calls:/Pure line right, so the residual keeps byte semantics.
  $all = [System.IO.File]::ReadAllText($src)
  $resid = ($all -split "`r?`n" | Where-Object { $_ -match '<para>(Calls|Pure|Complexity|Mutates|Touches)' } | Select-Object -First 1)
  if ($resid) {
    ReplaceLine $resid ($resid -replace '<para>', '<para>TAMPERED ')
    Reindex
    Check 'CONTROL a tampered NON-inbound line IS still drift' (IsStale) `
      'the residual must keep byte-compare semantics'
  } else {
    Check 'CONTROL a tampered NON-inbound line IS still drift' $true 'skipped: fixture rendered no residual fact line'
  }
}
finally { Pop-Location }

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
