<#
run_migrate_dbs_keeps_unmodelled_keys.ps1 -- `migrate-dbs --apply` rewrites
the manifest to drop each moved section's "db" key. It must change ONLY that:
every key the parser does not model must survive, and no defaulted key may be
added.

Measured on 1.31.4: migrate-dbs saved through TManifestIO.Save, which
re-serialises the model, so "_comment", "scan", settings.futureKnob and a
section's "_note" were dropped and settings/docs defaults were written in.

Arms:
  P  positive control: the DB really moved and the section's "db" key is gone
  K  "_comment", "scan", settings.futureKnob, section "_note" survive
  N  no defaulted key is added (no "docs", no settings.defaultPlatform, no
     section sqlOnlyMS), and settings.maxJobs keeps its value

Runs only on a private temp manifest (--config), never the real one.
Usage: pwsh -NoProfile -File tests\autotest\run_migrate_dbs_keeps_unmodelled_keys.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint-migrate-keeps-keys-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $status = if ($Ok) {'PASS'} else {'FAIL'}
  $color  = if ($Ok) {'Green'} else {'Red'}
  Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
  if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) {
  Write-Host "  [FAIL] engine not found: $Exe" -ForegroundColor Red
  exit 1
}
$Exe = (Resolve-Path -LiteralPath $Exe).Path
try {
  New-Item -ItemType Directory -Path "$WorkDir\proj", "$WorkDir\elsewhere" -Force | Out-Null
  [IO.File]::WriteAllText("$WorkDir\proj\App.dpr", "program App;`r`nbegin`r`nend.`r`n", [Text.Encoding]::ASCII)
  $oldDb = "$WorkDir\elsewhere\App.sqlite"
  $newDb = "$WorkDir\proj\_D-RAG\App.sqlite"
  $p = Start-Process -FilePath $Exe -ArgumentList @('index', '--project', "$WorkDir\proj\App.dpr", '--db', $oldDb) `
         -NoNewWindow -Wait -PassThru -WorkingDirectory $WorkDir `
         -RedirectStandardOutput "$WorkDir\idx.out" -RedirectStandardError "$WorkDir\idx.err"
  Check 'fixture: the DB to migrate was built' (($p.ExitCode -eq 0) -and (Test-Path -LiteralPath $oldDb)) "exit=$($p.ExitCode)"

  $esc = $WorkDir -replace '\\', '\\'
  $cfg = "$WorkDir\m.json"
  [IO.File]::WriteAllText($cfg,
    ('{"_comment":"keep me","settings":{"maxJobs":2,"futureKnob":7},"indexes":{"sections":[{"name":"App","include":["' +
     $esc + '\\proj\\App.dpr"],"db":"' + $esc + '\\elsewhere\\App.sqlite","_note":"mine"}]},"scan":{"x":1}}'),
    [Text.Encoding]::ASCII)

  $p = Start-Process -FilePath $Exe -ArgumentList @('migrate-dbs', '--config', $cfg, '--apply') `
         -NoNewWindow -Wait -PassThru -WorkingDirectory $WorkDir `
         -RedirectStandardOutput "$WorkDir\mig.out" -RedirectStandardError "$WorkDir\mig.err"
  $migOut = ([IO.File]::ReadAllText("$WorkDir\mig.out")).Trim() -replace '\s+', ' '
  $text = [IO.File]::ReadAllText($cfg)
  $j = $text | ConvertFrom-Json
  $sec = @($j.indexes.sections | Where-Object { $_.name -eq 'App' })

  Check 'P: migrate-dbs --apply exit 0' ($p.ExitCode -eq 0) "exit=$($p.ExitCode) out='$migOut'"
  Check 'P: the DB moved to the project''s _D-RAG folder' ((Test-Path -LiteralPath $newDb) -and -not (Test-Path -LiteralPath $oldDb))
  Check 'P: the section''s "db" key is gone (the migrated path DID change)' (($sec.Count -eq 1) -and (-not $sec[0].PSObject.Properties['db'])) ($text -replace '\s+', ' ')

  Check 'K: "_comment" survives' ($j._comment -eq 'keep me')
  Check 'K: "scan" survives' ($j.scan.x -eq 1)
  Check 'K: settings.futureKnob survives' ($j.settings.futureKnob -eq 7)
  Check 'K: section "_note" survives' (($sec.Count -eq 1) -and ($sec[0]._note -eq 'mine'))

  Check 'N: settings.maxJobs keeps its value' ($j.settings.maxJobs -eq 2)
  Check 'N: no defaulted key is added' `
    ((-not $j.PSObject.Properties['docs']) -and (-not $j.settings.PSObject.Properties['defaultPlatform']) -and
     ($sec.Count -eq 1) -and (-not $sec[0].PSObject.Properties['sqlOnlyMS'])) ($text -replace '\s+', ' ')
} finally {
  if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
