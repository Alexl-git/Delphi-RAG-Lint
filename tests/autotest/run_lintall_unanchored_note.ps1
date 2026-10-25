<#
run_lintall_unanchored_note.ps1 -- `lint-all --db <project db>` with no
--project, on a DB that sits outside any _D-RAG folder and no manifest claims,
must SAY that no ownership scoping was applied (X-10, INBOX-2026-09-29 item 3).

Measured 2026-10-25 (1.33.x): a project index of App.dpr whose closure reaches
..\lib\L.pas, stored at an ad-hoc path, linted with `lint-all --db` alone,
reported L.pas's findings next to the project's and printed no note; the same
run with --project skipped L.pas and named the default ownRoots. The W3-7
re-measure missed this because its DB sat in the project's _D-RAG folder, from
which LintAnchorDir derives the anchor.

Arms:
  A  project DB, ad-hoc path, no --project: a NOTE names the unscoped run and --project
  B  positive control: the same DB with --project: no unscoped NOTE
  C  a folder-scan DB (no project_tag): no unscoped NOTE (scoping is meaningless there)

Usage: pwsh -NoProfile -File tests\autotest\run_lintall_unanchored_note.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint-lintall-unanchored-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $status = if ($Ok) {'PASS'} else {'FAIL'}
  $color  = if ($Ok) {'Green'} else {'Red'}
  Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
  if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) {
  Write-Host "  [FAIL] engine not found: $Exe" -ForegroundColor Red
  exit 1
}
$Exe   = (Resolve-Path -LiteralPath $Exe).Path
$Ascii = [Text.Encoding]::ASCII
function Write-Ascii([string]$Path, [string]$Body) {
  [IO.File]::WriteAllText($Path, ($Body -replace "`r`n", "`n" -replace "`n", "`r`n"), $Ascii)
}
function Invoke-Dl([string[]]$Arguments) {
  $o = "$WorkDir\o.txt"; $e = "$WorkDir\e.txt"
  $p = Start-Process -FilePath $Exe -ArgumentList $Arguments -NoNewWindow -Wait -PassThru -WorkingDirectory $WorkDir `
         -RedirectStandardOutput $o -RedirectStandardError $e
  [pscustomobject]@{ Exit = $p.ExitCode; All = [IO.File]::ReadAllText($o) + [IO.File]::ReadAllText($e) }
}
$notePat = 'NOTE: .*no ownership scoping'
try {
  New-Item -ItemType Directory -Path "$WorkDir\proj", "$WorkDir\lib", "$WorkDir\dbs" -Force | Out-Null
  Write-Ascii "$WorkDir\proj\App.dpr" "program App;`nuses`n  L in '..\lib\L.pas',`n  M in 'M.pas';`nbegin`nend.`n"
  $body = "interface`nprocedure P;`nimplementation`nprocedure P;`nbegin`n  try`n  except`n  end;`nend;`nend.`n"
  Write-Ascii "$WorkDir\proj\M.pas" ("unit M;`n" + $body)
  Write-Ascii "$WorkDir\lib\L.pas"  ("unit L;`n" + $body)

  $null = Invoke-Dl @('index', '--project', "$WorkDir\proj\App.dpr", '--db', "$WorkDir\dbs\p.sqlite")
  $null = Invoke-Dl @('index', "$WorkDir\lib", '--db', "$WorkDir\dbs\f.sqlite")

  $a = Invoke-Dl @('lint-all', '--db', "$WorkDir\dbs\p.sqlite")
  Check 'A: unanchored project DB -- NOTE says no ownership scoping' ($a.All -match $notePat) "exit=$($a.Exit)"
  Check 'A: unanchored project DB -- NOTE names the --project remedy' ($a.All -match '(?m)NOTE: .*--project') ''
  $b = Invoke-Dl @('lint-all', '--db', "$WorkDir\dbs\p.sqlite", '--project', "$WorkDir\proj\App.dpr")
  Check 'B: with --project -- no unscoped NOTE' ($b.All -notmatch $notePat) "exit=$($b.Exit)"
  Check 'B: with --project -- the outside file is skipped (scoping is live)' ($b.All -match 'outside the project''s own roots skipped') ''
  $c = Invoke-Dl @('lint-all', '--db', "$WorkDir\dbs\f.sqlite")
  Check 'C: folder-scan DB -- no unscoped NOTE' ($c.All -notmatch $notePat) "exit=$($c.Exit)"
}
finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
if ($script:Failed) { Write-Host 'run_lintall_unanchored_note: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_lintall_unanchored_note: PASS' -ForegroundColor Green
exit 0
