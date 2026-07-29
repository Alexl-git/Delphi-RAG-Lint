# run_info_verb.ps1 -- drag-lint info --json emits info/1 with the required self-info fields
$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot '..\..\third_party\dll-win64\drag-lint.exe'
$fail = 0
function Check($c,$m){ if(-not $c){Write-Host "FAIL: $m";$script:fail++}else{Write-Host "PASS: $m"} }

$json = & $exe info --json
$o = $json | ConvertFrom-Json
Check ($o.schema -eq 'info/1') 'schema is info/1'
Check ($o.name -eq 'drag-lint') 'name is drag-lint'
Check ($o.version -and $o.version.Length -ge 3) 'version present'
Check ($o.license -eq 'MIT') 'license is MIT'
Check ($o.build_date -match '^\d{4}-\d{2}-\d{2}') 'build_date looks like a date'
Check ($null -ne $o.tree_sitter) 'tree_sitter block present'

# --- K20: the grammar DLL must be identifiable from `info` alone ---------------
# `delphi13`/`dfm` are tree-sitter ABI numbers. They read 14 for every grammar at
# that ABI and do not move when a grammar is rebuilt, which is how a SIX-WEEK DLL
# drift produced a whole false bug report against a parser that was not the one
# running, and why T4c needed a parse-fixture harness instead of a version check.
# These fields are the ones that move. Asserted, not printed: a stamp nobody
# checks is the same as no stamp.
Check ($o.tree_sitter.dll_delphi13 -and $o.tree_sitter.dll_delphi13 -ne 'not loaded' -and $o.tree_sitter.dll_delphi13 -ne 'unknown') `
  'tree_sitter.dll_delphi13 names a loaded module'
Check ($o.tree_sitter.dll_dfm -and $o.tree_sitter.dll_dfm -ne 'not loaded' -and $o.tree_sitter.dll_dfm -ne 'unknown') `
  'tree_sitter.dll_dfm names a loaded module'
# Shape: '<path>  yyyy-mm-dd hh:mm:ss  N bytes'. The DATE and the SIZE are the
# whole point -- a stamp that carried only a path would be as inert as the ABI
# number it exists to replace.
foreach ($k in @('dll_delphi13','dll_dfm')) {
  $v = $o.tree_sitter.$k
  Check ($v -match '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') "tree_sitter.$k carries an mtime"
  Check ($v -match '\s\d+ bytes$') "tree_sitter.$k carries a byte size"
  $p = ($v -split '\s\s')[0]
  Check (Test-Path -LiteralPath $p) "tree_sitter.$k path resolves to a real file ($p)"
}
Check ($o.tree_sitter.abi_note -match 'ABI') 'tree_sitter.abi_note says these numbers are ABI versions'
Check ($null -ne $o.capabilities) 'capabilities block present'
Check ($o.exe_path -and (Test-Path $o.exe_path)) 'exe_path resolves to a real file'
Check ($o.platform -eq 'Win64' -or $o.platform -eq 'Win32') 'platform is Win32|Win64'

# text form (no --json) must also work and not error
$txt = & $exe info
Check ($LASTEXITCODE -eq 0) 'info (text) exits 0'
Check ($txt -match 'MIT') 'text form mentions MIT'
# K20: the text form must LABEL the number as an ABI, not as a grammar version.
# The old label ('tree-sitter: delphi13 14') is what was misread for six weeks.
Check ((($txt -join "`n") -match 'tree-sitter ABI:') -and (($txt -join "`n") -match 'NOT a grammar version')) `
  'text form labels the tree-sitter number as an ABI version'
Check ((($txt -join "`n") -match '(?m)^\s+delphi13 dll:.*\d{4}-\d{2}-\d{2}.*bytes')) `
  'text form prints the delphi13 DLL stamp'

if ($fail){Write-Host "RESULT: FAIL ($fail)";exit 1}else{Write-Host 'RESULT: PASS';exit 0}
