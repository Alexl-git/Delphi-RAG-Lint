<#
  run_convert_apply_old_platform_enum.ps1 -- 1.43 ENUMMAP (owner ruling 2026-10-28):
  an enum type #migrate maps the members of the OLD platform's enum, not today's.

  THE CONTRACT this guard pins:
    * convert-apply --old-platform-db <db> (repeatable): the From side of an enum
      type #migrate reads its members from that index first, today's --db members
      are added after it; matching stays by the name after the lowercase prefix,
      never by ordinal.
    * A member the old platform has and today's enum lost still maps (pcrSQLWait).
    * A member with no counterpart that the unit uses is a migrate-check on its
      line, left as written (pcrOther).
    * An enum only the old platform declares maps too (gcoWait).
    * A member only today's enum has still maps (pcrAdded).
    * An explicit #migrate member line beats the name match.
    * The old-platform index NEVER answers for a TARGET: New must resolve in --db.
    * The index is read, never written; a path that is no readable index exits 2.
    * POSITIVE CONTROL: without the flag pcrSQLWait has no item at all and stays,
      and the old-only enum is a rule-level migrate-check.

  Fixtures: tests\autotest\fixtures\migrate_old_platform, COPIED to a $PID scratch
  folder and indexed there: old\ into old.sqlite, cur\ + app\ into fx.sqlite.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_convert_old_platform_enum_$PID"
)
try {
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check($n,$ok,$d=''){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
[void][IO.Directory]::CreateDirectory($WorkDir)
Copy-Item (Join-Path $PSScriptRoot 'fixtures\migrate_old_platform\*') $WorkDir -Recurse

$oldDb = Join-Path $WorkDir 'old.sqlite'
$db    = Join-Path $WorkDir 'fx.sqlite'
$unit  = Join-Path $WorkDir 'app\EnumUser.pas'
$orig  = [IO.File]::ReadAllBytes($unit)
# two index roots: the old platform alone, and today's platform + the application
$oldHome = Join-Path $WorkDir 'oldplat'
[IO.Directory]::Move((Join-Path $WorkDir 'old'), $oldHome)
& $Exe index $oldHome --db $oldDb 2>&1 | Out-Null
$project = Join-Path $WorkDir 'project'
[void][IO.Directory]::CreateDirectory($project)
[IO.Directory]::Move((Join-Path $WorkDir 'cur'), (Join-Path $project 'cur'))
[IO.Directory]::Move((Join-Path $WorkDir 'app'), (Join-Path $project 'app'))
$unit = Join-Path $project 'app\EnumUser.pas'
& $Exe index $project --db $db 2>&1 | Out-Null
Check 'V both fixture indexes were built' ((Test-Path $oldDb) -and (Test-Path $db))

function Apply([string]$Rules, [string[]]$Extra = @()) {
  $o = (& $Exe @(@('convert-apply', '--unit', $unit, '--rules', (Join-Path $WorkDir $Rules), '--db', $db) + $Extra) 2>&1) -join "`n"
  $code = $LASTEXITCODE
  $j = $null
  if ($Extra -contains 'json') { try { $j = $o.Substring($o.IndexOf('{')) | ConvertFrom-Json } catch {} }
  return [pscustomobject]@{ Code = $code; Out = $o; J = $j }
}
function Kinds($j, [string]$k) { if ($null -eq $j) { return @() }; return @($j.items | Where-Object { $_.kind -eq $k }) }
function Applied($items, [string]$from, [string]$to) { return @($items | Where-Object { $_.path -eq $from -and $_.value -eq $to }).Count }
function Show($items) { return (($items | ForEach-Object { "$($_.path)->$($_.value)@$($_.line)" }) -join ', ') }
function Texts($items) { return (($items | ForEach-Object { "$($_.line): $($_.text)" }) -join ' | ') }

# ---- positive control: no flag ------------------------------------------------
$r  = Apply 'enum.rules' @('--format', 'json')
$ma = Kinds $r.J 'migrate-applied'
$mc = Kinds $r.J 'migrate-check'
Check 'C1 no flag: JSON parsed, exit 0' (($r.Code -eq 0) -and ($null -ne $r.J)) $r.Out
Check 'C2 ... today''s members map by name, never by ordinal' `
  (((Applied $ma 'pcrDefault' 'ncrDefault') -eq 1) -and ((Applied $ma 'pcrAdded' 'ncrAdded') -eq 1) -and ((Applied $ma 'pcrDefault' 'ncrNone') -eq 0)) (Show $ma)
Check 'C3 ... pcrSQLWait, which today''s enum lost, has no item at all (the gap the flag closes)' `
  ((@($ma + $mc | Where-Object { $_.path -eq 'pcrSQLWait' -or $_.text -match 'pcrSQLWait' }).Count) -eq 0) (Show $ma)
Check 'C4 ... the enum only the old platform declares: rule-level migrate-check, gcoWait not renamed' `
  ((@($mc | Where-Object { $_.line -eq 0 -and $_.text -match 'TGoneCursor resolves in no supplied index' }).Count -eq 1) -and ((Applied $ma 'gcoWait' 'ngnWait') -eq 0)) (Texts $mc)

# ---- the flag: dry run ----------------------------------------------------------
$before = (Get-Item $oldDb).LastWriteTimeUtc
$len    = (Get-Item $oldDb).Length
$r  = Apply 'enum.rules' @('--old-platform-db', $oldDb, '--format', 'json')
$ma = Kinds $r.J 'migrate-applied'
$mc = Kinds $r.J 'migrate-check'
Check 'F1 --old-platform-db: JSON parsed, exit 0' (($r.Code -eq 0) -and ($null -ne $r.J)) $r.Out
Check 'F2 ... pcrSQLWait, in the old enum only, maps by name' ((Applied $ma 'pcrSQLWait' 'ncrSQLWait') -eq 1) (Show $ma)
Check 'F3 ... pcrDefault / pcrHourGlass by name, never by ordinal (ncrNone is ordinal 0)' `
  (((Applied $ma 'pcrDefault' 'ncrDefault') -eq 1) -and ((Applied $ma 'pcrHourGlass' 'ncrHourGlass') -eq 1) -and (@($ma | Where-Object { $_.value -eq 'ncrNone' }).Count -eq 0)) (Show $ma)
Check 'F4 ... pcrAdded, in today''s enum only, still maps' ((Applied $ma 'pcrAdded' 'ncrAdded') -eq 1) (Show $ma)
Check 'F5 ... an enum only the old platform declares maps too (gcoWait -> ngnWait)' ((Applied $ma 'gcoWait' 'ngnWait') -eq 1) (Show $ma)
Check 'F6 ... unmatched pcrOther in use: a migrate-check on its line, naming the fix' `
  ((@($mc | Where-Object { $_.line -gt 0 -and $_.text -match 'pcrOther' -and $_.text -match 'no counterpart' -and $_.text -match '#migrate pcrOther -> <member>' }).Count -eq 1) -and ((Applied $ma 'pcrOther' '') -eq 0)) (Texts $mc)
Check 'F7 ... the old index never answers for a TARGET: TOnlyInOld is a migrate-check, S stays' `
  ((@($mc | Where-Object { $_.line -gt 0 -and $_.text -match 'TStuckOld' }).Count -ge 1) -and (@($mc | Where-Object { $_.line -eq 0 -and $_.text -match 'TOnlyInOld resolves in no supplied index' }).Count -eq 1) -and (@($ma | Where-Object { $_.value -eq 'TOnlyInOld' }).Count -eq 0)) (Texts $mc)
Check 'F8 ... no rule-level complaint about TGoneCursor any more' (@($mc | Where-Object { $_.text -match 'TGoneCursor resolves in no supplied index' }).Count -eq 0) (Texts $mc)

# ---- explicit member lines beat the name match ---------------------------------
$r  = Apply 'explicit.rules' @('--old-platform-db', $oldDb, '--format', 'json')
$ma = Kinds $r.J 'migrate-applied'
$mc = Kinds $r.J 'migrate-check'
Check 'E1 explicit lines win: pcrOther -> ncrNone, pcrSQLWait -> ncrHourGlass, not ncrSQLWait' `
  (((Applied $ma 'pcrOther' 'ncrNone') -eq 1) -and ((Applied $ma 'pcrSQLWait' 'ncrHourGlass') -eq 1) -and ((Applied $ma 'pcrSQLWait' 'ncrSQLWait') -eq 0)) (Show $ma)
Check 'E2 ... so no member warning is left' (@($mc | Where-Object { $_.text -match 'no counterpart' }).Count -eq 0) (Texts $mc)

# ---- the bytes ---------------------------------------------------------------------
$r = Apply 'enum.rules' @('--old-platform-db', $oldDb, '--apply', '--no-backup', '--no-reindex')
$t = [IO.File]::ReadAllText($unit, [Text.Encoding]::ASCII)
Check 'A1 --apply exits 0' ($r.Code -eq 0) $r.Out
Check 'A2 ... mapped members written' `
  ($t.Contains('C:= ncrDefault;') -and $t.Contains('C:= ncrHourGlass;') -and $t.Contains('C:= ncrSQLWait;') -and $t.Contains('C:= ncrAdded;') -and $t.Contains('G:= ngnWait;')) $t
Check 'A3 ... the unmatched member and the unresolved target stay as written' ($t.Contains('C:= pcrOther;') -and $t.Contains('S: TStuckOld;')) $t
Check 'A4 ... a comment is not touched' $t.Contains('{ pcrDefault stays in this comment }') $t
Check 'A5 ... uses gains CurPlat, never the old-platform unit' ($t -match '\bCurPlat\b' -and $t -notmatch '\bOldPlatDb\b') $t
Check 'A6 ... the old-platform index was not written' (((Get-Item $oldDb).LastWriteTimeUtc -eq $before) -and ((Get-Item $oldDb).Length -eq $len))

# ---- refusals and the gate -----------------------------------------------------------
[IO.File]::WriteAllBytes($unit, $orig)
$r = Apply 'enum.rules' @('--old-platform-db', (Join-Path $WorkDir 'nosuch.sqlite'), '--apply', '--no-backup', '--no-reindex')
Check 'R1 a missing old-platform index: exit 2, it says so' (($r.Code -eq 2) -and ($r.Out -match '--old-platform-db')) $r.Out
Check 'R2 ... and nothing was written' ([IO.File]::ReadAllText($unit, [Text.Encoding]::ASCII).Contains('C:= pcrSQLWait;'))
$info = (& $Exe info --json --db $db 2>&1) -join "`n"
$ij = $null; try { $ij = $info.Substring($info.IndexOf('{')) | ConvertFrom-Json } catch {}
Check 'G1 info capability old_platform_enum_map' ($ij.capabilities.old_platform_enum_map -eq $true) $info.Substring(0,[Math]::Min(300,$info.Length))

if ($script:fail) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS' -ForegroundColor Green
exit 0
} finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch {} }
}
