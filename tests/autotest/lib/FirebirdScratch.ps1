<#
  FirebirdScratch.ps1 -- a SCRATCH Firebird 4 database for the live field-repository tests, made with the private
  embedded engine of FirebirdEmbed.ps1 (no server, no alias, no user database is ever named or opened).
  New-ScratchFbConnection returns a connection string for a fresh database holding tests\fixtures\fieldrepo\fbscratch\schema.sql,
  or '' when no Firebird 4 is installed. It also sets $env:FIREBIRD (the embedded folder) for the calling process.
#>
. (Join-Path $PSScriptRoot 'FirebirdEmbed.ps1')
function New-ScratchFbConnection([string]$Work, [string]$Repo) {
  $embed = New-FirebirdEmbed (Join-Path $Work 'fbembed')
  if (-not $embed) { return '' }
  $env:FIREBIRD = $embed
  $env:DL_TEST_FB_EMBED = $embed
  $db = Join-Path $Work 'scratch.fdb'
  $sql = (Get-Content -LiteralPath (Join-Path $Repo 'tests\fixtures\fieldrepo\fbscratch\schema.sql') -Raw).Replace('@DB@', $db)
  $sqlFile = Join-Path $Work 'scratch-schema.sql'
  [IO.File]::WriteAllText($sqlFile, $sql, [Text.Encoding]::ASCII)
  $o = & { $ErrorActionPreference = 'Continue'; & (Join-Path $embed 'isql.exe') -q -i $sqlFile 2>&1 }
  if (-not (Test-Path -LiteralPath $db)) { throw "scratch Firebird database was not created: $($o -join ' ')" }
  return "Database=$db;User_Name=SYSDBA;Password=masterkey;DriverID=FB;VendorLib=$embed\fbclient.dll"
}
