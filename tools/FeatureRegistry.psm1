#Requires -Version 7.3
<#
  FeatureRegistry.psm1 -- the ONE place the feature registry's schema, canonical
  form, validation, live harvest, importers, checks and renderers live.
  tools\feature-registry.ps1, tools\build-feature-pages.ps1 and
  tests\autotest\run_feature_registry_guard.ps1 are thin callers of this module.
  Spec: docs\superpowers\specs\2026-10-05-feature-registry-design.md
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The caption/verb harvest is SHARED with run_docs_sync_guard.ps1 (Task 2 adds
# the file). Dot-sourced once at module load, from the module's own repo, so
# Get-CaptionKey / Get-LiveMenuCaptions / Get-HelpVerbList / Test-CaptionKeyMatch
# are one definition for both guards. Missing until Task 2 lands: tolerated.
$script:HarvestLibPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'tests\autotest\lib\DocsSurfaceHarvest.ps1'
if (Test-Path -LiteralPath $script:HarvestLibPath) { . $script:HarvestLibPath }

# Per-type key order and required keys for surfaces[] (spec 6.1). The schema's
# enum of 'type' mirrors the keys here; run_feature_registry_canonical.ps1
# asserts the two lists agree.
$script:SurfaceKeys = [ordered]@{
  'cli'         = @('type', 'verb', 'sub', 'example')
  'ide-menu'    = @('type', 'path')
  'ide-context' = @('type', 'host', 'caption')
  'ide-about'   = @('type', 'caption')
  'tool-window' = @('type', 'path')
  'shortcut'    = @('type', 'keys')
  'lsp'         = @('type', 'method')
  'mcp'         = @('type', 'tool')
  'script'      = @('type', 'path', 'args')
  'exe'         = @('type', 'name', 'menu')
  'workflow'    = @('type', 'doc')
}
$script:SurfaceRequired = @{
  'cli' = @('verb'); 'ide-menu' = @('path'); 'ide-context' = @('host', 'caption'); 'ide-about' = @('caption')
  'tool-window' = @('path'); 'shortcut' = @('keys'); 'lsp' = @('method'); 'mcp' = @('tool')
  'script' = @('path'); 'exe' = @('name'); 'workflow' = @('doc')
}
$script:ContextHosts = @('Structure form', 'Project Manager', 'Editor')
$script:ChildOnlyKeys = @('parent', 'subgroup', 'emitter', 'wikiAnchor')
$script:ExampleKeys = @('kind', 'text', 'path', 'note')
$script:LastVerifiedKeys = @('date', 'by', 'build')

function Get-RegistryPaths {
  param([string]$Repo = (Split-Path -Parent $PSScriptRoot))
  $Repo = (Resolve-Path -LiteralPath $Repo).Path
  $f = Join-Path $Repo 'features'
  return [pscustomobject]@{
    Repo = $Repo; Features = $f
    Entries = Join-Path $f 'entries'; Families = Join-Path $f 'families'; Templates = Join-Path $f 'templates'
    Schema = Join-Path $f 'schema'; Generated = Join-Path $f 'generated'
    Groups = Join-Path $f 'groups.json'; Teams = Join-Path $f 'teams.json'
    Exemptions = Join-Path $f 'exemptions.json'; SeedBacklog = Join-Path $f 'seed-backlog.json'
    RelatedProjects = Join-Path $f 'related-projects.json'
    Wiki = Join-Path $Repo 'docs\wiki'; Changelog = Join-Path $Repo 'CHANGELOG.md'
    Exe = Join-Path $Repo 'third_party\dll-win64\drag-lint.exe'
    Readme = Join-Path $Repo 'README.md'; AiUsage = Join-Path $Repo 'docs\AI-USAGE.md'
    CoreModel = Join-Path $Repo 'src\core\DRagLint.Core.Model.pas'
    SchemaPas = Join-Path $Repo 'src\storage\DRagLint.Storage.Schema.pas'
    ReportText = Join-Path $Repo 'src\delphi-plugin\DragLint.Plugin.ReportText.pas'
    McpServer = Join-Path $Repo 'src\mcp\DRagLint.MCP.Server.pas'
    CliPas = Join-Path $Repo 'src\cli\DRagLint.CLI.pas'
    PackScript = Join-Path $Repo 'build\pack-lint-release.ps1'
    ChartBundler = Join-Path $Repo 'charts\src\New-DiagramArtifact.ps1'
    ChartsDir = Join-Path $Repo 'charts\src'
    HarvestLib = Join-Path $Repo 'tests\autotest\lib\DocsSurfaceHarvest.ps1'
    SubMapLib = Join-Path $Repo 'tests\autotest\lib\CliFlagVerbMap.ps1'
  }
}

# ---------------------------------------------------------------------------
# Canonical JSON
# ---------------------------------------------------------------------------
function ConvertTo-OrderedObject {
  param([AllowNull()]$Value)
  if ($null -eq $Value) { return $null }
  if ($Value -is [string] -or $Value -is [bool] -or $Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) { return $Value }
  if ($Value -is [System.Collections.Specialized.OrderedDictionary]) {
    $o = [ordered]@{}; foreach ($k in $Value.Keys) { $o[[string]$k] = ConvertTo-OrderedObject $Value[$k] }; return $o
  }
  if ($Value -is [System.Collections.IDictionary]) {
    $o = [ordered]@{}; $ks = [string[]]@($Value.Keys); [Array]::Sort($ks, [System.StringComparer]::Ordinal)
    foreach ($k in $ks) { $o[$k] = ConvertTo-OrderedObject $Value[$k] }; return $o
  }
  if ($Value -is [System.Management.Automation.PSCustomObject]) {
    $o = [ordered]@{}; foreach ($pr in $Value.PSObject.Properties) { $o[$pr.Name] = ConvertTo-OrderedObject $pr.Value }; return $o
  }
  if ($Value -is [System.Collections.IEnumerable]) { return ,@(foreach ($i in $Value) { ConvertTo-OrderedObject $i }) }
  return $Value
}

function Write-JsonString([System.Text.StringBuilder]$Sb, [string]$S) {
  [void]$Sb.Append('"')
  foreach ($ch in $S.ToCharArray()) {
    $code = [int]$ch
    if ($ch -eq '"') { [void]$Sb.Append('\"') }
    elseif ($ch -eq '\') { [void]$Sb.Append('\\') }
    elseif ($ch -eq "`n") { [void]$Sb.Append('\n') }
    elseif ($ch -eq "`r") { [void]$Sb.Append('\r') }
    elseif ($ch -eq "`t") { [void]$Sb.Append('\t') }
    elseif ($code -gt 127) { throw ("non-ASCII character U+{0} in string: {1}" -f $code.ToString('X4'), $S) }
    elseif ($code -lt 32) { [void]$Sb.Append('\u' + $code.ToString('x4')) }
    else { [void]$Sb.Append($ch) }
  }
  [void]$Sb.Append('"')
}

function Write-JsonValue([System.Text.StringBuilder]$Sb, $V, [int]$Level) {
  $pad = '  ' * $Level
  if ($null -eq $V) { [void]$Sb.Append('null'); return }
  if ($V -is [bool]) { [void]$Sb.Append($(if ($V) { 'true' } else { 'false' })); return }
  if ($V -is [string]) { Write-JsonString $Sb $V; return }
  if ($V -is [int] -or $V -is [long] -or $V -is [double] -or $V -is [decimal]) { [void]$Sb.Append(([string]$V)); return }
  if ($V -is [System.Management.Automation.PSCustomObject]) { $V = ConvertTo-OrderedObject $V }
  if ($V -is [System.Collections.IDictionary]) {
    $keys = @($V.Keys | ForEach-Object { [string]$_ })
    if (-not ($V -is [System.Collections.Specialized.OrderedDictionary])) { $ks = [string[]]$keys; [Array]::Sort($ks, [System.StringComparer]::Ordinal); $keys = $ks }
    if ($keys.Count -eq 0) { [void]$Sb.Append('{}'); return }
    [void]$Sb.Append("{`r`n")
    for ($i = 0; $i -lt $keys.Count; $i++) {
      [void]$Sb.Append($pad + '  '); Write-JsonString $Sb $keys[$i]; [void]$Sb.Append(': ')
      Write-JsonValue $Sb $V[$keys[$i]] ($Level + 1)
      if ($i -lt $keys.Count - 1) { [void]$Sb.Append(',') }
      [void]$Sb.Append("`r`n")
    }
    [void]$Sb.Append($pad + '}'); return
  }
  if ($V -is [System.Collections.IEnumerable]) {
    $items = @($V)
    if ($items.Count -eq 0) { [void]$Sb.Append('[]'); return }
    $complex = @($items | Where-Object { ($_ -is [System.Collections.IDictionary]) -or ($_ -is [System.Management.Automation.PSCustomObject]) -or (($_ -is [System.Collections.IEnumerable]) -and -not ($_ -is [string])) })
    if ($complex.Count -eq 0) {
      [void]$Sb.Append('[')
      for ($i = 0; $i -lt $items.Count; $i++) { if ($i -gt 0) { [void]$Sb.Append(', ') }; Write-JsonValue $Sb $items[$i] $Level }
      [void]$Sb.Append(']'); return
    }
    [void]$Sb.Append("[`r`n")
    for ($i = 0; $i -lt $items.Count; $i++) {
      [void]$Sb.Append($pad + '  '); Write-JsonValue $Sb $items[$i] ($Level + 1)
      if ($i -lt $items.Count - 1) { [void]$Sb.Append(',') }
      [void]$Sb.Append("`r`n")
    }
    [void]$Sb.Append($pad + ']'); return
  }
  Write-JsonString $Sb ([string]$V)
}

function ConvertTo-CanonicalJson {
  param([Parameter(Mandatory)][AllowNull()]$Value)
  $sb = [System.Text.StringBuilder]::new()
  Write-JsonValue $sb $Value 0
  return $sb.ToString() + "`r`n"
}

function Sort-OrdinalUnique([string[]]$Items) {
  $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
  foreach ($i in @($Items)) { [void]$set.Add([string]$i) }
  $arr = [string[]]@($set); [Array]::Sort($arr, [System.StringComparer]::Ordinal)
  return ,$arr
}

function Get-EntryKeyOrder {
  param([Parameter(Mandatory)]$Paths)
  $schema = Get-Content -LiteralPath (Join-Path $Paths.Schema 'entry.schema.json') -Raw | ConvertFrom-Json
  return [string[]]@($schema.properties.PSObject.Properties.Name)
}

function Select-OrderedKeys([System.Collections.IDictionary]$Obj, [string[]]$Order) {
  $o = [ordered]@{}
  foreach ($k in $Order) { if ($Obj.Contains($k) -and $null -ne $Obj[$k]) { $o[$k] = $Obj[$k] } }
  $rest = [string[]]@($Obj.Keys | Where-Object { $Order -notcontains $_ }); [Array]::Sort($rest, [System.StringComparer]::Ordinal)
  foreach ($k in $rest) { $o[$k] = $Obj[$k] }
  return $o
}

function Test-EmptyValue($V) {
  if ($null -eq $V) { return $true }
  if ($V -is [string]) { return ($V -eq '') }
  if (($V -is [System.Collections.IEnumerable]) -and -not ($V -is [System.Collections.IDictionary])) { return (@($V).Count -eq 0) }
  return $false
}

function ConvertTo-CanonicalEntry {
  param([Parameter(Mandatory)][System.Collections.IDictionary]$Entry, [Parameter(Mandatory)][string[]]$KeyOrder)
  $e = ConvertTo-OrderedObject $Entry
  $out = [ordered]@{}
  $all = @($KeyOrder) + @($e.Keys | Where-Object { $KeyOrder -notcontains $_ } | Sort-Object)
  foreach ($k in $all) {
    if ($k -eq 'surfaces' -and -not $e.Contains($k)) { $out[$k] = @(); continue }
    if (-not $e.Contains($k)) { continue }
    $v = $e[$k]
    # surfaces is REQUIRED by the schema and a planned entry legitimately has
    # none, so an empty surfaces array is written as [] rather than omitted.
    if ($k -eq 'surfaces' -and (Test-EmptyValue $v)) { $out[$k] = @(); continue }
    if (Test-EmptyValue $v) { continue }
    switch ($k) {
      'related'      { $v = Sort-OrdinalUnique ([string[]]@($v)) }
      'aliases'      { $v = Sort-OrdinalUnique ([string[]]@($v)) }
      'surfaces'     { $v = @(foreach ($s in @($v)) { $t = [string]$s['type']; $order = if ($script:SurfaceKeys.Contains($t)) { $script:SurfaceKeys[$t] } else { @('type') }; Select-OrderedKeys $s $order }) }
      'examples'     { $v = @(foreach ($x in @($v)) { Select-OrderedKeys $x $script:ExampleKeys }) }
      'lastVerified' { $v = Select-OrderedKeys $v $script:LastVerifiedKeys }
      'requires'     { $v = @($v | ForEach-Object { [string]$_ }) }
      'tests'        { $v = @($v | ForEach-Object { [string]$_ }) }
      'homeOrder'    { $v = [int]$v }
    }
    $out[$k] = $v
  }
  return $out
}

function Test-AsciiCrlfFile {
  param([Parameter(Mandatory)][string]$Path)
  $b = [IO.File]::ReadAllBytes($Path)
  if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { return "${Path}: BOM" }
  $line = 1
  for ($i = 0; $i -lt $b.Length; $i++) {
    if ($b[$i] -gt 127) { return ("{0}:{1}: non-ASCII byte 0x{2:X2}" -f $Path, $line, $b[$i]) }
    if ($b[$i] -eq 10) { if ($i -eq 0 -or $b[$i - 1] -ne 13) { return "$Path`: LF line ending at line $line" }; $line++ }
  }
  if ($b.Length -gt 0 -and -not ($b[$b.Length - 1] -eq 10)) { return "$Path`: no trailing newline" }
  return ''
}

function Read-FeatureEntry {
  param([Parameter(Mandatory)][string]$Path)
  $b = [IO.File]::ReadAllBytes($Path)
  for ($i = 0; $i -lt $b.Length; $i++) { if ($b[$i] -gt 127) { throw ("{0}: non-ASCII byte 0x{1:X2} at byte {2}" -f $Path, $b[$i], $i) } }
  $raw = [Text.Encoding]::ASCII.GetString($b)
  $obj = $raw | ConvertFrom-Json -AsHashtable -Depth 16
  return [pscustomobject]@{ Path = $Path; Stem = [IO.Path]::GetFileNameWithoutExtension($Path); Entry = (ConvertTo-OrderedObject $obj); Raw = $raw }
}

function Write-FeatureEntry {
  param([Parameter(Mandatory)][System.Collections.IDictionary]$Entry, [Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string[]]$KeyOrder)
  $text = ConvertTo-CanonicalJson -Value (ConvertTo-CanonicalEntry -Entry $Entry -KeyOrder $KeyOrder)
  $old = if (Test-Path -LiteralPath $Path) { [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($Path)) } else { $null }
  if ($old -ceq $text) { return $false }
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  [IO.File]::WriteAllText($Path, $text, [Text.Encoding]::ASCII)
  return $true
}

function Test-EntryCanonicalBytes {
  param([Parameter(Mandatory)]$Read, [Parameter(Mandatory)][string[]]$KeyOrder)
  $canon = ConvertTo-CanonicalJson -Value (ConvertTo-CanonicalEntry -Entry $Read.Entry -KeyOrder $KeyOrder)
  if ($Read.Raw -ceq $canon) { return '' }
  $n = [Math]::Min($Read.Raw.Length, $canon.Length); $at = $n
  for ($i = 0; $i -lt $n; $i++) { if ($Read.Raw[$i] -cne $canon[$i]) { $at = $i; break } }
  return ("{0}: not canonical (first difference at byte {1}); run tools\feature-registry.ps1 normalise" -f $Read.Path, $at)
}

# ---------------------------------------------------------------------------
# Context and validation
# ---------------------------------------------------------------------------
function Get-RegistryContext {
  param([Parameter(Mandatory)]$Paths, [string[]]$ExtraIds = @(), [System.Collections.Generic.HashSet[string]]$SeedBacklog = $null)
  $groups = [ordered]@{}
  $gj = Get-Content -LiteralPath $Paths.Groups -Raw | ConvertFrom-Json
  foreach ($g in @($gj.groups | Sort-Object order)) { $groups[[string]$g.id] = $g }
  $teams = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
  $tj = Get-Content -LiteralPath $Paths.Teams -Raw | ConvertFrom-Json
  foreach ($t in @($tj.teams)) { [void]$teams.Add([string]$t.id) }
  $vers = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
  foreach ($m in [regex]::Matches((Get-Content -LiteralPath $Paths.Changelog -Raw), '(?m)^## v(\d+\.\d+\.\d+(?:-alpha)?)')) { [void]$vers.Add($m.Groups[1].Value) }
  $pages = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
  foreach ($f in (Get-ChildItem -LiteralPath $Paths.Wiki -Filter '*.md' -File)) { [void]$pages.Add($f.BaseName) }
  $entries = New-Object 'System.Collections.Generic.List[object]'
  if (Test-Path -LiteralPath $Paths.Entries) {
    foreach ($f in (Get-ChildItem -LiteralPath $Paths.Entries -Filter '*.json' -File | Sort-Object Name)) { $entries.Add((Read-FeatureEntry -Path $f.FullName)) }
  }
  $known = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
  foreach ($r in $entries) { [void]$known.Add($r.Stem) }
  foreach ($x in $ExtraIds) { [void]$known.Add($x) }
  if ($null -eq $SeedBacklog) {
    $SeedBacklog = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    if (Test-Path -LiteralPath $Paths.SeedBacklog) {
      $bj = Get-Content -LiteralPath $Paths.SeedBacklog -Raw | ConvertFrom-Json
      foreach ($team in $bj.teams.PSObject.Properties) { foreach ($id in @($team.Value)) { [void]$SeedBacklog.Add([string]$id) } }
    }
  }
  $ex = [ordered]@{ verbs = [ordered]@{}; captions = [ordered]@{}; exes = [ordered]@{} }
  if (Test-Path -LiteralPath $Paths.Exemptions) { $ex = ConvertTo-OrderedObject (Get-Content -LiteralPath $Paths.Exemptions -Raw | ConvertFrom-Json -AsHashtable) }
  return [pscustomobject]@{
    Paths = $Paths; KeyOrder = @(Get-EntryKeyOrder -Paths $Paths)
    SchemaJson = (Get-Content -LiteralPath (Join-Path $Paths.Schema 'entry.schema.json') -Raw)
    Groups = $groups; Teams = $teams; ChangelogVersions = $vers; WikiPages = $pages
    Entries = $entries; KnownIds = $known; SeedBacklog = $SeedBacklog; Exemptions = $ex
  }
}

function Get-NearestCandidates {
  param([string]$Value, [string[]]$Candidates, [int]$Top = 3)
  $scored = foreach ($c in @($Candidates)) {
    $a = $Value.ToLowerInvariant(); $b = $c.ToLowerInvariant()
    $d = New-Object 'int[,]' ($a.Length + 1), ($b.Length + 1)
    for ($i = 0; $i -le $a.Length; $i++) { $d[$i, 0] = $i }
    for ($j = 0; $j -le $b.Length; $j++) { $d[0, $j] = $j }
    for ($i = 1; $i -le $a.Length; $i++) { for ($j = 1; $j -le $b.Length; $j++) {
      $cost = if ($a[$i - 1] -eq $b[$j - 1]) { 0 } else { 1 }
      $d[$i, $j] = [Math]::Min([Math]::Min($d[($i - 1), $j] + 1, $d[$i, ($j - 1)] + 1), $d[($i - 1), ($j - 1)] + $cost)
    } }
    [pscustomobject]@{ C = $c; D = $d[$a.Length, $b.Length] }
  }
  return ,@($scored | Sort-Object D, C | Select-Object -First $Top | ForEach-Object { $_.C })
}

function Get-EntryList([System.Collections.IDictionary]$E, [string]$K) {
  # @($null) is a ONE-element array in PowerShell; a missing key must read as empty.
  if ($E.Contains($K) -and $null -ne $E[$K]) { return ,@($E[$K]) }
  return ,@()
}

function Test-RepoRelativeExists($Paths, [string]$Rel) {
  if ([string]::IsNullOrWhiteSpace($Rel)) { return $false }
  if ([IO.Path]::IsPathRooted($Rel)) { return $false }
  return (Test-Path -LiteralPath (Join-Path $Paths.Repo $Rel))
}

function Test-FeatureEntry {
  param([Parameter(Mandatory)][System.Collections.IDictionary]$Entry, [Parameter(Mandatory)]$Context, [Parameter(Mandatory)][string]$Stem, [switch]$Child)
  $p = New-Object 'System.Collections.Generic.List[string]'
  $e = ConvertTo-OrderedObject $Entry
  $id = [string]$e['id']
  $tag = if ($Child) { "child $id" } else { "$Stem.json" }
  $allowed = @($Context.KeyOrder) + $(if ($Child) { $script:ChildOnlyKeys } else { @() })
  foreach ($k in $e.Keys) { if ($allowed -notcontains $k) { $p.Add("${tag}: unknown key '$k' (not in entry.schema.json)") } }
  $probe = [ordered]@{}; foreach ($k in $e.Keys) { if ($Context.KeyOrder -contains $k) { $probe[$k] = $e[$k] } }
  $json = ConvertTo-CanonicalJson -Value $probe
  $jsonErr = $null
  $ok = Test-Json -Json $json -Schema $Context.SchemaJson -ErrorAction SilentlyContinue -ErrorVariable jsonErr
  if (-not $ok) { foreach ($er in @($jsonErr)) { $p.Add("${tag}: schema: " + ($er.ToString() -replace '\s+', ' ')) } }
  if (-not $Child) {
    if ($id -ne $Stem) { $p.Add("${tag}: id '$id' must equal the filename stem '$Stem'") }
    if ($id -like '*.*') { $p.Add("${tag}: id '$id' contains '.'; importers own rule.<id> and chart.<id>, hand ids never contain a dot") }
  }
  $group = [string]$e['group']
  if (-not $Context.Groups.Contains($group)) { $p.Add("${tag}: group '$group' is not in groups.json (one of: $($Context.Groups.Keys -join ' '))") }
  $owner = [string]$e['owner']
  if (-not $Context.Teams.Contains($owner)) { $p.Add("${tag}: owner '$owner' is not in teams.json (one of: $(@($Context.Teams) -join ' ')); add it with feature-registry.ps1 add -NewTeam") }
  $status = [string]$e['status']
  $inBacklog = $Context.SeedBacklog.Contains($id)
  $since = [string]$e['since']
  if ($status -eq 'shipped' -and -not $since) { $p.Add("${tag}: since is required for a shipped entry") }
  if ($since -and -not $Context.ChangelogVersions.Contains($since)) {
    if (-not ($since -eq '0.0.0' -and $inBacklog)) { $p.Add("${tag}: since '$since' is not a '## v<version>' heading in CHANGELOG.md") }
  }
  $summary = [string]$e['summary']
  if ($summary.EndsWith('.')) { $p.Add("${tag}: summary ends with a period; the Quick-Help line carries none") }
  if (-not $Child -and $status -eq 'shipped' -and -not $inBacklog -and -not $e.Contains('intro')) { $p.Add("${tag}: intro is required for a shipped entry (seeded entries are exempt while listed in seed-backlog.json)") }
  $page = [string]$e['wikiPage']
  if ($page -and -not $Context.WikiPages.Contains($page)) {
    $near = Get-NearestCandidates -Value $page -Candidates @($Context.WikiPages) -Top 3
    $p.Add("${tag}: wikiPage '$page' -- no such page in docs\wiki (exact case; did you mean: $($near -join ', '))")
  }
  $surfaces = Get-EntryList $e 'surfaces'
  if ($status -in @('shipped', 'experimental', 'internal', 'deprecated') -and $surfaces.Count -eq 0) { $p.Add("${tag}: surfaces must hold at least one surface for status '$status'") }
  foreach ($s in $surfaces) {
    if (-not ($s -is [System.Collections.IDictionary])) { $p.Add("${tag}: surfaces[] item is not an object"); continue }
    $t = [string]$s['type']
    if (-not $script:SurfaceKeys.Contains($t)) { $p.Add("${tag}: surface type '$t' unknown"); continue }
    foreach ($k in $s.Keys) { if ($script:SurfaceKeys[$t] -notcontains $k) { $p.Add("${tag}: surface '$t' has unknown key '$k'") } }
    foreach ($k in $script:SurfaceRequired[$t]) { if (-not $s.Contains($k) -or [string]::IsNullOrWhiteSpace([string]$s[$k])) { $p.Add("${tag}: surface '$t' is missing required key '$k'") } }
    switch ($t) {
      'cli'         { if ([string]$s['verb'] -notmatch '^[a-z][a-z0-9-]*$') { $p.Add("${tag}: cli verb '$($s['verb'])' is not a verb token") } }
      'ide-menu'    { if ([string]$s['path'] -notlike 'drag-lint > *') { $p.Add("${tag}: ide-menu path must start 'drag-lint > ' (full path, every level)") } }
      'tool-window' { if ([string]$s['path'] -notlike 'View > Tool Windows > *') { $p.Add("${tag}: tool-window path must start 'View > Tool Windows > '") } }
      'ide-context' { if ($script:ContextHosts -notcontains [string]$s['host']) { $p.Add("${tag}: ide-context host '$($s['host'])' must be one of: $($script:ContextHosts -join ', ')") } }
      'script'      { if (-not (Test-RepoRelativeExists $Context.Paths ([string]$s['path']))) { $p.Add("${tag}: script path '$($s['path'])' does not exist (repo-relative)") } }
      'workflow'    { if (-not (Test-RepoRelativeExists $Context.Paths ([string]$s['doc']))) { $p.Add("${tag}: workflow doc '$($s['doc'])' does not exist (repo-relative)") } }
      'exe'         { if ([string]$s['name'] -notlike '*.exe') { $p.Add("${tag}: exe name '$($s['name'])' must end in .exe") } }
    }
  }
  foreach ($x in (Get-EntryList $e 'examples')) {
    if (-not ($x -is [System.Collections.IDictionary])) { continue }
    $kind = [string]$x['kind']
    if ($kind -eq 'command' -and [string]::IsNullOrWhiteSpace([string]$x['text'])) { $p.Add("${tag}: a command example needs 'text'") }
    if ($kind -in @('file', 'image') -and -not (Test-RepoRelativeExists $Context.Paths ([string]$x['path']))) { $p.Add("${tag}: example path '$($x['path'])' does not exist (repo-relative)") }
  }
  foreach ($rid in (Get-EntryList $e 'related')) {
    if ([string]$rid -eq $id) { $p.Add("${tag}: related names itself") }
    elseif (-not $Context.KnownIds.Contains([string]$rid)) {
      $near = Get-NearestCandidates -Value ([string]$rid) -Candidates @($Context.KnownIds) -Top 3
      $p.Add("${tag}: related '$rid' is not a registered id (did you mean: $($near -join ', '))")
    }
  }
  if ($e.Contains('supersededBy') -and $status -ne 'deprecated') { $p.Add("${tag}: supersededBy is only valid with status deprecated") }
  if ($e.Contains('removedIn') -and $status -ne 'deprecated') { $p.Add("${tag}: removedIn is only valid with status deprecated") }
  if ($e.Contains('supersededBy') -and -not $Context.KnownIds.Contains([string]$e['supersededBy'])) { $p.Add("${tag}: supersededBy '$($e['supersededBy'])' is not a registered id") }
  if ($e.Contains('family') -and -not (Test-Path -LiteralPath (Join-Path $Context.Paths.Families ([string]$e['family'] + '.json')))) { $p.Add("${tag}: family '$($e['family'])' has no features\families\<family>.json") }
  if ($e.Contains('lastVerified')) {
    $lv = $e['lastVerified']
    $d = [datetime]::MinValue
    if (-not [datetime]::TryParseExact([string]$lv['date'], 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$d)) { $p.Add("${tag}: lastVerified.date '$($lv['date'])' is not yyyy-MM-dd") }
    elseif ($d.Date -gt (Get-Date).Date) { $p.Add("${tag}: lastVerified.date '$($lv['date'])' is in the future") }
    if (-not $Context.ChangelogVersions.Contains([string]$lv['build'])) { $p.Add("${tag}: lastVerified.build '$($lv['build'])' is not a CHANGELOG version") }
  } elseif (-not $Child -and $status -eq 'shipped' -and -not $inBacklog) {
    $p.Add("${tag}: lastVerified is required for a shipped entry (seeded entries are exempt while listed in seed-backlog.json)")
  }
  foreach ($tp in (Get-EntryList $e 'tests')) { if (-not (Test-RepoRelativeExists $Context.Paths ([string]$tp))) { $p.Add("${tag}: tests path '$tp' does not exist") } }
  return [string[]]$p.ToArray()
}

function Test-GroupsAndTeams {
  param([Parameter(Mandatory)]$Context, [switch]$RequireNonEmptyGroups)
  $p = New-Object 'System.Collections.Generic.List[string]'
  $schema = Get-Content -LiteralPath (Join-Path $Context.Paths.Schema 'groups.schema.json') -Raw
  foreach ($file in @($Context.Paths.Groups, $Context.Paths.Teams)) {
    $raw = Get-Content -LiteralPath $file -Raw
    $err = $null
    if (-not (Test-Json -Json $raw -Schema $schema -ErrorAction SilentlyContinue -ErrorVariable err)) { foreach ($x in @($err)) { $p.Add("$file`: " + ($x.ToString() -replace '\s+', ' ')) } }
    $asc = Test-AsciiCrlfFile -Path $file; if ($asc) { $p.Add($asc) }
  }
  $ids = @($Context.Groups.Keys); $orders = @($Context.Groups.Values | ForEach-Object { [int]$_.order })
  if (@($ids | Sort-Object -Unique).Count -ne $ids.Count) { $p.Add('groups.json: duplicate group id') }
  if (@($orders | Sort-Object -Unique).Count -ne $orders.Count) { $p.Add('groups.json: duplicate group order') }
  foreach ($g in $ids) { if ($g -notmatch '^[a-z][a-z0-9-]*$') { $p.Add("groups.json: group id '$g' is not kebab-case") } }
  if ($RequireNonEmptyGroups -and $Context.Entries.Count -gt 0) {
    foreach ($g in $ids) {
      if (@($Context.Entries | Where-Object { [string]$_.Entry['group'] -eq $g }).Count -eq 0) { $p.Add("groups.json: group '$g' has no entries -- a group is created by registering into it and deleted when it empties") }
    }
  }
  return [string[]]$p.ToArray()
}

Export-ModuleMember -Function Get-RegistryPaths, ConvertTo-OrderedObject, ConvertTo-CanonicalJson, Sort-OrdinalUnique, Get-EntryKeyOrder, ConvertTo-CanonicalEntry, Get-EntryList, Test-AsciiCrlfFile, Read-FeatureEntry, Write-FeatureEntry, Test-EntryCanonicalBytes, Get-RegistryContext, Get-NearestCandidates, Test-FeatureEntry, Test-GroupsAndTeams
