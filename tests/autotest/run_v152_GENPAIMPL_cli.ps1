<#
  run_v152_GENPAIMPL_cli.ps1 -- 1.52 lane GENPAIMPL: `repo gen-param-array` (spec
  docs\superpowers\specs\2026-11-18-gen-param-array-design.md section 5).
  Fixture project tests\fieldrepo\paramarray\proj (PaDemo: uFolders = eligible unit with a text DFM,
  uTestHelper = on the exclusion list). Every case runs the real exe on a COPY under %TEMP%.
    print    : --in uFolders.pas prints TTPA's golden block (read from ParamArrayTests.dpr) on stdout
    plan     : --plan prints a diff and writes nothing (hash check)
    apply    : --apply writes the commented block through ONE compile gate; .BCK1 exists; the excluded
               unit is untouched
    rollback : DRAGLINT_GATE_TEST_BREAK=1 -> exit 1, bytes identical (POSITIVE CONTROL for apply)
    --query/--table naming an absent component -> exit 1; a binary DFM -> a binary-dfm line;
    --plan --apply -> exit 2; --json shape; --step-size / --progress-form reach the block.
  Needs RAD Studio (the gate builds the fixture, Win64). A missing exe / compiler is a FAIL, never a skip.
  RED before the change: the verb answered "not available in this build" (exit 1) for every case.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-genpa-cli-$PID"
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Continue'
$script:Pass = 0
$script:Fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Pass++; Write-Host "  ok   $Name" } else { $script:Fail++; Write-Host "  FAIL $Name $Detail" -ForegroundColor Red }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 1 }
$Exe = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Fixture = Join-Path $Repo 'tests\fieldrepo\paramarray\proj'

function New-Copy([string]$Name) {
  $d = Join-Path $WorkDir $Name
  [IO.Directory]::CreateDirectory($d) | Out-Null
  Copy-Item "$Fixture\*" $d -Recurse -Force
  return $d
}
function Run([string[]]$CliArgs) {
  $o = Join-Path $WorkDir 'o.txt'; $e = Join-Path $WorkDir 'e.txt'
  & { $ErrorActionPreference = 'Continue'; & $Exe @CliArgs > $o 2> $e }
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = [IO.File]::ReadAllText($o); Err = [IO.File]::ReadAllText($e) }
}
function Hash([string]$Dir) {
  return (Get-ChildItem $Dir -Recurse -File | Where-Object { $_.FullName -notmatch '\\(Win64|Win32)\\|\.BCK|\.res$' } | Sort-Object FullName |
    ForEach-Object { "$($_.Name):$((Get-FileHash $_.FullName -Algorithm SHA256).Hash)" }) -join ';'
}
function Lines([string]$Text) {
  $l = @($Text -split "`r?`n")
  while ($l.Count -gt 0 -and $l[-1] -eq '') { $l = $l[0..($l.Count - 2)] }
  return $l
}
[IO.Directory]::CreateDirectory($WorkDir) | Out-Null

# golden block: the GOLDEN array of the engine test runner (one source of truth)
$golden = @()
$inG = $false
foreach ($ln in [IO.File]::ReadAllLines((Join-Path $Repo 'tests\fieldrepo\ParamArrayTests.dpr'))) {
  if ($ln -match 'GOLDEN: array') { $inG = $true; continue }
  if ($inG) {
    if ($ln -match "^\s*'(.*)'(,|\))") { $golden += $Matches[1].Replace("''", "'") }
    if ($ln -match '\);\s*$') { break }
  }
}
Check 'golden block read from the engine tests' ($golden.Count -gt 30) "lines $($golden.Count)"

# print
$w = New-Copy 'print'
$r = Run @('repo', 'gen-param-array', '--in', "$w\uFolders.pas")
Check 'print: exit 0' ($r.Code -eq 0) "exit $($r.Code) err [$($r.Err)]"
Check 'print: stdout is the golden block' ((Lines $r.Out) -join "`n" -ceq ($golden -join "`n")) "first diff: $(((Lines $r.Out) | Select-Object -First 3) -join ' | ')"
Check 'print: status line on stderr' ($r.Err -match 'uFolders: planned \(4 matched, 1 mismatch, 1 missing params, 1 missing fields\)') $r.Err
$r = Run @('repo', 'gen-param-array', '--in', "$w\uFolders.pas", '--step-size', '500', '--progress-form', 'frmLoader2019_Main')
Check 'print: --step-size reaches the block' ($r.Out -match 'STEPSIZE = 500;')
Check 'print: --progress-form reaches the block' ($r.Out -match 'frmLoader2019_Main')
$r = Run @('repo', 'gen-param-array', '--in', "$w\uFolders.pas", '--step-size', '0')
Check 'print: --step-size 0 is a usage error' ($r.Code -eq 2) "exit $($r.Code)"

# plan: writes nothing
$w = New-Copy 'plan'
$before = Hash $w
$r = Run @('repo', 'gen-param-array', '--in', "$w\uFolders.pas", '--plan')
Check 'plan: exit 0' ($r.Code -eq 0) "exit $($r.Code) err [$($r.Err)]"
Check 'plan: stdout is a unified diff' ($r.Out -match '(?m)^@@ -\d+,0 \+\d+,\d+ @@' -and $r.Out -match '(?m)^\+const') $r.Out
Check 'plan: nothing written (hash check)' ((Hash $w) -eq $before)

