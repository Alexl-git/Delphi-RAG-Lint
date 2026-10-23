<#
  run_cli_flag_audit_help_surface.ps1 --
  tools\cli-flag-audit.ps1 must read the REAL --help surface, not HelpText.pas alone.

  THE DEFECT (W6-Q lane, 2026-10-23). The audit built its "documented" set H from
  src\cli\DRagLint.CLI.HelpText.pas only. `drag-lint --help` also prints the
  hand-written lines of PrintHelp in DRagLint.CLI.pas, which document
  `--size-guard-mb N` and `--force32`. So both flags were reported as
  ACCEPTED-UNDOCUMENTED although `drag-lint --help` shows them.

  P1 is the positive control: a flag that really is parsed and absent from --help
  (`--from-block`, convert-reemit's verb-local block file) must still land in
  Table 1, or T1/T2 would pass against an audit that reports nothing.

  Run from any CWD, pwsh 7. Writes only its own TEMP report.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe"
)
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
$exePath = (Resolve-Path $Exe).Path
$out = Join-Path $env:TEMP "draglint_flag_audit_$PID.md"
try {
  & pwsh -NoProfile -File (Join-Path $PSScriptRoot '..\..\tools\cli-flag-audit.ps1') -Exe $exePath -OutFile $out *> $null
  $rep = [IO.File]::ReadAllText($out)
  $t1 = $rep.Substring(0, [Math]::Max(0, $rep.IndexOf('## Table 2')))
  $help = (& $exePath --help 2>&1 | Out-String)

  Check 'V --help really documents --force32 and --size-guard-mb' `
        (($help -match '--force32') -and ($help -match '--size-guard-mb')) 'precondition gone: the flags left --help'
  Check 'P1 POSITIVE CONTROL an undocumented parsed flag (--from-block) is still in Table 1' `
        ($t1 -match '`--from-block`') 'Table 1 lost a genuinely undocumented flag -- T1/T2 would be vacuous'
  Check 'T1 --force32 is NOT reported accepted-undocumented' (-not ($t1 -match '`--force32`')) 'H still misses PrintHelp'
  Check 'T2 --size-guard-mb is NOT reported accepted-undocumented' (-not ($t1 -match '`--size-guard-mb`')) 'H still misses PrintHelp'
} finally {
  if (Test-Path -LiteralPath $out) { [IO.File]::Delete($out) }
}
Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
