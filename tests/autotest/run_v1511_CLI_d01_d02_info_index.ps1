<#
  run_v1511_CLI_d01_d02_info_index.ps1 -- lane v1511 CLI, items D01 + D02.
  D01: `info` (text) prints the extractor, resolver and grammar identity again -- before
       only `info --json` carried the first two and nothing printed the grammar DLLs'
       content identity. The text values must equal the --json ones.
  D02: `index --project <file> --db <db>` and `index <dir> --db <db>` print parse-errors=N
       on their Done line (the manifest-section summary already did); a file with a
       syntax error counts 1, a clean tree 0.
  Usage: pwsh -File tests\autotest\run_v1511_CLI_d01_d02_info_index.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = (Join-Path $PSScriptRoot '..\..\src\cli\Win64\Debug\drag-lint.exe'))
$ErrorActionPreference = 'Stop'
$exePath = (Resolve-Path $Exe).Path
$fx = Join-Path $PSScriptRoot '..\fixtures\t2-library-root-150'
$scratch = Join-Path $env:TEMP ("v1511_cli_d01_" + $PID)
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
$fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS $Name" } else { Write-Host "FAIL $Name $Detail" -ForegroundColor Red; $script:fail++ }
}
try {
  $src = Join-Path $scratch 'src'
  New-Item -ItemType Directory -Path $src -Force | Out-Null
  Copy-Item (Join-Path $fx '*') $src -Force
  $db = Join-Path $scratch 'p.sqlite'

  # D02 -- index --project on a clean tree
  $o1 = (& $exePath index --project (Join-Path $src 'T2Lib.dpr') --db $db 2>&1 | Out-String)
  Check 'D02: index --project Done line carries parse-errors=0' ($o1 -match '(?m)^Done\. Files: \d+,.*parse-errors=0\b') $o1

  # D02 -- a broken unit counts
  $brk = Join-Path $scratch 'brk'
  New-Item -ItemType Directory -Path $brk -Force | Out-Null
  [IO.File]::WriteAllText((Join-Path $brk 'uBroken.pas'), "unit uBroken;`r`n`r`ninterface`r`n`r`nimplementation`r`n`r`nprocedure X;`r`nbegin`r`n  if then begin ) ;`r`nend;`r`n`r`nend.`r`n")
  $o2 = (& $exePath index $brk --db (Join-Path $scratch 'b.sqlite') 2>&1 | Out-String)
  Check 'D02: index <dir> Done line counts the broken file (parse-errors=1)' ($o2 -match '(?m)^Done\. Files: \d+,.*parse-errors=1\b') $o2

  # D01 -- info text vs info --json
  $j = (& $exePath info --json 2>$null | Out-String | ConvertFrom-Json)
  $t = (& $exePath info --db $db 2>&1 | Out-String)
  Check 'D01: info text prints the extractor version (= info --json)' ($t -match ("(?m)^extractor: " + [regex]::Escape($j.extractor_version) + '\b')) $t
  Check 'D01: info text prints the resolver version (= info --json)' ($t -match ("(?m)^resolver: " + [regex]::Escape($j.resolver_version) + '\b')) $t
  Check 'D01: info text prints the grammar DLL identity' ($t -match '(?m)^grammar dlls: tree-sitter\.dll=\d+:[0-9A-Fa-f]{16};tree-sitter-delphi13\.dll=\d+:[0-9A-Fa-f]{16};tree-sitter-dfm\.dll=') $t
  Check 'D01: the ABI line is still labelled as an ABI' ($t -match 'ABI, NOT a grammar version') $t
} finally {
  if (Test-Path -LiteralPath $scratch) { [IO.Directory]::Delete($scratch, $true) }
}
if ($fail -gt 0) { Write-Host "FAIL ($fail)" -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
