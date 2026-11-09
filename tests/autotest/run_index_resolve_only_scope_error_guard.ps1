#Requires -Version 7
<#
  run_index_resolve_only_scope_error_guard.ps1 -- 146 k1 tail (148 LS): `index --resolve-only`
  with no <path> / --project said "index requires a <path>", which reads as a contradiction for
  a mode that walks nothing. It must say why the scope is needed and name the no-scope form.
    A  index --resolve-only --db <x> -> exit 2; the text names --resolve-only, the scope it
       needs (--project / <path>) and `index --all --resolve-only`.
    B  POSITIVE CONTROL: plain `index --db <x>` (no --resolve-only) keeps its own text
       "index requires a <path>" and exit 2 (a guard matching any ERROR fails here).
  Never writes a DB: the scope check refuses before any store opens (asserted: no file made).
  Run from any CWD, pwsh 7. -Exe defaults to the repo build.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-ro-scope-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
. (Join-Path $PSScriptRoot 'lsp_stdio_helpers.ps1')
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
New-Item -ItemType Directory $WorkDir -Force | Out-Null
$db = Join-Path $WorkDir 'never.sqlite'

Write-Host ''
Write-Host 'run_index_resolve_only_scope_error_guard -- index --resolve-only names its scope' -ForegroundColor Cyan
$ea = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$a = (& $Exe index --resolve-only --db $db 2>&1 | Out-String); $aCode = $LASTEXITCODE
$b = (& $Exe index --db $db 2>&1 | Out-String); $bCode = $LASTEXITCODE
$ErrorActionPreference = $ea
Check 'A: exit 2' ($aCode -eq 2) "exit=$aCode"
Check 'A: names --resolve-only and the scope it needs' (($a -match 'index --resolve-only parses nothing') -and ($a -match '--project <file\.dproj>') -and ($a -match '<path>')) $a.Trim()
Check 'A: names the no-scope form index --all --resolve-only' ($a -match 'index --all --resolve-only') $a.Trim()
Check 'B control: plain index keeps "index requires a <path>", exit 2' (($b -match 'index requires a <path>') -and ($bCode -eq 2)) "exit=$bCode $($b.Trim())"
Check 'no DB file was created' (-not (Test-Path $db)) $db
[IO.Directory]::Delete($WorkDir, $true)
if ($script:Failed) { exit 1 }
