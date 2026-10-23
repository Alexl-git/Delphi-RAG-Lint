<#
  run_context_stale_anchor.ps1 --
  On a STALE index, `context` must never show another routine's code as the Impl slice.

  THE DEFECT (found 2026-10-23, INBOX-context-slice-wrong-on-stale-anchor.md).
  `context --task "modify DragLint.Plugin.Editor.RegisterDragLintMenu"` on an index
  older than the unit returned impl_start_line 6110 (real: 6549) and printed the body
  of whatever routine now sits at 6110. GetSymbolSlice cuts the CURRENT file at the
  line numbers RECORDED at index time and never checked that the anchor still holds
  the symbol.

  CONTRACT. When the recorded anchor line no longer names the symbol, the slice
  refuses: no code from the wrong place, a `stale-anchor` chunk and a loud
  STALE INDEX warning that names the reindex remedy.

  Run from any CWD, pwsh 7. Builds its own fixture; touches no shared index.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_context_stale_anchor_$PID"
)
try {
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
$unit = Join-Path $src 'uStale.pas'

$head = @"
unit uStale;

interface

type
  TWorker = class(TObject)
  public
    function FirstRoutine: Integer;
    function TargetRoutine: Integer;
  end;

implementation

"@
$bodies = @"
function TWorker.FirstRoutine: Integer;
begin
  Result := 111; // FIRST_BODY_MARK
end;

function TWorker.TargetRoutine: Integer;
begin
  Result := 222; // TARGET_BODY_MARK
end;

end.
"@
Write-Ascii $unit ($head + $bodies)

$db = Join-Path $WorkDir 'fx.sqlite'
& $exePath index $src --db $db 2>&1 | Out-Null
Check 'V the fixture index was built' (Test-Path $db) $db

function Bundle([string]$Task) {
  return ((& $exePath context --task $Task --db $db --format markdown 2>$null) -join "`r`n")
}

# ---- P1/P2 POSITIVE CONTROLS (fresh index) --------------------------------------
$fresh = Bundle 'modify uStale.TWorker.TargetRoutine'
Check 'P1 POSITIVE CONTROL a fresh index slices the TARGET body' ($fresh -match 'TARGET_BODY_MARK') `
      "fresh bundle has no target body ($($fresh.Length) bytes) -- T1/T2 would prove nothing"
Check 'P2 POSITIVE CONTROL a fresh index carries no stale warning' (-not ($fresh -match 'STALE INDEX')) `
      'the anchor check refuses a FRESH slice'

# ---- shift the target: remove FirstRoutine (5 lines) WITHOUT reindexing --------
# The recorded impl_start_line of TargetRoutine now points at `end.` / past EOF,
# and the recorded FirstRoutine span now holds TargetRoutine. Insert filler so the
# OLD target line lands inside another routine, the exact as-found shape.
$shifted = @"
function TWorker.TargetRoutine: Integer;
begin
  Result := 222; // TARGET_BODY_MARK
end;

function TWorker.FirstRoutine: Integer;
begin
  Result := 111; // FIRST_BODY_MARK
end;

end.
"@
Write-Ascii $unit ($head + $shifted)

$stale = Bundle 'modify uStale.TWorker.TargetRoutine'
Check 'T1 a stale anchor does NOT print another routine''s body' (-not ($stale -match 'FIRST_BODY_MARK')) `
      'the slice printed FirstRoutine''s code under TargetRoutine''s header'
Check 'T2 a stale anchor says STALE INDEX and names the reindex remedy' `
      (($stale -match 'STALE INDEX') -and ($stale -match 'reindex')) `
      "no loud warning in a $($stale.Length)-byte bundle"
Check 'T3 the refusal is a stale-anchor chunk' ($stale -match 'stale-anchor') 'no stale-anchor chunk kind'

# ---- T4: an edit BELOW the target keeps its slice (no false refusal) -----------
Write-Ascii $unit ($head + $bodies)
& $exePath index $src --db $db 2>&1 | Out-Null
Write-Ascii $unit ($head + $bodies + "`r`n// trailing comment added after indexing`r`n")
$below = Bundle 'modify uStale.TWorker.TargetRoutine'
Check 'T4 an edit below the target still slices the target (no false refusal)' `
      (($below -match 'TARGET_BODY_MARK') -and -not ($below -match 'STALE INDEX')) `
      'an unrelated edit made the anchor check refuse a correct slice'

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_context_stale_anchor_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
