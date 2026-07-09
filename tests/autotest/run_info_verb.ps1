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
Check ($null -ne $o.capabilities) 'capabilities block present'
Check ($o.exe_path -and (Test-Path $o.exe_path)) 'exe_path resolves to a real file'
Check ($o.platform -eq 'Win64' -or $o.platform -eq 'Win32') 'platform is Win32|Win64'

# text form (no --json) must also work and not error
$txt = & $exe info
Check ($LASTEXITCODE -eq 0) 'info (text) exits 0'
Check ($txt -match 'MIT') 'text form mentions MIT'

if ($fail){Write-Host "RESULT: FAIL ($fail)";exit 1}else{Write-Host 'RESULT: PASS';exit 0}
