<#
  run_type_prefix_exception_ancestor.ps1 -- type-name-prefix must not ask for "T"
  on an exception class whose ancestry leaves the index.

  ORM3 BASICS.PAS:446 (2026-10-16): `EKeyViolation = class(EDatabaseError)`.
  EDatabaseError lives in Data.DB, outside the project index, so the store's
  IsDescendantOf answered "no" and the rule reported `should start with the "T"
  prefix`; Fix all planned EKeyViolation -> TEKeyViolation. The fallback reads
  the direct ancestor's NAME: Exception, or E + a capital, makes it an exception.

  Store-less lint of a fixture (no --db), the path where only the fallback can
  answer. Positive controls: a T-less class of TObject still fires, and so does
  an E-named class whose ancestor is not exception-named (EWidget = class(TObject))
  -- E alone is not an exemption.
  Full ancestry tracing: docs\INBOX-type-name-prefix-exception-ancestry.md.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail) {
  if ($Ok) { Write-Host "  PASS $Name" -ForegroundColor Green }
  else { Write-Host "  FAIL $Name -- $Detail" -ForegroundColor Red; $script:Failed = $true }
}

$work = Join-Path $env:TEMP ('draglint-excprefix-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
$pas = Join-Path $work 'ExcPrefix.pas'
$src = @(
  'unit ExcPrefix;'
  ''
  'interface'
  ''
  'uses'
  '  Data.DB;'
  ''
  'type'
  '  EKeyViolation = class(EDatabaseError);'
  '  EQualified = class(Data.DB.EDatabaseError);'
  '  EPlain = class(Exception);'
  '  Widget = class(TObject);'
  '  EWidget = class(TObject);'
  ''
  'implementation'
  ''
  'end.'
) -join "`r`n"
[IO.File]::WriteAllText($pas, $src + "`r`n", [Text.Encoding]::ASCII)

# lint --json is a bare ARRAY whose line field is start_line (not line)
$raw = & $Exe lint $pas --rule type-name-prefix --json 2>$null
$json = ($raw | Where-Object { $_ -notmatch '^\(loaded' }) -join "`n"
$found = @()
if ($json.Trim().StartsWith('[')) { $found = @($json | ConvertFrom-Json) }
$lines = @($found | Where-Object { $_.rule -eq 'type-name-prefix' } | ForEach-Object { [int]$_.start_line })
Write-Host "type-name-prefix lines: $($lines -join ',')"

Check 'X1 EKeyViolation = class(EDatabaseError): no finding' (-not ($lines -contains 9)) "lines: $($lines -join ',')"
Check 'X2 EQualified = class(Data.DB.EDatabaseError): no finding' (-not ($lines -contains 10)) "lines: $($lines -join ',')"
Check 'X3 EPlain = class(Exception): no finding' (-not ($lines -contains 11)) "lines: $($lines -join ',')"
Check 'X4 Widget = class(TObject) still fires (positive control)' ($lines -contains 12) "lines: $($lines -join ',')"
Check 'X5 EWidget = class(TObject) still fires: E alone is no exemption' ($lines -contains 13) "lines: $($lines -join ',')"

[IO.Directory]::Delete($work, $true)
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
