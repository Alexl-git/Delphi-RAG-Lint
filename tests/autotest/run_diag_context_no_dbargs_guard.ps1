<#
  run_diag_context_no_dbargs_guard.ps1 -- TDragLintDiagContext carries no dead DbArgs field.

  Defect (ENGINE wave 4, H1): TDragLintDiagContext.DbArgs was declared but never
  assigned or read (the runner sets FilePath/BufferPath/ExePath/ActiveProjectDb
  only); a dead field invites a provider to read '' and silently run unscoped.

  Asserts: (1) the record body has no DbArgs, (2) nothing in src\delphi-plugin
  reads or writes Ctx.DbArgs / ACtx.DbArgs, (3) POSITIVE CONTROL: the sibling
  TDragLintCompletionContext record DOES still declare DbArgs, so the extractor
  regex is capable of finding the field when it exists.
#>
[CmdletBinding()]
param([string]$RepoRoot = "$PSScriptRoot\..\..")
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  Write-Host ("  [{0}] {1} {2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $n, $d) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
  if (-not $ok) { $script:Failed = $true }
}
$plug = Join-Path (Resolve-Path $RepoRoot).Path 'src\delphi-plugin'
$src  = [IO.File]::ReadAllText((Join-Path $plug 'DragLint.Plugin.Providers.pas'))
function Body([string]$Name) {
  $m = [regex]::Match($src, "(?s)$Name\s*=\s*record(.*?)\bend;")
  if ($m.Success) { $m.Groups[1].Value } else { $null }
}
$diag = Body 'TDragLintDiagContext'
$comp = Body 'TDragLintCompletionContext'
Check 'found the TDragLintDiagContext record' ($null -ne $diag) ''
Check 'TDragLintDiagContext declares no DbArgs field' ($null -ne $diag -and $diag -notmatch '(?m)^\s*DbArgs\b') ''
$uses = @(Get-ChildItem -LiteralPath $plug -Filter *.pas | Select-String -Pattern '\bACtx\.DbArgs\b|\bCtx\.DbArgs\b')
Check 'no unit reads or writes Ctx.DbArgs' ($uses.Count -eq 0) "hits=$($uses.Count)"
Check 'POSITIVE CONTROL: TDragLintCompletionContext still declares DbArgs (regex can see one)' `
  ($null -ne $comp -and $comp -match '(?m)^\s*DbArgs\b') ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
