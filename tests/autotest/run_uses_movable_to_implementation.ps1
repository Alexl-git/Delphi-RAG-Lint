# Guard: uses-movable-to-implementation (gap-rules wave, lane G8, project-wide, hint, ON by default since lane IMOV).
#
# Fixture tests\lint-project\uses-movable-to-implementation: uA.pas has an interface uses of
#   uB (only the implementation calls BProc)  -> FIRES (line 6)
#   uC (the interface declares FC: TC)         -> silent (the non-hit)
#   uD (referenced nowhere)                    -> silent (that is unused-unit-in-uses, not this rule)
# uE.pas: uB is the LAST entry of a multi-line interface uses -> FIRES (line 11); the fix must
#   rewrite the line above to end in ';' (dogfood 2026-10-27: the removal was dropped, E2004).
# uF/uG/uH/uI (lane IATOM): the house LEADING-COMMA layout -- first / middle / last (; own line) /
#   last (; on the entry) interface entry; the implementation insert follows that clause's layout.
# uL (lane IATOM): a column-aligned dotted name (`uM   .Sub`) with a trailing { comment } -- the engine
#   source's own shape -- moves compacted; uM.Sub.pas is its unit.
# uN (lane IATOM dogfood): a `uses` inside a comment below `implementation` is not the clause.
# uJ (lane IATOM, written at run time -- it is UTF-8): a non-ASCII comment on the line above the entry.
#   IATOM declined it (the plan decoded it as ANSI); since CLIFIX C3 it is APPLIED whole (removal +
#   implementation insert together) and stays valid UTF-8.
# Fix: removes the entry from the interface uses and adds it to the implementation uses;
# expected\uA.fixed.pas is hand-written. Second run is a no-op.
# ON by default (lane IMOV, 2026-10-27: REFTYPE closed the reference-to-function FP; engine dogfood
# --fix --apply builds with identical warnings): no config and no --rule -> fires; the config still works.
# Usage: pwsh -File tests/autotest/run_uses_movable_to_implementation.ps1 [-Exe <path>]
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
      [string]$WorkDir = "$env:TEMP\drag-lint-g8-umi-$PID")
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\g8-common.ps1"
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$rule = 'uses-movable-to-implementation'
try {
  $fx = New-G8Scratch $rule $WorkDir
  $db = Join-Path $WorkDir 'fx.sqlite'
  $cfg = Join-Path $PSScriptRoot "..\lint-project\$rule\expected\config.json"
  Check 'index exits 0' ((Invoke-G8Index $Exe $fx $db) -eq 0)
  $off = Get-G8Findings $Exe $db $rule -AllRules
  $viaCfg = Get-G8Findings $Exe $db $rule @('--config', $cfg) -AllRules
  $f = Get-G8Findings $Exe $db $rule
  Show-G8Findings $f
  Check 'positive: uB flagged on uA.pas line 6' (@($f | Where-Object { $_.file_path -match 'uA\.pas$' -and [int]$_.start_line -eq 6 }).Count -eq 1)
  Check 'positive: uB flagged on uE.pas line 11 (last entry)' (@($f | Where-Object { $_.file_path -match 'uE\.pas$' -and [int]$_.start_line -eq 11 }).Count -eq 1)
  Check 'positive: leading-comma uB flagged in uF/uG/uH/uI (line 10)' (@($f | Where-Object { $_.file_path -match 'u[FGHI]\.pas$' -and [int]$_.start_line -eq 10 }).Count -eq 4)
  Check 'positive: aligned dotted name + trailing comment, and the next entry, flagged in uL' (@($f | Where-Object { $_.file_path -match 'uL\.pas$' }).Count -eq 2)
  Check 'negative: uC (used in the interface) and uD (unused) not flagged' ($f.Count -eq 9)
  Check 'message names the unit and points at uses-fix' (($f.Count -eq 9) -and ($f[0].message -match 'uB') -and ($f[0].message -match 'uses-fix'))
  Check 'severity is hint' (($f.Count -eq 9) -and ($f[0].severity -eq 'hint'))
  # --- fix
  $pas = Join-Path $fx 'uA.pas'
  $want = Join-Path $PSScriptRoot "..\lint-project\$rule\expected\uA.fixed.pas"
  & $Exe lint-all --db $db --rule $rule --fix --fix-rule $rule --apply --no-backup 2>&1 | Out-Null
  Check 'fix: result is byte-identical to expected\uA.fixed.pas' (Test-G8BytesEqual $pas $want)
  Check 'fix: last entry -- result is byte-identical to expected\uE.fixed.pas' (Test-G8BytesEqual (Join-Path $fx 'uE.pas') (Join-Path $PSScriptRoot "..\lint-project\$rule\expected\uE.fixed.pas"))
  foreach ($u in 'uF','uG','uH','uI','uL','uN') {
    Check ("fix: leading-comma -- result is byte-identical to expected\$u.fixed.pas") (Test-G8BytesEqual (Join-Path $fx "$u.pas") (Join-Path $PSScriptRoot "..\lint-project\$rule\expected\$u.fixed.pas"))
  }
  $before = [IO.File]::ReadAllBytes($pas)
  & $Exe lint-all --db $db --rule $rule --fix --fix-rule $rule --apply --no-backup 2>&1 | Out-Null
  Check 'fix: second run leaves the bytes unchanged' ([Linq.Enumerable]::SequenceEqual([byte[]]$before, [byte[]][IO.File]::ReadAllBytes($pas)))
  Check 'fix: reindexed fixed file no longer fires' ((Invoke-G8Index $Exe $fx $db) -eq 0 -and (Get-G8Findings $Exe $db $rule).Count -eq 0)
  # --- atomicity (lane IATOM): uJ is UTF-8; the line above the movable entry holds a non-ASCII
  # comment, so the removal's whole-line guard cannot match at apply time. All-or-nothing: the
  # implementation insert must not land without the removal.
  $dj = Join-Path $WorkDir 'drift'
  New-Item -ItemType Directory -Force $dj | Out-Null
  foreach ($u in 'uB','uC') { Copy-Item (Join-Path $fx "$u.pas") $dj -Force }
  $uj = Join-Path $dj 'uJ.pas'
  $nonAscii = [string][char]0x00E4 + [char]0x00DF
  $src = "unit uJ;`r`n`r`ninterface`r`n`r`nuses`r`n  uC {$nonAscii},`r`n  uB;`r`n`r`ntype`r`n  TJ = class`r`n    FC: TC;`r`n  end;`r`n`r`nimplementation`r`n`r`nuses`r`n  uC;`r`n`r`nprocedure DoJ;`r`nbegin`r`n  BProc;`r`nend;`r`n`r`nend.`r`n"
  [IO.File]::WriteAllText($uj, $src, (New-Object Text.UTF8Encoding($false)))
  $djDb = Join-Path $WorkDir 'drift.sqlite'
  Check 'drift: index exits 0' ((Invoke-G8Index $Exe $dj $djDb) -eq 0)
  Check 'drift: uB flagged on uJ.pas line 7 (positive control)' (@(Get-G8Findings $Exe $djDb $rule | Where-Object { $_.file_path -match 'uJ\.pas$' -and [int]$_.start_line -eq 7 }).Count -eq 1)
  # CLIFIX C3: the uses fixers now decode UTF-8 like the applier and map index byte columns to
  # characters, so uJ is APPLIED (it used to be declined because the plan decoded it as ANSI). The
  # atomic whole-fix property still holds: removal AND implementation insert land together, the file
  # stays valid UTF-8 and keeps its non-ASCII comment. The withdraw path of the all-or-nothing applier
  # has no uses-movable trigger left (see the CLIFIX report); cyclefix / convert-apply keep covering it.
  $jRaw = & $Exe lint-all --db $djDb --rule $rule --fix --fix-rule $rule --apply --no-backup --json 2>$null | Out-String
  $strictU8 = New-Object Text.UTF8Encoding($false, $true)
  $jTxt8 = $null; try { $jTxt8 = $strictU8.GetString([IO.File]::ReadAllBytes($uj)) } catch { }
  Check 'utf8: the file is still valid UTF-8 and keeps its non-ASCII comment' (($null -ne $jTxt8) -and $jTxt8.Contains($nonAscii))
  $jIntf = if ($jTxt8) { ($jTxt8 -split 'implementation')[0] } else { '' }
  $jImpl = if ($jTxt8) { ($jTxt8 -split 'implementation')[1] } else { '' }
  Check 'utf8: uB left the interface uses AND joined the implementation uses (whole fix, no half)' (($jIntf -notmatch '\buB\b') -and ($jImpl -match '\buB\b'))
  $jRows = @(); $jb = $jRaw.IndexOf('['); if ($jb -ge 0) { try { $jRows = @($jRaw.Substring($jb) | ConvertFrom-Json) } catch { } }
  $jRow = @($jRows | Where-Object { $_.rule -eq $rule -and ($_.file_path -match 'uJ\.pas$' -or $_.file -match 'uJ\.pas$') })
  Check 'utf8: --json row says applied, not declined' (($jRow.Count -eq 1) -and ($jRow[0].applied -eq $true) -and ($jRow[0].declined -ne $true)) $jRaw.Trim()  Check 'ON by default: no config, no --rule -> fires' ($off.Count -eq 9)
  Check 'config enabled -> fires without --rule' ($viaCfg.Count -eq 9)
} finally { [IO.Directory]::Delete($WorkDir, $true) }
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }