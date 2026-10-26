<#
  capture-migrate.ps1 -- re-creates the editor's committed #migrate apply/1 captures (A4 slice 1).

  Copies the ENGINE fixture tests\autotest\fixtures\migrate\* plus this folder's extra books
  (legacy, linked, noinst, global) and SelfForm.pas/.dfm into a TEMP work dir, indexes it into a
  scratch DB there (never a project or library DB), runs convert-apply --json (DRY RUN) for the
  nine pairs of spec section 2 and convert-validate on legacy.rules, and writes the outputs here
  (or to -Out) as apply-<Unit>-<book>-<Suffix>.json / validate-migrate-<Suffix>.txt.

  Usage: pwsh -NoProfile -File capture-migrate.ps1 -Exe <STAGED copy of the pin's drag-lint.exe>
         [-Out <dir>] [-Suffix 1350]
  Never point -Exe at third_party\dll-win64 or into the pin dir itself.
#>
param(
  [Parameter(Mandatory = $true)][string]$Exe,
  [string]$Out = $PSScriptRoot,
  [string]$Suffix = '1350'
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..\..\..')).Path
$engineFixture = Join-Path $repo 'tests\autotest\fixtures\migrate'
$work = Join-Path ([IO.Path]::GetTempPath()) ('cap-migrate-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $work | Out-Null
Copy-Item (Join-Path $engineFixture '*') $work -Force
foreach ($f in 'legacy.rules', 'linked.rules', 'noinst.rules', 'global.rules', 'SelfForm.pas', 'SelfForm.dfm') {
  Copy-Item (Join-Path $PSScriptRoot $f) $work -Force
}
$db = Join-Path $work 'mig.sqlite'
& $Exe index $work --db $db 2>&1 | Out-Null
if (-not (Test-Path $db)) { throw "index failed: $db" }

$pairs = @(
  @('MigForm', 'rename'), @('DlForm', 'dlnone'), @('SelfForm', 'dlnone'), @('WithForm', 'rename'),
  @('MigForm', 'legacy'), @('MigForm', 'linked'), @('CtlForm', 'noinst'), @('MigForm', 'global'),
  @('CtlForm', 'control'))
foreach ($p in $pairs) {
  $unit = Join-Path $work ($p[0] + '.pas')
  $rules = Join-Path $work ($p[1] + '.rules')
  $json = (& $Exe convert-apply --unit $unit --rules $rules --db $db --json 2>$null) -join "`r`n"
  $name = 'apply-{0}-{1}-{2}.json' -f $p[0], $p[1], $Suffix
  [IO.File]::WriteAllText((Join-Path $Out $name), $json + "`r`n", [Text.ASCIIEncoding]::new())
}
$v1 = (& $Exe convert-validate --rules (Join-Path $work 'legacy.rules') 2>&1) -join "`r`n"
$v2 = (& $Exe convert-validate --rules (Join-Path $work 'legacy.rules') --from TSrcBtn --to TDstBtn 2>&1) -join "`r`n"
[IO.File]::WriteAllText((Join-Path $Out ('validate-migrate-{0}.txt' -f $Suffix)),
  "plain:`r`n$v1`r`nscoped:`r`n$v2`r`n", [Text.ASCIIEncoding]::new())
Write-Output "captured into $Out (work dir $work)"
