<#
  run_v152_FUSCOPE_menu.ps1 -- 1.52 lane FUSCOPE, IDE side (SOURCE guard; the plugin
  needs a live IDE, so the owner test page carries the click-level check).

  Pins: the Find Usages submenu (main menu and editor right-click) has the four scopes,
  captions This symbol / Project / Group / Everywhere in that order; the unit is in the
  package; the editor menu nests a row with an EditorParent; the Find Usages panel has the
  same four-scope combo and hands the scope (and the caret) to the engine.
  P0 positive control: the Cmd152 table unit exists and declares EditorParent.
#>
[CmdletBinding()] param()
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check([string]$n, [bool]$ok, [string]$d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $(if ($ok) { '' } else { $d })) -ForegroundColor $c
  if (-not $ok) { $script:fail = $true }
}
$pl = Join-Path $PSScriptRoot '..\..\src\delphi-plugin'
function Src([string]$f) { $p = Join-Path $pl $f; if (Test-Path $p) { [IO.File]::ReadAllText($p) } else { '' } }
$table = Src 'DragLint.Plugin.Cmd152.pas'
$cmd   = Src 'DragLint.Plugin.Cmd.FindUsagesScope.pas'
$menu  = Src 'DragLint.Plugin.EditorLocalMenu.pas'
$form  = Src 'DragLint.Plugin.UsagesForm.pas'
$query = Src 'DragLint.Plugin.UsagesQuery.pas'

Check 'P0 the command table declares EditorParent' ($table -match 'EditorParent\s*:\s*string')
Check 'C1 the unit is in the .dpk and the .dproj' (((Src 'dclDragLintWizard.dpk') -match 'DragLint\.Plugin\.Cmd\.FindUsagesScope in') -and ((Src 'dclDragLintWizard.dproj') -match 'DragLint\.Plugin\.Cmd\.FindUsagesScope\.pas'))
$caps = @([regex]::Matches($cmd, "\.Caption:=\s*'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
Check 'C2 four rows, captions in menu order' (($caps -join '|') -eq 'This symbol|Project|Group|Everywhere') "captions=$($caps -join '|')"
$ids = @([regex]::Matches($cmd, "\.Id:=\s*'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
Check 'C3 the ids sort in menu order (the table sorts by Id)' ((($ids | Sort-Object) -join ',') -eq ($ids -join ',')) "ids=$($ids -join ',')"
Check 'C4 main menu: under drag-lint > Find Usages; editor: drag-lint > Find Usages' (($cmd -match "PARENT_CAPTION = 'Find Usages'") -and ($cmd -match 'ParentPath:= PARENT_CAPTION') -and ($cmd -match 'EditorParent:= PARENT_CAPTION') -and ($cmd -match 'csMainMenu, csEditorContext'))
Check 'C5 the four clicks ask the panel in symbol / project / group / everywhere' (($cmd -match "FindUsagesIn\('symbol'\)") -and ($cmd -match "FindUsagesIn\('project'\)") -and ($cmd -match "FindUsagesIn\('group'\)") -and ($cmd -match "FindUsagesIn\('everywhere'\)"))
Check 'E1 the editor menu nests an EditorParent row (own category + .Items)' (($menu -match 'Rows\[i\]\.EditorParent') -and ($menu -match "\+ '\.Items'"))
Check 'E2 the registry path names the editor submenu' ($table -match 'pCommand\.EditorParent')
Check 'F1 the panel has the four-scope combo' ($form -match "FScopeCombo\.Items\.Add\('This symbol'\)[\s\S]*'Project'[\s\S]*'Group'[\s\S]*'Everywhere'")
Check 'F2 the dock tab''s width switch is the scope switch' (($form -match "Combo\.Items\.Add\('This symbol'") -and ($form -notmatch "Combo\.Items\.Add\('Very wide'\)"))
Check 'F3 the CLI query passes --scope and the caret' (($form -match "' --scope ' \+ FScope") -and ($form -match '--in "%s" --line %d --col %d'))
Check 'F4 the LSP query is scoped' (($form -match 'UsagesLspScopedParams\(') -and ($query -match "AddPair\('scope'"))
Check 'F5 Find Usages from the menu / Ctrl+Alt+F binds at the caret' (([regex]::Matches($form, 'SetPositionFromCaret;')).Count -ge 3)

if ($script:fail) { Write-Host 'run_v152_FUSCOPE_menu: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_v152_FUSCOPE_menu: PASS' -ForegroundColor Green
exit 0
