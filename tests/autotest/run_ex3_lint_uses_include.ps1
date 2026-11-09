<#
  run_ex3_lint_uses_include.ps1 -- wave 150 lane EX3 item 6 (EX2 150 row).

  A unit whose interface uses list is an include (`uses {$I FfIncUses.inc}`, the entries and the `;` in
  the .inc) parsed clean in the INDEXER since 149 EX2 (MarkUsesListIncludes in TIndexer.IndexFileBody),
  but `lint` / the LSP host parse it through TAstParseCache.ApplyPreprocess, which did not patch it: the
  empty uses clause swallowed the type section and every rule saw parser-error / syntax-error.
  RED on 1.49.0-alpha base: 3 parser-error + 3 syntax-error on FfIncA.pas.
  POSITIVE CONTROL: tests\fixtures\BrokenSyntax.pas still reports a parser-error / syntax-error under the
  same command (a fix that silenced the rule would fail it).
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe")
$ErrorActionPreference = 'Stop'
$script:Failed = 0; $script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { $script:Failed++; if ($d) { Write-Host "      $d" -ForegroundColor DarkGray } }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Fx  = (Resolve-Path (Join-Path $PSScriptRoot '..\fixtures')).Path

# lint --json is a bare ARRAY of findings with a `rule` field (inspected raw); 0 findings prints [].
function SyntaxFindings([string]$file) {
  $raw = & $Exe lint $file --json 2>$null
  $txt = ($raw | Where-Object { $_ -notmatch '^\(loaded' }) -join "`n"
  if ($txt.Trim() -eq '') { return $null }
  return ,@(@($txt | ConvertFrom-Json) | Where-Object { $_.rule -in @('parser-error', 'syntax-error') })
}
Write-Host "== EX3 lint parse of a uses-list include host ($Exe)"
$host_ = Join-Path $Fx 'file-facts-149\facts\FfIncA.pas'
$f = SyntaxFindings $host_
Check 'U1 FfIncA.pas (uses {$I FfIncUses.inc}) lints with no parser-error / syntax-error' (($null -ne $f) -and ($f.Count -eq 0)) "findings=$(($f | ForEach-Object { '{0}@{1}' -f $_.rule, $_.start_line }) -join ', ')"
$ctl = SyntaxFindings (Join-Path $Fx 'BrokenSyntax.pas')
Check 'C1 control: BrokenSyntax.pas still reports a parser-error / syntax-error' (($null -ne $ctl) -and ($ctl.Count -gt 0)) "count=$($ctl.Count)"
Write-Host ("== {0} passed, {1} failed" -f $script:Passed, $script:Failed)
exit ([int]($script:Failed -gt 0))
