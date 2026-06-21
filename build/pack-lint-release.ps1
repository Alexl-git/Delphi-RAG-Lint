<#
  pack-lint-release.ps1 -Version <X.Y.Z-alpha>

  Builds drag-lint.exe Release for Win64 + Win32, deploys the Win64 exe to
  third_party\dll-win64, and stages + zips a self-contained release archive per
  platform that BUNDLES the rules\ folder next to the exe.

  Output: C:\TEMP\rel-<Version>\drag-lint-v<Version>-win64.zip (and -win32.zip)
  Prints the two zip paths on success. Tag + gh release create are done separately.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Version)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$rs = 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"'
$dproj = Join-Path $repo "src\cli\drag-lint.dproj"

foreach ($plat in 'Win64','Win32') {
  $out = cmd /c "$rs && msbuild /t:Build /p:Config=Release /p:Platform=$plat /v:minimal `"$dproj`"" 2>&1
  $err = $out | Select-String -Pattern "\bError\b|E2\d{3}|F2\d{3}|Fatal"
  if ($err) { Write-Host "$plat BUILD FAILED:"; $err | Select-Object -First 10; exit 1 }
  Write-Host ("{0}: {1}" -f $plat, ($out | Select-Object -Last 1))
}
# keep the canonical Win64 exe (used by tests / IDE plugin) in sync
Copy-Item (Join-Path $repo "src\cli\Win64\Release\drag-lint.exe") (Join-Path $repo "third_party\dll-win64\drag-lint.exe") -Force

$rel = "C:\TEMP\rel-$Version"
if (Test-Path $rel) { Remove-Item $rel -Recurse -Force }
$zips = @()
foreach ($plat in 'win64','win32') {
  if ($plat -eq 'win64') { $exe = "src\cli\Win64\Release\drag-lint.exe"; $dll = "third_party\dll-win64" }
  else                   { $exe = "src\cli\Win32\Release\drag-lint.exe"; $dll = "third_party\dll-win32" }
  $stg = Join-Path $rel "drag-lint-v$Version-$plat"
  New-Item -ItemType Directory -Path (Join-Path $stg "rules"), (Join-Path $stg "docs\lint") -Force | Out-Null
  Copy-Item (Join-Path $repo $exe) $stg
  foreach ($d in 'tree-sitter-delphi13.dll','tree-sitter-dfm.dll','tree-sitter.dll') { Copy-Item (Join-Path $repo "$dll\$d") $stg }
  Copy-Item (Join-Path $repo "rules\*.scm") (Join-Path $stg "rules")
  Copy-Item (Join-Path $repo "rules\*.json") (Join-Path $stg "rules")
  Copy-Item (Join-Path $repo "rules\builtin-symbols.txt") (Join-Path $stg "rules")
  Copy-Item (Join-Path $repo "rules\README.md") (Join-Path $stg "rules")
  foreach ($f in 'README.md','CHANGELOG.md','LICENSE','INSTALL.md') { Copy-Item (Join-Path $repo $f) $stg }
  if (Test-Path (Join-Path $repo "docs\AI-USAGE.md")) { Copy-Item (Join-Path $repo "docs\AI-USAGE.md") (Join-Path $stg "docs") }
  Copy-Item (Join-Path $repo "docs\lint\REPORT-1-delphi-lint-landscape.md") (Join-Path $stg "docs\lint")
  Copy-Item (Join-Path $repo "docs\lint\REPORT-2-draglint-implementation-plan.md") (Join-Path $stg "docs\lint")
  $z = Join-Path $rel "drag-lint-v$Version-$plat.zip"
  Compress-Archive -Path $stg -DestinationPath $z
  Write-Host ("{0} -> {1:N0} bytes" -f $plat, (Get-Item $z).Length)
  $zips += $z
}
Write-Host ("ZIPS: " + ($zips -join " "))
