<#
  run_installed_layout_sqlite.ps1 -- the engine must work with ONLY what the installer ships.

  The engine loads sqlite3.dll dynamically (FireDAC). It used to be found on PATH
  (RAD Studio bin64) on dev machines, so nothing noticed it was never shipped: on a clean
  VM `info` said FTS5=False and `index` died with "-314 Cannot load vendor library".

  Layout under test = what installer\drag-lint.iss puts in {app}\bin: drag-lint.exe,
  tree-sitter*.dll, sqlite3.dll. Run from a fresh temp dir with PATH stripped of every
  directory holding a sqlite3.dll.

  POSITIVE CONTROL: the same copy WITHOUT sqlite3.dll must show FTS5=False / index failing,
  otherwise this guard could not fail (PATH leak, system copy).

  Usage: pwsh -File tests\autotest\run_installed_layout_sqlite.ps1 [-EngineDir <dir>]
#>
param([string] $EngineDir = (Join-Path $PSScriptRoot '..\..\src\cli\Win64\Debug'))
$ErrorActionPreference = 'Stop'
$EngineDir = [IO.Path]::GetFullPath($EngineDir)
$fail = 0
function Check([string] $name, [bool] $ok, [string] $detail = '') {
  if ($ok) { "PASS  $name" } else { "FAIL  $name  $detail"; $script:fail++ }
}

foreach ($f in 'drag-lint.exe', 'sqlite3.dll', 'tree-sitter.dll') {
  if (-not (Test-Path -LiteralPath (Join-Path $EngineDir $f))) { throw "missing $EngineDir\$f" }
}

$cleanPath = (($env:PATH -split ';') | Where-Object {
  $_ -and -not (Test-Path -LiteralPath (Join-Path $_ 'sqlite3.dll'))
}) -join ';'
$oldPath = $env:PATH

function New-Layout([string] $root, [bool] $withSqlite) {
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  Copy-Item -LiteralPath (Join-Path $EngineDir 'drag-lint.exe') $root
  Copy-Item -Path (Join-Path $EngineDir 'tree-sitter*.dll') $root
  if ($withSqlite) { Copy-Item -LiteralPath (Join-Path $EngineDir 'sqlite3.dll') $root }
  $src = Join-Path $root 'src'
  New-Item -ItemType Directory -Force -Path $src | Out-Null
  $unit = "unit SqliteProbeUnit;`r`n`r`ninterface`r`n`r`ntype`r`n  TSqliteProbeWidget = class`r`n  public`r`n    procedure Spin;`r`n  end;`r`n`r`nimplementation`r`n`r`nprocedure TSqliteProbeWidget.Spin;`r`nbegin`r`nend;`r`n`r`nend.`r`n"
  [IO.File]::WriteAllText((Join-Path $src 'SqliteProbeUnit.pas'), $unit, [Text.Encoding]::ASCII)
}

function Invoke-Engine([string] $root, [string[]] $a) {
  $exe = Join-Path $root 'drag-lint.exe'
  $o = & $exe @a 2>&1 | Out-String
  [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("dl-sqlite-guard-" + [guid]::NewGuid().ToString('N'))
try {
  $env:PATH = $cleanPath
  # ---- layout WITH sqlite3.dll ----
  $with = Join-Path $tmp 'with'
  New-Layout $with $true
  $r = Invoke-Engine $with @('info')
  Check 'with sqlite3.dll: info reports FTS5=True' ($r.Out -match 'FTS5=True') $r.Out.Trim()
  $db = Join-Path $with 'probe.sqlite'
  $r = Invoke-Engine $with @('index', (Join-Path $with 'src'), '--db', $db)
  Check 'with sqlite3.dll: index exits 0' ($r.Code -eq 0) ("exit=$($r.Code) " + $r.Out.Trim())
  $r = Invoke-Engine $with @('query', '--name', 'TSqliteProbeWidget', '--db', $db)
  Check 'with sqlite3.dll: query finds the indexed symbol' ($r.Code -eq 0 -and $r.Out -match 'TSqliteProbeWidget') $r.Out.Trim()

  # ---- positive control: WITHOUT sqlite3.dll ----
  $without = Join-Path $tmp 'without'
  New-Layout $without $false
  $r = Invoke-Engine $without @('info')
  Check 'CONTROL without sqlite3.dll: info reports FTS5=False' ($r.Out -match 'FTS5=False') $r.Out.Trim()
  $r = Invoke-Engine $without @('index', (Join-Path $without 'src'), '--db', (Join-Path $without 'probe.sqlite'))
  Check 'CONTROL without sqlite3.dll: index fails' ($r.Code -ne 0) ("exit=$($r.Code) " + $r.Out.Trim())
}
finally {
  $env:PATH = $oldPath
  if (Test-Path -LiteralPath $tmp) { [IO.Directory]::Delete($tmp, $true) }
}
if ($fail) { "FAILED: $fail check(s)"; exit 1 }
'OK: installed layout works with only the shipped sqlite3.dll'
exit 0