# json (project mode, plan): the excluded unit is reported
$r = Run @('repo', 'gen-param-array', '--project', "$w\PaDemo.dproj", '--all', '--plan', '--json')
$j = $null
try { $j = $r.Out | ConvertFrom-Json } catch { }
Check 'json: parses, mode plan' (($null -ne $j) -and $j.mode -eq 'plan') $r.Out
$uf = @($j.units | Where-Object { $_.unit -eq 'uFolders' })
$ut = @($j.units | Where-Object { $_.unit -eq 'uTestHelper' })
Check 'json: uFolders planned with counts' ($uf.Count -eq 1 -and $uf[0].status -eq 'planned' -and $uf[0].matched -eq 4 -and $uf[0].type_mismatch -eq 1 -and $uf[0].missing_params -eq 1 -and $uf[0].missing_fields -eq 1 -and $uf[0].query -eq 'qIns' -and $uf[0].table -eq 'tblFOLDERS')
Check 'json: uTestHelper excluded' ($ut.Count -eq 1 -and $ut[0].status -eq 'excluded')
Check 'json: project plan wrote nothing' ((Hash $w) -eq $before)

# absent named components, mode flags
$r = Run @('repo', 'gen-param-array', '--in', "$w\uFolders.pas", '--query', 'qNope')
Check 'query: an absent --query is exit 1, no fallback' ($r.Code -eq 1 -and $r.Out -eq '' -and $r.Err -match 'no-block') "exit $($r.Code) [$($r.Err)]"
$r = Run @('repo', 'gen-param-array', '--in', "$w\uFolders.pas", '--table', 'tblNope')
Check 'table: an absent --table is exit 1' ($r.Code -eq 1) "exit $($r.Code)"
$r = Run @('repo', 'gen-param-array', '--in', "$w\uFolders.pas", '--query', 'QINS', '--table', 'tblfolders')
Check 'query/table: the named pair is accepted (case-insensitive)' ($r.Code -eq 0) "exit $($r.Code)"
$r = Run @('repo', 'gen-param-array', '--in', "$w\uFolders.pas", '--plan', '--apply', '--project', "$w\PaDemo.dproj")
Check 'flags: --plan --apply is exit 2' ($r.Code -eq 2) "exit $($r.Code)"
$r = Run @('repo', 'gen-param-array', '--in', "$w\uFolders.pas", '--apply')
Check 'flags: --apply without --project is exit 2' ($r.Code -eq 2) "exit $($r.Code)"
$r = Run @('repo', 'gen-param-array')
Check 'flags: no --in / --all is exit 2' ($r.Code -eq 2) "exit $($r.Code)"

# binary DFM is REPORTED
$w = New-Copy 'binary'
[IO.File]::WriteAllBytes("$w\uFolders.dfm", [byte[]](0x54, 0x50, 0x46, 0x30, 0, 1, 2, 3))
$r = Run @('repo', 'gen-param-array', '--in', "$w\uFolders.pas")
Check 'binary dfm: a binary-dfm line, exit 1' ($r.Code -eq 1 -and $r.Err -match 'uFolders: binary-dfm') "exit $($r.Code) [$($r.Err)]"
[IO.File]::Delete("$w\uFolders.dfm")
$r = Run @('repo', 'gen-param-array', '--in', "$w\uFolders.pas")
Check 'missing dfm: a missing-dfm line, exit 1' ($r.Code -eq 1 -and $r.Err -match 'uFolders: missing-dfm') "exit $($r.Code) [$($r.Err)]"

# apply through the compile gate
$w = New-Copy 'apply'
$orig = [IO.File]::ReadAllBytes("$w\uFolders.pas")
$helper = (Get-FileHash "$w\uTestHelper.pas").Hash
$r = Run @('repo', 'gen-param-array', '--project', "$w\PaDemo.dproj", '--all', '--apply', '--platform', 'win64')
Check 'apply: exit 0' ($r.Code -eq 0) "exit $($r.Code) out [$($r.Out)] err [$($r.Err)]"
Check 'apply: status applied' ($r.Out -match 'uFolders: applied') $r.Out
$txt = [IO.File]::ReadAllText("$w\uFolders.pas")
Check 'apply: the commented block is in the unit' ($txt -match '(?s)\{\r\nconst\r\n  STEPSIZE = 20000;.*\r\n\}\r\nend\.')
Check 'apply: the backup .BCK1 exists' (Test-Path "$w\uFolders.pas.BCK1")
Check 'apply: the excluded unit is untouched' ((Get-FileHash "$w\uTestHelper.pas").Hash -eq $helper)
Check 'apply: the gate built the project (compile gate lines)' ($r.Err -match 'compile gate')

# rollback: the test seam breaks the first written file
$w = New-Copy 'break'
$before = Hash $w
$env:DRAGLINT_GATE_TEST_BREAK = '1'
$r = Run @('repo', 'gen-param-array', '--project', "$w\PaDemo.dproj", '--all', '--apply', '--platform', 'win64')
$env:DRAGLINT_GATE_TEST_BREAK = ''
Check 'rollback: exit 1' ($r.Code -eq 1) "exit $($r.Code) err [$($r.Err)]"
Check 'rollback: bytes identical (POSITIVE CONTROL for apply)' ((Hash $w) -eq $before)
Check 'rollback: refused-by-gate reported' ($r.Out -match 'refused-by-gate' -or $r.Err -match 'refused-by-gate|REFUSED')

Write-Host "Summary: pass=$($script:Pass) fail=$($script:Fail)"
if ($script:Fail -gt 0) { Write-Host 'GENPAIMPL CLI: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'GENPAIMPL CLI: PASS' -ForegroundColor Green
exit 0
