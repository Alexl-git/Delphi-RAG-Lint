<#
  1.20.4 #4b-4: `NOTE: no index owns <project>` is printed ONCE per run, not once per
  ResolveConsumerDbs call. Fixture: an unregistered project in a temp dir, no own index;
  `lint-all --project` consults the resolver several times. Control: the note IS printed once
  (a guard that only counted zero would pass with the note removed).
  Run from any CWD, pwsh 7.
#>
param([string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe")
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  if ($ok) { Write-Host "  [PASS] $n" -ForegroundColor Green } else { Write-Host "  [FAIL] $n $d" -ForegroundColor Red; $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$W = Join-Path ([IO.Path]::GetTempPath()) ("noteonce-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path "$W\proj" | Out-Null
[IO.File]::WriteAllText("$W\proj\App.dproj", "<Project><PropertyGroup><MainSource>App.dpr</MainSource></PropertyGroup></Project>`r`n", [Text.Encoding]::ASCII)
[IO.File]::WriteAllText("$W\proj\App.dpr", "program App;`r`nbegin`r`nend.`r`n", [Text.Encoding]::ASCII)
Push-Location $W
try {
  $err = & $Exe lint-all --project "$W\proj\App.dproj" 2>&1 | Where-Object { $_ -is [Management.Automation.ErrorRecord] -or $_ -match '^NOTE:' } | ForEach-Object { "$_" }
} finally { Pop-Location }
$n = @($err | Where-Object { $_ -match 'no index owns' }).Count
Check 'note printed (positive control)' ($n -ge 1) "count=$n"
Check 'note printed exactly once' ($n -eq 1) "count=$n"
[IO.Directory]::Delete($W, $true)
if ($script:Failed) { Write-Host 'run_cli_note_once_guard: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_cli_note_once_guard: PASS' -ForegroundColor Green
exit 0
