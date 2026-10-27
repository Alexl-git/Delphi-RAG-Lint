# Guard: dfm-event-handler-missing (gap-rules wave, lane G8, project-wide, warning).
#
# Fixture tests\lint-project\dfm-event-handler-missing:
#   uForm.dfm   MainForm: TMainForm (ancestor TBaseForm in uBase.pas)
#     line 2 OnClick    = FormClick   declared on TMainForm        -> silent
#     line 3 OnDblClick = BaseClick   declared on the ANCESTOR     -> silent (the non-hit)
#     line 4 OnKeyPress = MissingKey  declared nowhere             -> FIRES
#     line 6 OnClick    = BtnClick    on a child, root class has it -> silent
#     line 7 OnExit     = GoneExit    on a child, root lacks it    -> FIRES
#   uOrphan.dfm OrphanForm: TOrphanForm = class(TUnknownThing): the chain is UNKNOWN, so the
#               missing handler must stay SILENT (negative control for the unresolved-ancestor gate).
# Usage: pwsh -File tests/autotest/run_dfm_event_handler_missing.ps1 [-Exe <path>]
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
      [string]$WorkDir = "$env:TEMP\drag-lint-g8-ehm-$PID")
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\g8-common.ps1"
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  $fx = New-G8Scratch 'dfm-event-handler-missing' $WorkDir
  $db = Join-Path $WorkDir 'fx.sqlite'
  Check 'index exits 0' ((Invoke-G8Index $Exe $fx $db) -eq 0)
  $f = Get-G8Findings $Exe $db 'dfm-event-handler-missing'
  Show-G8Findings $f
  $form = @($f | Where-Object { $_.file_path -match 'uForm\.dfm$' } | ForEach-Object { [int]$_.start_line } | Sort-Object)
  Check 'positive: OnKeyPress = MissingKey flagged (line 4)' ($form -contains 4)
  Check 'positive: child OnExit = GoneExit flagged (line 7)' ($form -contains 7)
  Check 'negative: handler declared on the form class not flagged (line 2)' ($form -notcontains 2)
  Check 'negative: handler declared in the ANCESTOR not flagged (line 3)' ($form -notcontains 3)
  Check 'negative: child handler the root class declares not flagged (line 6)' ($form -notcontains 6)
  Check 'negative: unresolved ancestor chain stays silent (uOrphan.dfm)' (@($f | Where-Object { $_.file_path -match 'uOrphan\.dfm$' }).Count -eq 0)
  Check 'exactly two findings' ($f.Count -eq 2)
  Check 'severity is warning' (($f.Count -gt 0) -and ($f[0].severity -eq 'warning'))
  Check 'message names the handler and the class' (($f | Where-Object { $_.message -match 'MissingKey' -and $_.message -match 'TMainForm' }).Count -eq 1)
} finally { [IO.Directory]::Delete($WorkDir, $true) }
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }