<#
  FirebirdEmbed.ps1 -- a PRIVATE embedded Firebird 4 for tests: copies client + engine of an installed Firebird 4 into
  a folder of the test and writes a firebird.conf with `Providers = Engine13`, so this copy can open local files only:
  no server, no alias, no network database can be reached through it, and no user database is named anywhere.
  New-FirebirdEmbed returns the folder, or '' when no Firebird 4 is installed.
#>
function New-FirebirdEmbed([string]$Target) {
  $src = @('C:\Firebird\Firebird_4_0', 'C:\Program Files\Firebird\Firebird_4_0') |
    Where-Object { Test-Path -LiteralPath (Join-Path $_ 'plugins\engine13.dll') } | Select-Object -First 1
  if (-not $src) { return '' }
  foreach ($d in @($Target, "$Target\plugins", "$Target\intl", "$Target\tzdata")) { [IO.Directory]::CreateDirectory($d) | Out-Null }
  foreach ($n in 'fbclient.dll', 'firebird.msg', 'ib_util.dll', 'plugins.conf', 'isql.exe') { Copy-Item -LiteralPath "$src\$n" -Destination $Target }
  Get-ChildItem -LiteralPath $src -File | Where-Object { $_.Name -match '^(icu|msvcp|vcruntime|zlib)' } | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $Target }
  Copy-Item -LiteralPath "$src\plugins\engine13.dll" -Destination "$Target\plugins"
  Copy-Item -Path "$src\intl\*" -Destination "$Target\intl"
  Copy-Item -Path "$src\tzdata\*" -Destination "$Target\tzdata"
  [IO.File]::WriteAllText("$Target\firebird.conf", "Providers = Engine13`r`nServerMode = Super`r`nDefaultDbCachePages = 256`r`n")
  [IO.File]::WriteAllText("$Target\databases.conf", '')
  return $Target
}
