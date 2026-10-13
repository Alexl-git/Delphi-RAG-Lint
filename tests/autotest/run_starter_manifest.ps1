<#
  run_starter_manifest.ps1 -- the installer's starter drag-lint.json (zero
  sections) and a missing manifest are both accepted quietly by the engine.

  WHY. The installer (installer\drag-lint.iss) drops installer\drag-lint.starter.json
  beside drag-lint.exe as {"settings":{},"indexes":{}} -- a fresh install has no
  project yet. If the engine ever started treating "no sections" as an error or
  a parse warning, every first run after install would greet the user with a
  WARNING about a file they never wrote. Nothing else fails when that happens.
  Note "indexes" is an OBJECT: "indexes":[] is rejected with a parse warning,
  which is what the control case below relies on.

  CASES (engine copied with its tree-sitter DLLs and rules\ into a temp folder,
  manifest written beside the copy, CWD = that folder)
    S1-S3 starter manifest: resolve-dbs --platform Win64, index --all --dry-run,
          index --all -> exit 0, no 'WARNING', no 'could not parse'
    N1-N3 no manifest at all: the same three commands -> exit 0
    C1 CONTROL "indexes":[] -> the warning IS printed (proves the copy reads the
          manifest beside it and that the S checks for "no warning" can fire)

  Run from any CWD, pwsh 7. Touches no real index: the copy has no section.
#>
[CmdletBinding()]
param(
  [string]$Exe      = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$Starter  = "$PSScriptRoot\..\..\installer\drag-lint.starter.json",
  [string]$WorkDir  = "C:\TEMP\draglint_starter_manifest_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
$exePath = (Resolve-Path $Exe).Path
$srcDir  = Split-Path $exePath -Parent
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Path $WorkDir | Out-Null
Copy-Item -LiteralPath $exePath -Destination $WorkDir
Get-ChildItem -LiteralPath $srcDir -Filter 'tree-sitter*.dll' | Copy-Item -Destination $WorkDir
Copy-Item -LiteralPath (Join-Path $srcDir 'rules') -Destination $WorkDir -Recurse
$copy     = Join-Path $WorkDir 'drag-lint.exe'
$manifest = Join-Path $WorkDir 'drag-lint.json'

function Invoke-Engine([string[]]$EngineArgs){
  Push-Location -LiteralPath $WorkDir
  try {
    $o = ((& $copy @EngineArgs 2>&1 | ForEach-Object { "$_" }) -join "`n")
    return [pscustomobject]@{ Rc = $LASTEXITCODE; Out = $o }
  } finally { Pop-Location }
}
$commands = @(
  @{ Tag = 'resolve-dbs --platform Win64'; Args = @('resolve-dbs', '--platform', 'Win64') },
  @{ Tag = 'index --all --dry-run';        Args = @('index', '--all', '--dry-run') },
  @{ Tag = 'index --all';                  Args = @('index', '--all') }
)

# ---- S: the shipped starter manifest ----
Copy-Item -LiteralPath (Resolve-Path $Starter).Path -Destination $manifest
$n = 0
foreach ($c in $commands) {
  $n++
  $r = Invoke-Engine $c.Args
  Check "S$n starter manifest, $($c.Tag): exit 0 (got $($r.Rc))" ($r.Rc -eq 0) $r.Out
  Check "S${n}b no WARNING / could not parse" ($r.Out -notmatch 'WARNING|could not parse') $r.Out
}

# ---- N: no manifest at all ----
[IO.File]::Delete($manifest)
$n = 0
foreach ($c in $commands) {
  $n++
  $r = Invoke-Engine $c.Args
  Check "N$n no manifest, $($c.Tag): exit 0 (got $($r.Rc))" ($r.Rc -eq 0) $r.Out
}

# ---- C: control -- a malformed indexes value IS reported ----
[IO.File]::WriteAllText($manifest, '{"settings":{},"indexes":[]}', [Text.Encoding]::ASCII)
$r = Invoke-Engine $commands[0].Args
Check 'C1 CONTROL "indexes":[] prints a warning (the S checks can fire)' ($r.Out -match 'WARNING|could not parse') $r.Out

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  foreach ($d23 in @("C:\TEMP\draglint_starter_manifest_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
