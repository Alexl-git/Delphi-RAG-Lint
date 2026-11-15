<#
  run_v151_wid_scm_fixers.ps1 -- v151 WID-SCM: the three sidecar fixers in DRagLint.Fix.Expr.pas
  (empty-finally, format-string-not-formatted, shared-marker-legacy-shape) each rewrite their
  fixture (tests\autofix\v151-WID-SCM-<id>\<id>.pas) to exactly <id>.expected. The fixtures also
  hold shapes the fixer must LEAVE alone (try as an if-body, body without ';', non-empty array).
  Usage: pwsh -File tests\autofix\run_v151_wid_scm_fixers.ps1 [-Exe path\to\drag-lint.exe]
#>
[CmdletBinding()]
param([string]$Exe = (Join-Path $PSScriptRoot '..\..\src\cli\Win64\Debug\drag-lint.exe'))
$ErrorActionPreference = 'Stop'
$Exe = (Resolve-Path $Exe).Path
$scratch = Join-Path ([IO.Path]::GetTempPath()) "v151_wid_scm_fix_$PID"
[IO.Directory]::CreateDirectory($scratch) | Out-Null
$fail = $false
try {
  foreach ($id in 'empty-finally', 'format-string-not-formatted', 'shared-marker-legacy-shape') {
    $dir = Join-Path $PSScriptRoot "v151-WID-SCM-$id"
    $tgt = Join-Path $scratch "$id.pas"
    Copy-Item (Join-Path $dir "$id.pas") $tgt -Force
    & $Exe lint $tgt --fix --fix-rule $id --apply --no-backup 2>&1 | Out-Null
    $got = [IO.File]::ReadAllText($tgt)
    $want = [IO.File]::ReadAllText((Join-Path $dir "$id.expected"))
    if ($got -ceq $want) { Write-Host "PASS  $id" } else { Write-Host "FAIL  ${id}: output differs from $id.expected"; $fail = $true }
  }
} finally { [IO.Directory]::Delete($scratch, $true) }
if ($fail) { exit 1 } else { Write-Host 'v151 WID-SCM fixers: all pass'; exit 0 }
