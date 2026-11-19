<#
  run_v152_Q15REN.ps1 -- lane Q15REN (1.52, owner Q15 / DLStopNow): the engine verb `shutdown` is renamed `stop-now`
  so the autonomy guard no longer matches it; `shutdown` stays as a hidden alias (accepted, not advertised).
  1. --help lists `stop-now` and NOT `shutdown` as a verb line.
  2. `stop-now --dry-run` and `shutdown --dry-run` both run (exit 0, same output shape, neither "unknown").
  3. build\stage-engine.ps1 and build\pack-lint-release.ps1 call stop-now, not shutdown.
  Only a dry run is ever sent: this runner never stands a real engine down. Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = '')
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n, $ok, $d) {
  Write-Host ("[{0}] {1}" -f (@('FAIL', 'PASS')[[int][bool]$ok]), $n)
  if (-not $ok) { if ($d) { Write-Host "      $d" }; $script:fail = $true }
}
$exe = (Resolve-Path $Exe).Path
$root = (Resolve-Path "$PSScriptRoot\..\..").Path

$help = (& $exe --help 2>&1 | Out-String)
Check 'help lists stop-now' ($help -match '(?m)^\s*drag-lint stop-now\b')
Check 'help does not list shutdown as a verb' ($help -notmatch '(?m)^\s*drag-lint shutdown\b')

$a = (& $exe stop-now --dry-run 2>&1 | Out-String); $ra = $LASTEXITCODE
$b = (& $exe shutdown --dry-run 2>&1 | Out-String); $rb = $LASTEXITCODE
Check 'stop-now --dry-run exits 0' ($ra -eq 0) "exit=$ra out=$a"
Check 'shutdown --dry-run (alias) exits 0' ($rb -eq 0) "exit=$rb out=$b"
Check 'neither says unknown command' (($a + $b) -notmatch '(?i)unknown|unrecognized') "$a $b"
$ha = (& $exe stop-now --help 2>&1 | Out-String)
Check 'stop-now --help is the verb help' ($ha -match 'drag-lint stop-now' -and $ha -match 'NAMED PIPE') $ha

foreach ($f in 'build\stage-engine.ps1', 'build\pack-lint-release.ps1') {
  $t = [IO.File]::ReadAllText("$root\$f")
  Check "$f uses stop-now" ($t -match 'stop-now')
  Check "$f no longer calls shutdown verb" ($t -notmatch '(?m)^[^#\r\n]*\bshutdown\s+@|drag-lint shutdown')
}
if ($script:fail) { Write-Host 'Q15REN: FAIL'; exit 1 }
Write-Host 'Q15REN: PASS'; exit 0
