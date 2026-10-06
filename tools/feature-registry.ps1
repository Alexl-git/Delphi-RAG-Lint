#Requires -Version 7.3
<#
  feature-registry.ps1 -- the registry engine (spec section 17). Every team
  reads and writes features\ through this one tool, so every write lands in
  canonical form and nobody hand-crafts JSON.

  VERBS
    add        -Id <id> -Title <t> -Group <g> -Owner <TEAM> -Summary <s> -WikiPage <page>
               -Surface "<spec> ;; <spec> ;; ..." [-Intro <i>] [-Status shipped|experimental|planned|deprecated|internal]
               (several surfaces go in ONE -Surface argument separated by ' ;; ' -- pwsh -File cannot bind a
               repeated parameter and does not parse array syntax)
               [-Since <ver>] [-Audience human|agent|both] [-Requires <tok,...>] [-Aliases <a,...>] [-Related <id,...>]
               [-Notes <n>] [-HomeOrder <n>] [-By <who>]
               [-NewGroup -GroupTitle <t> -GroupSummary <s>] [-NewTeam -TeamTitle <t> -TeamSummary <s>]
               Surface specs: cli:<verb>[/<sub>][|<example>]  ide-menu:<drag-lint > A > B...>
               ide-context:<Structure form|Project Manager|Editor>|<caption>  ide-about:<caption>
               tool-window:<View > Tool Windows > X>  shortcut:<keys>  lsp:<method>  mcp:<tool>
               script:<repo path>[|<args>]  exe:<name.exe>[|<menu>]  workflow:<repo .md>
    update     -Id <id> -Set "field=value ;; field2=value2"   (JSON for arrays/objects: aliases=["a","b"]; 'field=' removes)
    find       -Text <text> [-IncludeChildren]
    blast-radius  -MenuPath "<node>" | -VerbName <verb> | -WikiPage <page> | -Group <g>  [-IncludeChildren]
    move-menu  -From "<old prefix>" -To "<new prefix>" [-WhatIf]   (also rewrites menuPrefix in
               families\chart-questions.json, in place, when the node covers it)
    deprecate  -Id <id> [-SupersededBy <id>] [-RemovedIn <ver>]
    normalise  (entries: canonical JSON; groups.json / teams.json: one row per line, keys id title order
               summary; families, exemptions, related-projects: CRLF / trailing newline / BOM only, never
               re-serialised -- their hand layout is kept)
    check      [-Level WellFormed|Full]   (= the guard's checks; Full needs the engine exe)
    generate   [-Check] [-OutDir <dir>]    (= tools\build-feature-pages.ps1)
  Common: -Repo <root> (default: parent of this script's folder), -Json (machine output).
  Exit codes: 0 ok, 1 refused / check failed / no hits, 2 usage.
#>
# Find-FeatureEntry, Get-FeatureBlastRadius, Move-FeatureMenuPath and
# Invoke-RegistryNormalise return WRAPPED arrays: assign them directly. @(...)
# around one of them is a one-element array even when there are no rows.
[CmdletBinding()]
param(
  [Parameter(Position = 0)][string]$Verb,
  [string]$Id, [string]$Title, [string]$Group, [string]$Owner, [string]$Status, [string]$Since, [string]$Summary, [string]$Intro,
  [string]$WikiPage, [string[]]$Surface, [string]$Audience, [string[]]$Requires, [string[]]$Aliases, [string[]]$Related,
  [string]$Notes, [int]$HomeOrder, [string]$By = $env:USERNAME,
  [switch]$NewGroup, [string]$GroupTitle, [string]$GroupSummary, [switch]$NewTeam, [string]$TeamTitle, [string]$TeamSummary,
  [string[]]$Set, [string]$Text, [string]$MenuPath, [string]$VerbName, [string]$From, [string]$To,
  [string]$SupersededBy, [string]$RemovedIn, [switch]$IncludeChildren, [switch]$WhatIf,
  [ValidateSet('WellFormed', 'Full')][string]$Level = 'Full', [switch]$Check, [string]$OutDir,
  [switch]$Json, [string]$Repo = (Split-Path -Parent $PSScriptRoot)
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$verbs = @('add', 'update', 'find', 'blast-radius', 'move-menu', 'deprecate', 'normalise', 'check', 'generate')
if (-not $Verb -or $verbs -notcontains $Verb) {
  Write-Host "usage: feature-registry.ps1 <$($verbs -join '|')> ...  (see the header of this script)" -ForegroundColor Yellow
  exit 2
}
Import-Module (Join-Path $PSScriptRoot 'FeatureRegistry.psm1') -Force
$paths = Get-RegistryPaths -Repo $Repo

function Out-Result($Obj, [string[]]$Columns) {
  if ($Json) { $Obj | ConvertTo-Json -Depth 8; return }
  if ($Obj -is [string]) { Write-Host $Obj; return }
  $Obj | Format-Table -Property $Columns -AutoSize | Out-String -Width 220 | Write-Host
}

function ConvertFrom-SetArg([string]$Arg) {
  $i = $Arg.IndexOf('=')
  if ($i -lt 1) { throw "-Set '$Arg': expected field=value" }
  $k = $Arg.Substring(0, $i).Trim(); $v = $Arg.Substring($i + 1)
  if ($v -eq '') { return @{ Key = $k; Value = $null } }
  if ($v.TrimStart().StartsWith('[') -or $v.TrimStart().StartsWith('{')) { # -NoEnumerate: without it a ONE-element JSON array arrives as a bare string.
    $val = ConvertTo-OrderedObject ($v | ConvertFrom-Json -AsHashtable -Depth 8 -NoEnumerate)
    return @{ Key = $k; Value = $val } }
  if ($k -eq 'homeOrder') { return @{ Key = $k; Value = [int]$v } }
  return @{ Key = $k; Value = $v }
}

try {
  switch ($Verb) {
    'add' {
      $fields = @{ id = $Id; title = $Title; group = $Group; owner = $Owner; status = $Status; since = $Since; summary = $Summary; intro = $Intro
                   wikiPage = $WikiPage; audience = $Audience; notes = $Notes }
      if ($Surface)  { $fields['surfaces'] = @($Surface | ForEach-Object { $_ -split '\s*;;\s*' } | Where-Object { $_.Trim() } | ForEach-Object { ConvertFrom-SurfaceSpec -Spec $_.Trim() }) }
      if ($Requires) { $fields['requires'] = @($Requires | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
      if ($Aliases)  { $fields['aliases']  = @($Aliases  | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
      if ($Related)  { $fields['related']  = @($Related  | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
      if ($HomeOrder -gt 0) { $fields['homeOrder'] = $HomeOrder }
      $file = New-FeatureEntry -Paths $paths -Fields $fields -By $By -NewGroup:$NewGroup -GroupTitle $GroupTitle -GroupSummary $GroupSummary -NewTeam:$NewTeam -TeamTitle $TeamTitle -TeamSummary $TeamSummary
      Out-Result "registered $Id -> $file`nnext: write docs\wiki\$WikiPage.md, then tools\build-feature-pages.ps1 and commit the regenerated pages with the feature"
    }
    'update' {
      if (-not $Set) { throw 'update: -Set field=value is required' }
      $h = @{}; foreach ($a in @($Set | ForEach-Object { $_ -split '\s*;;\s*' } | Where-Object { $_.Trim() })) { $kv = ConvertFrom-SetArg $a.Trim(); $h[$kv.Key] = $kv.Value }
      Out-Result ("updated " + (Update-FeatureEntry -Paths $paths -Id $Id -Set $h))
    }
    'find' {
      if (-not $Text) { throw 'find: -Text is required' }
      $rows = Find-FeatureEntry -Paths $paths -Text $Text -IncludeChildren:$IncludeChildren
      if ($rows.Count -eq 0) { Write-Host "find: nothing matches '$Text'"; exit 1 }
      Out-Result $rows @('Id', 'Title', 'Group', 'Owner', 'Status', 'WikiPage', 'Hit')
    }
    'blast-radius' {
      $rows = Get-FeatureBlastRadius -Paths $paths -MenuPath $MenuPath -Verb $VerbName -WikiPage $WikiPage -Group $Group -IncludeChildren:$IncludeChildren
      if ($rows.Count -eq 0) { Write-Host 'blast-radius: no entry sits at or under that node'; exit 1 }
      Out-Result $rows @('Id', 'Title', 'Owner', 'WikiPage', 'Surface', 'File')
    }
    'move-menu' {
      if (-not $From -or -not $To) { throw 'move-menu: -From and -To are required' }
      $rows = Move-FeatureMenuPath -Paths $paths -From $From -To $To -WhatIf:$WhatIf
      Out-Result $rows @('Id', 'Old', 'New', 'WikiPage', 'File')
      if (-not $Json) { Write-Host "revisit the wiki page of every row above, then tools\build-feature-pages.ps1 -- same commit as the menu change" -ForegroundColor Yellow }
    }
    'deprecate' {
      if (-not $Id) { throw 'deprecate: -Id is required' }
      Out-Result ("deprecated " + (Set-FeatureDeprecated -Paths $paths -Id $Id -SupersededBy $SupersededBy -RemovedIn $RemovedIn))
    }
    'normalise' {
      $changed = Invoke-RegistryNormalise -Paths $paths
      Out-Result ("normalised $($changed.Count) file(s)" + $(if ($changed.Count) { "`n  " + ($changed -join "`n  ") } else { '' }))
    }
    'check' {
      $res = Invoke-RegistryCheck -Paths $paths -Level $Level
      foreach ($n in $res.Notes) { Write-Host "  [NOTE] $n" -ForegroundColor DarkGray }
      foreach ($f in $res.Failures) { Write-Host "  [FAIL] $f" -ForegroundColor Red }
      if ($Json) { $res | ConvertTo-Json -Depth 6 }
      if ($res.Failures.Count) { Write-Host "check: $($res.Failures.Count) failure(s)" -ForegroundColor Red; exit 1 }
      Write-Host "check ($Level): PASS -- $($res.Stats['entries']) entries" -ForegroundColor Green
    }
    'generate' {
      $args2 = @('-Repo', $Repo); if ($Check) { $args2 += '-Check' }; if ($OutDir) { $args2 += @('-OutDir', $OutDir) }
      & (Join-Path $PSScriptRoot 'build-feature-pages.ps1') @args2
      exit $LASTEXITCODE
    }
  }
  exit 0
} catch {
  # Module messages already start with the verb ("add: ...").
  $msg = $_.Exception.Message
  Write-Host $(if ($msg.StartsWith("${Verb}:")) { $msg } else { "${Verb}: $msg" }) -ForegroundColor Red
  exit 1
}
