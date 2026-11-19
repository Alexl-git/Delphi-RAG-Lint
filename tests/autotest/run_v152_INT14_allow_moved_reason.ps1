<#
  run_v152_INT14_allow_moved_reason.ps1 -- `allow --apply` keeps the human-written reason of a
  marker it MOVES (1.52 INT14 tail).

  WHY
  ---
  A wrapped statement's finding anchors on its first line. A marker left on a continuation line
  is "superseded": `allow` removes it there and writes a fresh marker on the anchor line. Before
  1.52 that fresh marker was written with an EMPTY reason, so the reviewer's text -- and its
  `REVIEWED <yyyy-mm-dd>` stamp -- vanished silently (no note, exit 0).

  WHAT THIS PINS
    * moved marker: the reason text survives on the anchor line;
    * moved marker: its REVIEWED stamp is dropped and the note says so (L3: a re-hash is not a
      re-review -- the same rule `allow` already applies to a stale marker on its own line);
    * moved marker without a stamp: reason verbatim, no note;
    * positive controls: a stale marker on its own line keeps its reason and loses its stamp
      (the L3 design), and another rule's stamped marker on the line is kept when a NEW rule is
      added (no re-hash of that entry).

  Usage: pwsh -File tests\autotest\run_v152_INT14_allow_moved_reason.ps1 -Exe <drag-lint.exe>
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Exe,
  [string]$WorkDir = ''
)
if (-not $WorkDir) { $WorkDir = Join-Path $env:TEMP "drag-lint-allow-moved-reason-$PID" }
$ErrorActionPreference = 'Continue'
$script:fail = 0; $script:pass = 0
function Check([string]$n, [bool]$ok, [string]$d = '') {
  if ($ok) { $script:pass++; Write-Host "  [PASS] $n" -ForegroundColor Green }
  else     { $script:fail++; Write-Host "  [FAIL] $n -- $d" -ForegroundColor Red }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory $WorkDir | Out-Null }
Set-Location $WorkDir

$stamp = 'REVIEWED ' + (Get-Date).AddDays(-3).ToString('yyyy-MM-dd')

function New-Fixture([string]$Name, [string]$L1, [string]$L2) {
  $t = "unit $Name;`r`n`r`ninterface`r`n`r`nprocedure P;`r`n`r`nimplementation`r`n`r`nuses`r`n" +
       "  System.SysUtils;`r`n`r`nprocedure P;`r`nvar`r`n  I: Integer;`r`n  S: string;`r`nbegin`r`n" +
       "  S := '';`r`n  for I := 0 to 3 do`r`n  begin`r`n$L1`r`n$L2`r`n  end;`r`nend;`r`n`r`nend.`r`n"
  $p = Join-Path $WorkDir "$Name.pas"
  [IO.File]::WriteAllText($p, $t, [Text.Encoding]::ASCII)
  return $p
}
function Invoke-Allow([string]$Path) {
  $out = @(& $Exe allow $Path --fix-line 20 --fix-rule concat-in-loop --apply 2>&1 | ForEach-Object { "$_" })
  return @{ Out = ($out -join "`n"); Lines = [IO.File]::ReadAllLines($Path) }
}
function Get-Findings([string]$Path) {
  return @(& $Exe lint $Path 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match 'concat-in-loop|review-marker-stale' })
}

# --- M1: stamped marker on the continuation line of a wrapped statement ---------------------
$p = New-Fixture 'MovedStamped' '    S := S +' "      IntToStr(I); // dl:ok concat-in-loop -- $stamp bounded by the 4-pass loop"
$r = Invoke-Allow $p
Write-Host "  raw L20: $($r.Lines[19])"; Write-Host "  raw L21: $($r.Lines[20])"
Check 'M1 marker moved to the anchor line' ($r.Lines[19] -match 'dl:ok concat-in-loop@[0-9a-f]{4}') $r.Lines[19]
Check 'M1 continuation line no longer carries the marker' ($r.Lines[20] -notmatch 'dl:ok') $r.Lines[20]
Check 'M1 reason text survives the move' ($r.Lines[19] -match '-- bounded by the 4-pass loop$') $r.Lines[19]
Check 'M1 REVIEWED stamp dropped (re-hash is not a re-review)' ($r.Lines[19] -notmatch 'REVIEWED') $r.Lines[19]
Check 'M1 note names the dropped stamp' ($r.Out -match 'REVIEWED stamp was dropped') $r.Out
$f = Get-Findings $p
Check 'M1 lint: finding suppressed, marker not stale' ($f.Count -eq 0) ($f -join ' | ')

# --- M2: unstamped marker on the continuation line -------------------------------------------
$p = New-Fixture 'MovedPlain' '    S := S +' '      IntToStr(I); // dl:ok concat-in-loop -- bounded, four passes'
$r = Invoke-Allow $p
Check 'M2 reason carried verbatim' ($r.Lines[19] -match 'dl:ok concat-in-loop@[0-9a-f]{4} -- bounded, four passes$') $r.Lines[19]
Check 'M2 no stamp note when there was no stamp' ($r.Out -notmatch 'REVIEWED stamp was dropped') $r.Out

# --- C1 (control): stale marker on its own line -- L3 design ---------------------------------
$p = New-Fixture 'StaleOwnLine' "    S := S + IntToStr(I); // dl:ok concat-in-loop@ffff -- $stamp bounded" ''
$r = Invoke-Allow $p
Check 'C1 stale re-hash keeps the reason' ($r.Lines[19] -match 'concat-in-loop@[0-9a-f]{4} -- bounded$') $r.Lines[19]
Check 'C1 stale re-hash drops the stamp with a note' (($r.Lines[19] -notmatch 'REVIEWED') -and ($r.Out -match 'REVIEWED stamp was dropped')) $r.Out

# --- C2 (control): adding a NEW rule keeps another rule's stamp ------------------------------
$p = New-Fixture 'OtherRule' "    S := S + IntToStr(I); // dl:ok other-rule@abcd -- $stamp other reason" ''
$r = Invoke-Allow $p
Check 'C2 other rule stamp kept, new rule appended' ($r.Lines[19] -match "other-rule@abcd, concat-in-loop@[0-9a-f]{4} -- $stamp other reason$") $r.Lines[19]

Write-Host "run_v152_INT14_allow_moved_reason: $script:pass pass, $script:fail fail"
if ($script:fail -gt 0) { Write-Host 'RESULT: FAIL'; exit 1 }
Write-Host 'RESULT: PASS'; exit 0
