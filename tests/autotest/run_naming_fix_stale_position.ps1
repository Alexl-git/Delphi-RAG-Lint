<#
  run_naming_fix_stale_position.ps1 -- a naming fix the STALE INDEX cannot
  place is reported as "skipped (stale index)" with a reindex command, never
  as "no fixable findings".

  THE DEFECT THIS PINS (found 2026-10-13, spec criteria 12-13): the index had a
  constant at line 48, the file on disk had it at line 36. `lint --fix
  --fix-line 36 --fix-rule const-casing` could not resolve the symbol at the
  finding's position, skipped it silently (NamingFix.BuildNamingFixEdits,
  `if Sym.Id = 0 then Continue`), and the summary said `autofix: no fixable
  findings` -- which the user reads as "this cannot be fixed".

  THE FIX: when the position does not resolve BUT the index holds a symbol of
  that name in that file, the finding is counted as a stale-position skip (a
  per-FINDING counter, separate from the per-EDIT stale guard), and the summary
  reads `autofix: 0 fixable finding(s), N skipped (stale index) -- reindex:
  drag-lint index --project <proj> --db <db>`. The reindex hint is NEVER the
  folder form `index <dir> --db`, which widens a project DB permanently.

  Fixture: the DB lives at <work>\_D-RAG\Cc.sqlite beside <work>\Cc.dpr, so the
  hint can name the real project file without --project.

  Cases:
    S1  stale: output does NOT say "no fixable findings"
    S2  stale: output says "1 skipped (stale index)"
    S3  stale: output names `index --project "<the .dpr>"`, never `index <dir>`
    S4  stale: the file is byte-identical (nothing written)
    P1  positive control: after a reindex the same command finds 1 fixable finding
    G1  the live Micronite2027 index was not touched

  Exit code: 0 on full pass, 1 on any failure.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
  if (-not $Ok) { $script:Failed = $true }
}
Write-Host '== naming fix: stale-position skip is reported, not hidden ==' -ForegroundColor Cyan
$Exe = (Resolve-Path $Exe).Path
$live = 'C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite'
$liveBefore = if (Test-Path -LiteralPath $live) { $i = Get-Item -LiteralPath $live; "$($i.Length)|$($i.LastWriteTimeUtc.Ticks)" } else { 'absent' }
$work = Join-Path ([IO.Path]::GetTempPath()) ("draglint-nfstale-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path (Join-Path $work '_D-RAG') | Out-Null
try {
  $u = Join-Path $work 'uCc.pas'
  $body = @'
unit uCc;

interface

const Lot_Notes = 'x';

implementation

end.
'@
  [IO.File]::WriteAllText($u, (($body -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
  $dpr = Join-Path $work 'Cc.dpr'
  [IO.File]::WriteAllText($dpr, "program Cc;`r`nuses`r`n  uCc in 'uCc.pas';`r`nbegin`r`nend.`r`n", [Text.Encoding]::ASCII)
  $db = Join-Path $work '_D-RAG\Cc.sqlite'

  & $Exe index --project $dpr --db $db 2>&1 | Out-Null

  # Make the index stale: three comment lines above the const, NO reindex.
  # The const moves from line 5 to line 8.
  $stale = ($body -replace "`r`n", "`n") -replace "const Lot_Notes", "// a`n// b`n// c`nconst Lot_Notes"
  [IO.File]::WriteAllText($u, ($stale -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
  $before = [IO.File]::ReadAllBytes($u)

  $o = (& $Exe lint --file $u --db $db --fix --fix-line 8 --fix-rule const-casing 2>&1 | Out-String)
  $summary = ($o -split "`r?`n" | Where-Object { $_ -match 'autofix|reindex' }) -join ' | '
  Check 'S1 stale: summary does NOT say "no fixable findings"' ($o -notmatch 'no fixable findings') $summary
  Check 'S2 stale: summary says "1 skipped (stale index)"' ($o -match '1 skipped \(stale index\)') ''
  Check 'S3 stale: hint names index --project <the .dpr>, never the folder form' `
    (($o -match [regex]::Escape("index --project `"$dpr`"")) -and ($o -notmatch 'index <dir>')) ''
  $after = [IO.File]::ReadAllBytes($u)
  Check 'S4 stale: the file is unchanged' ([Linq.Enumerable]::SequenceEqual([byte[]]$before, [byte[]]$after)) ''

  & $Exe index --project $dpr --db $db 2>&1 | Out-Null
  $o2 = (& $Exe lint --file $u --db $db --fix --fix-line 8 --fix-rule const-casing 2>&1 | Out-String)
  Check 'P1 positive control: after reindex, 1 fixable finding' ($o2 -match '1 fixable finding') `
    (($o2 -split "`r?`n" | Where-Object { $_ -match 'autofix' }) -join ' | ')
} finally {
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
$liveAfter = if (Test-Path -LiteralPath $live) { $i = Get-Item -LiteralPath $live; "$($i.Length)|$($i.LastWriteTimeUtc.Ticks)" } else { 'absent' }
Check 'G1 Micronite2027.sqlite size+mtime unchanged' ($liveBefore -eq $liveAfter) "$liveBefore -> $liveAfter"
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
