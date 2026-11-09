<#
  run_codelens_exceptions.ps1 -- build and run CodeLensExceptionsTests.dpr (wave 149 PL item 1).

  The RAD Studio code lens renders the exception title the engine sends in
  draglint/callerCounts `exceptions` beside the caller count:
  `[1 caller] [raises 2 types, handles 1 type]`. A reply without the key (engine
  <= 1.48) must render the 1.48 label unchanged -- that is the positive control.

  Same compile-and-run harness as run_codelens_cache_lru.ps1 (the cache has no
  Open Tools API dependency); the assertions live in the .dpr.
  Exit 0 = all pass, 1 = an assertion failed, 2 = could not build.
#>
[CmdletBinding()]
param(
  [string]$WorkDir = "$env:TEMP\drag-lint-codelens-exc-$PID"
)
& "$PSScriptRoot\run_codelens_cache_lru.ps1" -Dpr "$PSScriptRoot\..\CodeLensExceptionsTests.dpr" -WorkDir $WorkDir
exit $LASTEXITCODE
