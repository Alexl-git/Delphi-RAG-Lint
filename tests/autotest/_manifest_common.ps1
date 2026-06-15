# Shared prologue for manifest smoke tests. Pins the Win64 exe + ensures DLLs.
param(
    [string] $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe"
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
# tree-sitter Win64 DLLs must sit beside the exe.
$dllSrc = "$PSScriptRoot\..\..\third_party\dll-win64"
Get-ChildItem "$dllSrc\*.dll" | ForEach-Object {
    $dst = Join-Path (Split-Path $Exe) $_.Name
    if (-not (Test-Path $dst)) { Copy-Item $_.FullName $dst }
}
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
    $status = if ($Ok) {'PASS'} else {'FAIL'}; $color = if ($Ok) {'Green'} else {'Red'}
    Write-Host ("  [{0}] {1} {2}" -f $status,$Name,$Detail) -ForegroundColor $color
    if (-not $Ok) { $script:Failed = $true }
}
return $Exe
