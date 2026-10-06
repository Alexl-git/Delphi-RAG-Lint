#Requires -Version 7.3
<#
  DocsSurfaceHarvest.ps1 -- the ONE definition of how the live CLI verb list and
  the live IDE caption set are harvested. Dot-sourced by
  tests\autotest\run_docs_sync_guard.ps1 (checks 1 and 5) and by
  tools\FeatureRegistry.psm1 (Get-LiveSurface). Extracted 2026-10-05 so the
  feature registry could not fork the regexes silently; a change here changes
  both guards, which is the point.

  No side effects: pure functions over text and the plugin sources on disk.
  Strict mode is set INSIDE each function, not at the top of this file: a
  top-level Set-StrictMode in a dot-sourced file runs in the CALLER's scope and
  would switch strict mode on for the whole of run_docs_sync_guard.ps1, which
  does not run under it -- a behaviour change the extraction must not make.
#>

function Get-HelpVerbList {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$HelpText)
  Set-StrictMode -Version Latest
  # The check-1 anchor: a verb line is exactly two spaces, 'drag-lint', a verb.
  # UNROLLED return: callers wrap the call in @(...) (an empty result is $null).
  return @([regex]::Matches($HelpText, '(?m)^\s{2}drag-lint\s+([a-z][a-z0-9-]*)') |
             ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
}

function Get-MenuSourceText {
  param([Parameter(Mandatory)][string]$Repo)
  Set-StrictMode -Version Latest
  $editorPas = Join-Path $Repo 'src\delphi-plugin\DragLint.Plugin.Editor.pas'
  $aboutForm = Join-Path $Repo 'src\delphi-plugin\DragLint.Plugin.AboutForm.pas'
  # The Reports submenu's items are created through AddWrappedItem in Editor.pas,
  # but their CAPTIONS live in ReportText.pas's REPORT_QUESTIONS catalog and the
  # group headers in ReportGroupCaption -- a menu source like the other two.
  $reportTxt = Join-Path $Repo 'src\delphi-plugin\DragLint.Plugin.ReportText.pas'
  $menuSrc = ''
  foreach ($p in @($editorPas, $aboutForm, $reportTxt)) {
    if (Test-Path -LiteralPath $p) { $menuSrc += (Get-Content -LiteralPath $p -Raw) }
  }
  return $menuSrc
}

# Dialog buttons: a '.Caption :=' whose receiver is a variable declared as, or
# created as, a TButton / TBitBtn / TSpeedButton in the menu sources ('Go To',
# 'Fix', 'Cancel'). They are not menu items and not features. Classified by the
# SOURCE CONSTRUCT, never by the word: a menu item captioned 'OK' stays a menu
# caption. Limitation: receivers are matched by variable NAME across the three
# units, so a button variable and a menu-item variable sharing one name would
# both be classed as buttons.
function Get-DialogButtonVariableNames {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Source)
  Set-StrictMode -Version Latest
  $names = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($m in [regex]::Matches($Source, '(?i)\b((?:\w+\s*,\s*)*\w+)\s*:\s*T(?:Button|BitBtn|SpeedButton)\b')) {
    foreach ($n in ($m.Groups[1].Value -split ',')) { [void]$names.Add($n.Trim()) }
  }
  foreach ($m in [regex]::Matches($Source, '(?i)\b(\w+)\s*:=\s*T(?:Button|BitBtn|SpeedButton)\.Create\b')) { [void]$names.Add($m.Groups[1].Value) }
  # 'var X: TButton:= TButton.Create' also yields the type name itself.
  [void]$names.RemoveWhere([Predicate[string]]{ param($n) $n -match '^T(?:Button|BitBtn|SpeedButton)$' })
  return ,$names
}

function Get-DialogButtonCaptionRegex {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Source)
  Set-StrictMode -Version Latest
  $names = Get-DialogButtonVariableNames -Source $Source
  if ($names.Count -eq 0) { return $null }
  $alt = (@($names) | Sort-Object | ForEach-Object { [regex]::Escape($_) }) -join '|'
  return "(?i)\b(?:$alt)\.Caption\s*:=\s*'([^']+)'"
}

function Get-LiveDialogButtonCaptions {
  param([Parameter(Mandatory)][string]$Repo)
  Set-StrictMode -Version Latest
  $src = Get-MenuSourceText -Repo $Repo
  $rx = Get-DialogButtonCaptionRegex -Source $src
  if (-not $rx) { return @() }
  # UNROLLED return: callers wrap the call in @(...).
  return @([regex]::Matches($src, $rx) | ForEach-Object { $_.Groups[1].Value.Replace('&&', '&').Trim() } | Sort-Object -Unique)
}

function Get-LiveMenuCaptions {
  # -ExcludeDialogButtons (the feature registry) drops dialog-button captions;
  # without it (docs-sync check 5) the set is unchanged.
  param([Parameter(Mandatory)][string]$Repo, [switch]$ExcludeDialogButtons)
  Set-StrictMode -Version Latest
  $menuSrc = Get-MenuSourceText -Repo $Repo
  if ($ExcludeDialogButtons) {
    $rx = Get-DialogButtonCaptionRegex -Source $menuSrc
    if ($rx) { $menuSrc = [regex]::Replace($menuSrc, $rx, '') }
  }
  # Captions the plugin actually creates: menu items, section headers, the About
  # window's buttons, the REPORT_QUESTIONS catalog rows and the report group headers.
  $liveCaptions = New-Object 'System.Collections.Generic.HashSet[string]'
  foreach ($rx in @(
      "AddWrappedItem\(\s*\w+\s*,\s*'([^']+)'",
      "AddSectionHeader\(\s*\w+\s*,\s*'([^']+)'",
      "Add(?:Proc)?Button\(\s*'([^']+)'",
      "\.Caption\s*:=\s*'([^']+)'",
      "\bCaption:\s*'([^']+)'",                      # REPORT_QUESTIONS catalog rows
      "\brtk\w+\s*:\s*Result\s*:=\s*'([^']+)'")) {   # ReportGroupCaption headers
    foreach ($m in [regex]::Matches($menuSrc, $rx)) {
      # '&&' is the Delphi escape for a literal '&' in a caption; docs write one.
      [void]$liveCaptions.Add($m.Groups[1].Value.Replace('&&', '&').Trim())
    }
  }
  return ,$liveCaptions
}

function Get-CaptionKey {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$S)
  Set-StrictMode -Version Latest
  # Docs abbreviate captions on purpose ("Call Graph" for "Call Graph
  # (Butterfly)..."). Normalise both sides, then accept a prefix either way.
  $s = $S.Replace('&&', '&')
  $s = $s -replace '\.\.\.', ' '          # trailing ellipsis is decoration
  $s = $s -replace '[`*"]', ' '
  $s = $s -replace '\s+', ' '
  return $s.Trim().Trim('.', ',', ';', ':', ')', '(').ToLowerInvariant()
}

function Test-CaptionKeyMatch {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Key, [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$LiveKeys)
  Set-StrictMode -Version Latest
  if (-not $Key) { return $false }
  foreach ($lk in $LiveKeys) {
    if ($lk -eq $Key -or $lk.StartsWith($Key) -or $Key.StartsWith($lk)) { return $true }
  }
  return $false
}
