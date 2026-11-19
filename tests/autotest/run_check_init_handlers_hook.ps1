<#
  run_check_init_handlers_hook.ps1 -- battery entry for run_check_init_handlers.ps1 WITH -RequireHook
  (INT, 1.52): the HBEVORD solver hook is applied, so the handler-order cases must be answered by the
  solver, not only by the harness. The battery passes only -Exe, hence this wrapper.

  Usage: pwsh -File tests\autotest\run_check_init_handlers_hook.ps1 [-Exe <drag-lint.exe>]
  Exit = the wrapped runner's exit code.
#>
param([string]$Exe = '')
$runner = Join-Path $PSScriptRoot 'run_check_init_handlers.ps1'
if ($Exe) { & $runner -Exe $Exe -RequireHook } else { & $runner -RequireHook }
exit $LASTEXITCODE
