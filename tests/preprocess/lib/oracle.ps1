# Run the JS preprocessor oracle on a file, return its resolved stdout as bytes.
# Node is a TEST-ONLY dependency; the shipped drag-lint exe never calls it.
param([string]$File, [string[]]$Defines, [string]$IncludeMode = 'defines-only')
$ppDir = Join-Path $PSScriptRoot '..\oracle\preprocessor'   # inside the repo: tests\preprocess\oracle\README.md
$defObj = @{ defines = $Defines } | ConvertTo-Json -Compress
$defFile = [System.IO.Path]::GetTempFileName()
Set-Content -Path $defFile -Value $defObj -Encoding ascii
$out = & node (Join-Path $ppDir 'cli.js') $File --defines $defFile --include-mode $IncludeMode
Remove-Item $defFile -Force
# Return the raw string (cli.js writes resolved text to stdout).
return ($out -join "`n")
