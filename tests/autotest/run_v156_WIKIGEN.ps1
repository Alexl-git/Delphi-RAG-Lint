#Requires -Version 7.3
<#
  run_v156_WIKIGEN.ps1 -- `repo gen-wiki` (lane WIKIGEN, CC-3): pages per table / per field, determinism, stale pages,
  ASCII + CRLF, project sections (a hand-filled index fixture), usage exit. Every negative assertion has a positive
  control in the same run. Parameters: -Repo (repo root), -Exe (drag-lint.exe with gen-wiki).
#>
[CmdletBinding()]
param([string]$Repo = '', [string]$Exe = '')
if (-not $Repo) { $Repo = (Resolve-Path "$PSScriptRoot\..\..").Path }
if (-not $Exe) { $Exe = Join-Path $Repo 'src\cli\Win64\Debug\drag-lint.exe' }
$ErrorActionPreference = 'Stop'
$script:fail = 0
function Check([string]$name, [bool]$ok, [string]$detail = '') {
  if ($ok) { Write-Host "  PASS $name" } else { $script:fail++; Write-Host "  FAIL $name $detail" -ForegroundColor Red }
}
function Run([string[]]$a) { $o = & { $ErrorActionPreference = 'Continue'; & $Exe @a 2>&1 | ForEach-Object { "$_" } }; [pscustomobject]@{ Code = $LASTEXITCODE; Out = ($o -join "`n") } }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "WIKIGEN: FAIL -- engine exe not found: $Exe" -ForegroundColor Red; exit 1 }
$work = Join-Path $env:TEMP "drag-lint-wikigen-$PID"
New-Item -ItemType Directory -Path $work -Force | Out-Null
try {
  $src = (Get-Content -LiteralPath (Join-Path $Repo 'tests\fixtures\fieldrepo\golden_v2.txt') -Raw).Replace('DISPLAY_LABEL=City', 'DISPLAY_LABEL=Stadt\u00E4')
  $txt = Join-Path $work 'in.txt'; [IO.File]::WriteAllText($txt, $src, [Text.Encoding]::ASCII)
  $repoFile = Join-Path $work 'r.dlrepo'
  $r = Run @('repo', 'restore', '--repo', $repoFile, '--in', $txt)
  Check 'A0 restore the fixture repository' ($r.Code -eq 0) $r.Out

  $r = Run @('repo', 'gen-wiki', '--repo', $repoFile)
  Check 'A1 no --out = exit 2' ($r.Code -eq 2) "$($r.Code) $($r.Out)"
  $o1 = Join-Path $work 'o1'
  $o0 = Join-Path $work 'o0'
  $r = Run @('repo', 'gen-wiki', '--repo', $repoFile, '--output', $o0)
  Check 'A1b the canonical --output spelling works as --out does' (($r.Code -eq 0) -and ($r.Out -match '2 written')) $r.Out
  $r = Run @('repo', 'gen-wiki', '--repo', $repoFile, '--out', $o1)
  Check 'A2 run exits 0, 2 written' (($r.Code -eq 0) -and ($r.Out -match '2 written, 0 unchanged')) $r.Out
  Check 'A3 note: no project index' ($r.Out -match 'note: no project index')
  $cust = Join-Path $o1 'CUSTOMER.md'
  $bytes = [IO.File]::ReadAllBytes($cust)
  $txtc = [Text.Encoding]::ASCII.GetString($bytes)
  Check 'A4 pages: CUSTOMER.md and ORDERS.md' ((Test-Path $cust) -and (Test-Path (Join-Path $o1 'ORDERS.md')))
  Check 'A5 caption heading, anchor and entity' (($txtc -match '(?m)^## Stadt&#228;\r$') -and ($txtc -match '<a id="city"></a>') -and ($txtc -notmatch '[^\x00-\x7F]'))
  Check 'A6 CRLF only (no bare LF)' ((([regex]::Matches($txtc, '(?<!\r)\n')).Count -eq 0) -and $txtc.Contains("`r`n"))
  Check 'A7 dl:wiki block with TABLE.FIELD alias' (($txtc -match '/// dl:wiki Stadt&#228;') -and ($txtc -match '/// Aliases: .*CUSTOMER\.CITY'))
  Check 'A8 fields sorted: CITY before ID before NAME' (($txtc.IndexOf('id="city"') -lt $txtc.IndexOf('id="id"')) -and ($txtc.IndexOf('id="id"') -lt $txtc.IndexOf('id="name"')))
  Check 'A9 summary prose printed' ($txtc -match 'City of the customer')
  $r = Run @('repo', 'gen-wiki', '--repo', $repoFile, '--out', $o1)
  Check 'B1 second run: 0 written, 2 unchanged' ($r.Out -match '0 written, 2 unchanged') $r.Out
  $o2 = Join-Path $work 'o2'
  $r = Run @('repo', 'gen-wiki', '--repo', $repoFile, '--out', $o2, '--per-field')
  $tp = Get-Content (Join-Path $o2 'CUSTOMER.md') -Raw
  Check 'B2 --per-field: CUSTOMER.CITY.md exists, table page links it' ((Test-Path (Join-Path $o2 'CUSTOMER.CITY.md')) -and ($tp -match 'CUSTOMER\.CITY\.md'))
  Check 'B3 --per-field: table page has no field section (positive control: default page has)' (($tp -notmatch 'Kind: data') -and ($txtc -match 'Kind: data'))
  $o3 = Join-Path $work 'o3'
  $r = Run @('repo', 'gen-wiki', '--repo', $repoFile, '--out', $o3, '--table', 'orders')
  Check 'B4 --table narrows to ORDERS.md only' ((Test-Path (Join-Path $o3 'ORDERS.md')) -and -not (Test-Path (Join-Path $o3 'CUSTOMER.md')))
  $o4 = Join-Path $work 'o4'
  $r = Run @('repo', 'gen-wiki', '--repo', $repoFile, '--out', $o4, '--dry-run')
  Check 'B5 --dry-run writes nothing, reports 2' (($r.Code -eq 0) -and -not (Test-Path $o4) -and ($r.Out -match '2 would be written'))
  [IO.File]::WriteAllText((Join-Path $o1 'GONE.md'), "<!-- dl:wikigen table GONE -->`r`n# GONE`r`n")
  [IO.File]::WriteAllText((Join-Path $o1 'README.md'), "hand written`r`n")
  $r = Run @('repo', 'gen-wiki', '--repo', $repoFile, '--out', $o1)
  Check 'C1 stale generated page listed, never deleted' (($r.Out -match 'stale page: GONE\.md') -and (Test-Path (Join-Path $o1 'GONE.md')))
  Check 'C2 hand-written page and live pages are not stale (positive control: C1)' (($r.Out -notmatch 'stale page: README') -and ($r.Out -notmatch 'stale page: CUSTOMER'))
  $db = Join-Path $work 'p.sqlite'
  & python -I (Join-Path $Repo 'tests\fixtures\v156\WIKIGEN\mkdb.py') $db
  $o5 = Join-Path $work 'o5'
  $r = Run @('repo', 'gen-wiki', '--repo', $repoFile, '--out', $o5, '--db', $db)
  $p5 = Get-Content (Join-Path $o5 'CUSTOMER.md') -Raw
  Check 'D1 shown / edited / code / by-name sections' (($p5 -match '(?m)^### Shown in') -and ($p5 -match 'grid column colCity in frmMain \(dataset qryCust\) \(uMain\.dfm:12\)') -and ($p5 -match 'form frmMain \(uMain\.dfm\)') -and ((([regex]::Matches($p5,'form frmMain')).Count) -eq 1) -and ($p5 -match '### Edited in') -and ($p5 -match 'code CityChanged \(uMain\.pas:57\)') -and ($p5 -match '### By name only') -and ($p5 -match 'code CopyCity \(uTools\.pas:9\)')) $r.Out
  Check 'D2 also shown as (project text) and older-copy note' (($p5 -match 'Also shown as: Town') -and ($r.Out -match 'note: the index copy is older than the repository'))
  Check 'D3 no project sections without --db (positive control: D1)' ($txtc -notmatch '### Shown in')
  Check 'D4 file names only, no folder' ($p5 -notmatch 'C:\\P')
} finally { [IO.Directory]::Delete($work, $true) }
if ($script:fail) { Write-Host "WIKIGEN: FAIL ($script:fail)" -ForegroundColor Red; exit 1 }
Write-Host 'WIKIGEN: PASS'
