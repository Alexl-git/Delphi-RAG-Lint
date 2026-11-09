<#
  DefaultEngineExe.ps1 -- 149 RQ item 7. Prints the default -Exe for a standalone guard run:
    1. this tree's Debug build (what the battery tests), else
    2. this tree's third_party\dll-win64 exe, else
    3. the MAIN tree's third_party\dll-win64 exe (a fresh git worktree has no build and no deployed exe), else
    4. the Debug path (so the guard's own "exe not found" FATAL names the expected build).
  Call as: [string]$Exe = $(& "$PSScriptRoot\lib\DefaultEngineExe.ps1")
#>
$root  = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$debug = Join-Path $root 'src\cli\Win64\Debug\drag-lint.exe'
$cand  = @($debug, (Join-Path $root 'third_party\dll-win64\drag-lint.exe'))
$common = & git -C $root rev-parse --path-format=absolute --git-common-dir 2>$null
if ($common) { $cand += (Join-Path (Split-Path -Parent $common) 'third_party\dll-win64\drag-lint.exe') }
foreach ($c in $cand) { if (Test-Path -LiteralPath $c) { $c; return } }
$debug
