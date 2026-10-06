#Requires -Version 7.3
<#
  FeatureRegistry.psm1 -- the ONE place the feature registry's schema, canonical
  form, validation, live harvest, importers, checks and renderers live.
  tools\feature-registry.ps1, tools\build-feature-pages.ps1 and
  tests\autotest\run_feature_registry_guard.ps1 are thin callers of this module.
  Spec: docs\superpowers\specs\2026-10-05-feature-registry-design.md

  Array-return convention (two shapes; do not mix them up at a call site):
  * UNROLLED -- Get-EntryKeyOrder, Test-FeatureEntry, Test-GroupsAndTeams,
    Import-LintRuleFamily, Import-ChartQuestionFamily.
    The array goes down the pipeline element by element. Callers MUST wrap
    the call in @(...): an empty result is $null otherwise, and .Count on
    $null throws under StrictMode.
  * WRAPPED (return ,@(...)) -- Get-NearestCandidates, Get-EntryList,
    Sort-OrdinalUnique, Find-FeatureEntry, Get-FeatureBlastRadius,
    Move-FeatureMenuPath, Invoke-RegistryNormalise (and the internal
    Get-AllRegistryItems, Read-RegistryList, Get-FamilyMenuPrefixes).
    The array arrives as ONE object, intact even when empty or single-element. Assign it directly; wrapping it in @(...)
    yields a one-element array holding the array.
    Test-LastVerifiedValue (module-internal) is UNROLLED too.
  * UNROLLED too: Get-ChildIdsIfNeeded (module-internal).
  * SINGLE OBJECT -- Read-FamilyDefinition and Get-RegistryChildren return one
    [ordered] dictionary; Get-RegistryChildren's values are object[] child
    lists (familyId -> children), already safe to .Count.
  * SINGLE OBJECT also: Invoke-RegistryCheck ({ Failures; Notes; Stats }), Get-EntrySkeleton ([string]),
    ConvertFrom-SurfaceSpec ([ordered] surface), and the [string] returns of
    New-FeatureEntry / Update-FeatureEntry / Set-FeatureDeprecated (file path).
  * Generator (Task 5): Get-RegistryModel and Invoke-RegistryGenerate return
    ONE [pscustomobject]; Update-MarkedBlock, Get-DiffHead and the internal
    Render-* functions return ONE [string] (CRLF). Sort-ByOrdinalKey
    (internal) is WRAPPED. Render-* stay module-internal because 'Render' is
    not an approved verb (exporting them would make Import-Module warn).
  Sort-OrdinalUnique, New-RegistryListAddition, Read-RegistryList,
  Get-FamilyMenuPrefixes, ConvertTo-RegistryListJson, Get-ChildIdsIfNeeded, Get-AllRegistryItems and
  Test-MenuNodeCovers are module-internal (not exported), as are the check's
  helpers Get-LeafKey, Get-ExemptionMap, Test-RegistryCaptionMatch ([bool]) and Get-NearestCaption (WRAPPED). Family children carry
  child-only keys (parent, subgroup, emitter, wikiAnchor) and are NEVER
  written under features\entries\.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The caption/verb harvest is SHARED with run_docs_sync_guard.ps1 (Task 2 adds
# the file). Dot-sourced once at module load, from the module's own repo, so
# Get-CaptionKey / Get-LiveMenuCaptions / Get-HelpVerbList / Test-CaptionKeyMatch
# are one definition for both guards. Get-LiveSurface re-loads it if absent.
# Test-CaptionKeyMatch is docs-sync's LOOSE rule (abbreviated prose); checks B
# and C here use the stricter module-internal Test-RegistryCaptionMatch.
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
# get_Keys(), never .Keys, on a dictionary whose keys are DATA: a shortcut
# surface has a key named 'keys', and PowerShell member access then returns
# that entry's VALUE instead of the key collection ({"Ctrl+Alt+F": null}).
# The same holds for group ids, entry stems, family ids and file paths (a
# group named 'keys' or 'values' is legal kebab-case). .Keys is left only on
# dictionaries with a FIXED, code-literal key set: $script:SurfaceKeys (surface
# types), the Feature-Index $sections and the generator's $outputs.
function ConvertTo-OrderedObject {
  param([AllowNull()]$Value)
  if ($null -eq $Value) { return $null }
  if ($Value -is [string] -or $Value -is [bool] -or $Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) { return $Value }
  if ($Value -is [System.Collections.Specialized.OrderedDictionary]) {
    $o = [ordered]@{}; foreach ($k in $Value.get_Keys()) { $o[[string]$k] = ConvertTo-OrderedObject $Value[$k] }; return $o
  }
  if ($Value -is [System.Collections.IDictionary]) {
    $o = [ordered]@{}; $ks = [string[]]@($Value.get_Keys()); [Array]::Sort($ks, [System.StringComparer]::Ordinal)
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
    $keys = @($V.get_Keys() | ForEach-Object { [string]$_ })
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
  $rest = [string[]]@($Obj.get_Keys() | Where-Object { $Order -notcontains $_ }); [Array]::Sort($rest, [System.StringComparer]::Ordinal)
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
  $all = @($KeyOrder) + @($e.get_Keys() | Where-Object { $KeyOrder -notcontains $_ } | Sort-Object)
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
    if ($b[$i] -eq 13 -and ($i + 1 -ge $b.Length -or $b[$i + 1] -ne 10)) { return "$Path`: lone CR at line $line" }
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

# Shared by entries (Test-FeatureEntry) and family definitions
# (Read-FamilyDefinition -Context): a real yyyy-MM-dd date, not in the future,
# and a build that is a '## v<version>' heading in CHANGELOG.md. The key SHAPE
# (date/by/build, nothing else) is the schema's job for an entry and
# Read-FamilyDefinition's for a family. Returns string[] (UNROLLED).
function Test-LastVerifiedValue([System.Collections.IDictionary]$Value, $Context, [string]$Tag) {
  $p = New-Object 'System.Collections.Generic.List[string]'
  $d = [datetime]::MinValue
  if (-not [datetime]::TryParseExact([string]$Value['date'], 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$d)) { $p.Add("${Tag}: lastVerified.date '$($Value['date'])' is not yyyy-MM-dd") }
  elseif ($d.Date -gt (Get-Date).Date) { $p.Add("${Tag}: lastVerified.date '$($Value['date'])' is in the future") }
  if (-not $Context.ChangelogVersions.Contains([string]$Value['build'])) { $p.Add("${Tag}: lastVerified.build '$($Value['build'])' is not a CHANGELOG version") }
  return [string[]]$p.ToArray()
}

function Test-FeatureEntry {
  # -Child: an importer-generated family child. Its id is '<prefix>.<source id>'
  # (rule.<id>, chart.<id>), so the schema's id pattern is applied to the part
  # after the prefix. -SinceOverride: the child's 'since' came from a per-child
  # override, which spec 7 exempts from the CHANGELOG-heading check.
  param([Parameter(Mandatory)][System.Collections.IDictionary]$Entry, [Parameter(Mandatory)]$Context, [Parameter(Mandatory)][string]$Stem, [switch]$Child, [switch]$SinceOverride)
  $p = New-Object 'System.Collections.Generic.List[string]'
  $e = ConvertTo-OrderedObject $Entry
  $id = [string]$e['id']
  $tag = if ($Child) { "child $id" } else { "$Stem.json" }
  $allowed = @($Context.KeyOrder) + $(if ($Child) { $script:ChildOnlyKeys } else { @() })
  foreach ($k in $e.get_Keys()) { if ($allowed -notcontains $k) { $p.Add("${tag}: unknown key '$k' (not in entry.schema.json)") } }
  $probe = [ordered]@{}; foreach ($k in $e.get_Keys()) { if ($Context.KeyOrder -contains $k) { $probe[$k] = $e[$k] } }
  if ($Child -and $probe.Contains('id')) {
    if ($id -match '^(?:rule|chart)\.(.+)$') { $probe['id'] = $Matches[1] }
    else { $p.Add("${tag}: child id '$id' must be rule.<id> or chart.<id>") }
  }
  $json = ConvertTo-CanonicalJson -Value $probe
  $jsonErr = $null
  $ok = Test-Json -Json $json -Schema $Context.SchemaJson -ErrorAction SilentlyContinue -ErrorVariable jsonErr
  if (-not $ok) { foreach ($er in @($jsonErr)) { $p.Add("${tag}: schema: " + ($er.ToString() -replace '\s+', ' ')) } }
  if (-not $Child) {
    if ($id -ne $Stem) { $p.Add("${tag}: id '$id' must equal the filename stem '$Stem'") }
    if ($id -like '*.*') { $p.Add("${tag}: id '$id' contains '.'; importers own rule.<id> and chart.<id>, hand ids never contain a dot") }
  }
  $group = [string]$e['group']
  if (-not $Context.Groups.Contains($group)) { $p.Add("${tag}: group '$group' is not in groups.json (one of: $($Context.Groups.get_Keys() -join ' '))") }
  $owner = [string]$e['owner']
  if (-not $Context.Teams.Contains($owner)) { $p.Add("${tag}: owner '$owner' is not in teams.json (one of: $(@($Context.Teams) -join ' ')); add it with feature-registry.ps1 add -NewTeam") }
  $status = [string]$e['status']
  $inBacklog = $Context.SeedBacklog.Contains($id)
  $since = [string]$e['since']
  if ($status -eq 'shipped' -and -not $since) { $p.Add("${tag}: since is required for a shipped entry") }
  if ($since -and -not ($Child -and $SinceOverride) -and -not $Context.ChangelogVersions.Contains($since)) {
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
    foreach ($k in $s.get_Keys()) { if ($script:SurfaceKeys[$t] -notcontains $k) { $p.Add("${tag}: surface '$t' has unknown key '$k'") } }
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
    foreach ($x in @(Test-LastVerifiedValue -Value $e['lastVerified'] -Context $Context -Tag $tag)) { $p.Add($x) }
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
  $ids = @($Context.Groups.get_Keys()); $orders = @($Context.Groups.get_Values() | ForEach-Object { [int]$_.order })
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

# ---------------------------------------------------------------------------
# The live surface (spec 3, 6.1): one object, every harvest non-empty or throw
# ---------------------------------------------------------------------------
function Get-LiveSurface {
  param([Parameter(Mandatory)]$Paths)
  . $Paths.SubMapLib
  if (-not (Get-Command Get-CaptionKey -ErrorAction SilentlyContinue)) { . $script:HarvestLibPath }
  if (-not (Test-Path -LiteralPath $Paths.Exe)) { throw "live surface: engine exe not found: $($Paths.Exe) (full path; a bare 'drag-lint' resolves off PATH to a stale build)" }
  # stdout only: --version and --help put '(loaded defaults from ...)' on stderr.
  $helpText = (& $Paths.Exe --help 2>$null | Out-String)
  $helpVerbs = @(Get-HelpVerbList -HelpText $helpText)
  if ($helpVerbs.Count -le 20) { throw "live surface: --help yielded $($helpVerbs.Count) verb(s); expected > 20 -- the harvest is broken, not the CLI" }
  $cliSrc = Get-Content -LiteralPath $Paths.CliPas -Raw
  $dispatch = @([regex]::Matches($cliSrc, "Args\.Command\s*=\s*'([a-z][a-z0-9-]*)'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
  if ($dispatch.Count -le 20) { throw "live surface: dispatch scan yielded $($dispatch.Count) verb(s); expected > 20" }
  $subMap = Get-CliVerbSubcommandMap -CliPath $Paths.CliPas
  # Dialog buttons (TButton / TBitBtn / TSpeedButton captions: 'Go To', 'Fix',
  # 'Cancel') are harvested APART: they are not features, so check B never asks
  # for them and no exemption is needed. Check C still accepts them as live for an
  # ide-about surface (a button of the About window is a dialog button).
  $captions = Get-LiveMenuCaptions -Repo $Paths.Repo -ExcludeDialogButtons
  $dialogButtons = [string[]]@(Get-LiveDialogButtonCaptions -Repo $Paths.Repo)
  if ($captions.Count -lt 40) { throw "live surface: $($captions.Count) caption(s) harvested; expected >= 40" }
  $captionKeys = @($captions | ForEach-Object { Get-CaptionKey -S $_ } | Where-Object { $_ })
  $aboutSrc = Get-Content -LiteralPath (Join-Path $Paths.Repo 'src\delphi-plugin\DragLint.Plugin.AboutForm.pas') -Raw
  $aboutButtons = @([regex]::Matches($aboutSrc, "Add(?:Proc)?Button\(\s*'([^']+)'") | ForEach-Object { $_.Groups[1].Value.Replace('&&', '&').Trim() } | Sort-Object -Unique)
  # Context-menu captions, per ide-context host (spec 6.1). They are NOT in
  # Captions: the docs-sync harvest reads the main-menu sources only, and a
  # context item checked against main-menu captions passes or fails by
  # coincidence. Single '&' is an accelerator here and is dropped; '&&' is a
  # literal '&'. A host with no harvester is absent (check C names it).
  $ctxCaps = [ordered]@{}
  $sfSrc = Get-Content -LiteralPath (Join-Path $Paths.Repo 'src\delphi-plugin\DragLint.Plugin.StructureForm.pas') -Raw
  $ctxCaps['Structure form'] = [string[]]@([regex]::Matches($sfSrc, "AddPopupItem\(\s*\w+\s*,\s*'([^']+)'") | ForEach-Object { (($_.Groups[1].Value -replace '&&', "`u{1}") -replace '&', '' -replace "`u{1}", '&').Trim() } | Where-Object { $_ -ne '-' } | Sort-Object -Unique)
  $pmSrc = Get-Content -LiteralPath (Join-Path $Paths.Repo 'src\delphi-plugin\DragLint.Plugin.ProjectMenu.pas') -Raw
  $ctxCaps['Project Manager'] = [string[]]@([regex]::Matches($pmSrc, "MENU_CAPTION\s*=\s*'([^']+)'") | ForEach-Object { (($_.Groups[1].Value -replace '&&', "`u{1}") -replace '&', '' -replace "`u{1}", '&').Trim() })
  foreach ($h in @($ctxCaps.get_Keys())) { if ($ctxCaps[$h].Count -eq 0) { throw "live surface: 0 context-menu captions harvested for host '$h'" } }
  $mcpSrc = Get-Content -LiteralPath $Paths.McpServer -Raw
  $mcpTools = @([regex]::Matches($mcpSrc, "ToolDescriptor\(\s*'([a-z_]+)'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
  $mcpDispatch = @([regex]::Matches($mcpSrc, "ToolName\s*=\s*'([a-z_]+)'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
  if ($mcpTools.Count -eq 0) { throw 'live surface: 0 MCP tools harvested from HandleToolsList (ToolDescriptor calls)' }
  $catText = (& $Paths.Exe rules --json 2>$null | Out-String)
  $cat = $catText | ConvertFrom-Json
  if ([int]$cat.summary.total -le 0) { throw 'live surface: rules --json reports total 0' }
  $rt = Get-Content -LiteralPath $Paths.ReportText -Raw
  $questions = New-Object 'System.Collections.Generic.List[object]'
  foreach ($m in [regex]::Matches($rt, "\(Id:\s*'([a-z-]+)'\s*;\s*Caption:\s*'([^']+)'\s*;\s*Kind:\s*(rtk\w+)\s*\)")) {
    $questions.Add([pscustomobject]@{ Id = $m.Groups[1].Value; Caption = $m.Groups[2].Value.Replace('&&', '&'); Kind = $m.Groups[3].Value })
  }
  if ($questions.Count -eq 0) { throw 'live surface: 0 REPORT_QUESTIONS rows harvested' }
  $qc = [regex]::Match($rt, 'REPORT_QUESTION_COUNT\s*=\s*(\d+)')
  if (-not $qc.Success) { throw 'live surface: REPORT_QUESTION_COUNT not found' }
  $groupCaptions = @{}
  foreach ($m in [regex]::Matches($rt, "\b(rtk\w+)\s*:\s*Result\s*:=\s*'([^']+)'")) { $groupCaptions[$m.Groups[1].Value] = $m.Groups[2].Value.Replace('&&', '&') }
  # ReportGroupCaption's case has an 'else' arm (rtkName's header today): it
  # captions every Kind the explicit arms do not name.
  $ge = [regex]::Match($rt, "(?s)function ReportGroupCaption\b(?:(?!\b(?:function|procedure)\b).)*?\belse\s+Result\s*:=\s*'([^']+)'\s*;\s*end;")
  if ($ge.Success) {
    foreach ($q in $questions) { if (-not $groupCaptions.ContainsKey($q.Kind)) { $groupCaptions[$q.Kind] = $ge.Groups[1].Value.Replace('&&', '&') } }
  }
  $validateSet = @((Get-Command $Paths.ChartBundler).Parameters['Question'].Attributes |
                   Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
                   ForEach-Object { $_.ValidValues })
  if ($validateSet.Count -eq 0) { throw 'live surface: New-DiagramArtifact.ps1 -Question has no ValidateSet' }
  $emitters = @(Get-ChildItem -LiteralPath $Paths.ChartsDir -Filter 'Emit-*.ps1' -File | Where-Object { $_.Name -ne 'Emit-Common.ps1' } | ForEach-Object { $_.Name } | Sort-Object)
  $packText = Get-Content -LiteralPath $Paths.PackScript -Raw
  $pm = [regex]::Match($packText, "foreach \(\`$need in '([^)]+)'\)")
  $packExes = if ($pm.Success) { @($pm.Groups[1].Value -split "'\s*,\s*'" | ForEach-Object { $_.Trim("'") }) } else { @() }
  if ($packExes.Count -eq 0) { throw 'live surface: pack-lint-release.ps1 payload exe list not found' }
  $core = Get-Content -LiteralPath $Paths.CoreModel -Raw
  $schemaPas = Get-Content -LiteralPath $Paths.SchemaPas -Raw
  $vers = [pscustomobject]@{
    Product   = [regex]::Match($core, "DRAGLINT_VERSION\s*=\s*'([^']+)'").Groups[1].Value
    Extractor = [regex]::Match($core, "DRAGLINT_EXTRACTOR_VERSION\s*=\s*'([^']+)'").Groups[1].Value
    Resolver  = [regex]::Match($core, "DRAGLINT_RESOLVER_VERSION\s*=\s*'([^']+)'").Groups[1].Value
    Schema    = [regex]::Match($schemaPas, 'SCHEMA_VERSION\s*=\s*(\d+)').Groups[1].Value
  }
  if (-not $vers.Product) { throw 'live surface: DRAGLINT_VERSION not found in DRagLint.Core.Model.pas' }
  return [pscustomobject]@{
    HelpText = $helpText; HelpVerbs = $helpVerbs; DispatchVerbs = $dispatch; SubMap = $subMap
    Captions = $captions; CaptionKeys = $captionKeys; AboutButtons = $aboutButtons; DialogButtons = $dialogButtons; ContextCaptions = $ctxCaps
    McpTools = $mcpTools; McpDispatch = $mcpDispatch; RuleCatalog = $cat
    ReportQuestions = $questions; ReportQuestionCount = [int]$qc.Groups[1].Value; GroupCaptions = $groupCaptions
    ChartValidateSet = $validateSet; EmitterFiles = $emitters; PackExes = $packExes; Versions = $vers
  }
}

# ---------------------------------------------------------------------------
# Families (spec 7): imported, never stored under features\entries\
# ---------------------------------------------------------------------------
$script:FamilyImporters = @('lint-rules', 'chart-questions')

# lastVerified (spec 7: the family as a whole; the section-11 review samples by
# it) is REQUIRED and must be exactly {date, by, build} with a non-empty 'by'.
# With -Context the date and build are validated as for an entry
# (Test-LastVerifiedValue); Get-RegistryChildren always passes it.
function Read-FamilyDefinition {
  param([Parameter(Mandatory)][string]$Path, $Context = $null)
  $asc = Test-AsciiCrlfFile -Path $Path; if ($asc) { throw "family definition: $asc" }
  $o = ConvertTo-OrderedObject ((Get-Content -LiteralPath $Path -Raw) | ConvertFrom-Json -AsHashtable -Depth 16)
  foreach ($k in @('family', 'entry', 'children', 'lastVerified')) { if (-not $o.Contains($k)) { throw "$Path`: family definition is missing '$k'" } }
  $lv = $o['lastVerified']
  if (-not ($lv -is [System.Collections.IDictionary])) { throw "$Path`: lastVerified must be an object { date, by, build }" }
  foreach ($k in $lv.get_Keys()) { if ($script:LastVerifiedKeys -notcontains $k) { throw "$Path`: lastVerified has unknown key '$k' (allowed: $($script:LastVerifiedKeys -join ', '))" } }
  foreach ($k in $script:LastVerifiedKeys) { if ([string]::IsNullOrWhiteSpace([string]$lv[$k])) { throw "$Path`: lastVerified.$k is missing or empty" } }
  if ($null -ne $Context) {
    $lvp = @(Test-LastVerifiedValue -Value $lv -Context $Context -Tag $Path)
    if ($lvp.Count -gt 0) { throw ($lvp -join "`n") }
  }
  if (-not $o.Contains('defaults') -or $null -eq $o['defaults']) { $o['defaults'] = [ordered]@{} }
  if ($null -eq $o['children']) { $o['children'] = [ordered]@{} }
  return $o
}

function Get-OverrideValue([System.Collections.IDictionary]$Family, [string]$ChildId, [string]$Key, $Fallback) {
  $ov = $Family['children'][$ChildId]
  if ($null -ne $ov -and $ov.Contains($Key) -and -not (Test-EmptyValue $ov[$Key])) { return $ov[$Key] }
  if ($Family['defaults'].Contains($Key) -and -not (Test-EmptyValue $Family['defaults'][$Key])) { return $Family['defaults'][$Key] }
  return $Fallback
}

function Remove-EmptyKeys([System.Collections.IDictionary]$Obj) {
  foreach ($k in @($Obj.get_Keys())) { if (Test-EmptyValue $Obj[$k]) { $Obj.Remove($k) } }
  return $Obj
}

function Limit-Summary([string]$Text, [string]$Suffix) {
  $t = $Text.TrimEnd('.', ' ')
  $max = 160 - $Suffix.Length
  if ($t.Length -gt $max) { $t = $t.Substring(0, $max - 3).TrimEnd() + '...' }
  $s = $t + $Suffix
  if ($s.Length -lt 20) { $s = $s + ' (lint rule)' }
  return $s
}

function Import-LintRuleFamily {
  param([Parameter(Mandatory)]$Live, [Parameter(Mandatory)][System.Collections.IDictionary]$Family, [Parameter(Mandatory)][System.Collections.IDictionary]$Parent)
  $rules = @($Live.RuleCatalog.rules)
  if ($rules.Count -eq 0) { throw 'lint-rules importer: 0 rules harvested' }
  if ($rules.Count -ne [int]$Live.RuleCatalog.summary.total) { throw "lint-rules importer: $($rules.Count) rule rows vs summary.total $($Live.RuleCatalog.summary.total)" }
  $ids = [string[]]@($rules | ForEach-Object { [string]$_.id })
  foreach ($ov in @($Family['children'].get_Keys())) { if ($ids -cnotcontains $ov) { throw "lint-rules importer: override '$ov' names a rule that no longer exists in rules --json (did you mean: $((Get-NearestCandidates -Value $ov -Candidates $ids) -join ', '))" } }
  $byId = @{}; foreach ($r0 in $rules) { $byId[[string]$r0.id] = $r0 }
  $out = New-Object 'System.Collections.Generic.List[object]'
  foreach ($id in (Sort-OrdinalUnique $ids)) {
    $r = $byId[$id]
    $suffix = ' (' + [string]$r.category + ', ' + [string]$r.default_severity + $(if ($r.fixable) { ', fixable' } else { '' }) + ')'
    $c = [ordered]@{
      id = 'rule.' + $id; title = $id; group = 'linting'; owner = [string]$Parent['owner']; status = 'shipped'
      since = [string](Get-OverrideValue $Family $id 'since' $Parent['since'])
      summary = Limit-Summary ([string]$r.title) $suffix
      wikiPage = [string](Get-OverrideValue $Family $id 'wikiPage' 'rules')
      surfaces = @([ordered]@{ type = 'cli'; verb = 'lint'; example = "drag-lint lint <file.pas> --rule $id" })
      audience = 'both'
      aliases = @(Get-OverrideValue $Family $id 'aliases' @()); related = @(Get-OverrideValue $Family $id 'related' @())
      notes = [string](Get-OverrideValue $Family $id 'notes' '')
      parent = [string]$Parent['id']; wikiAnchor = $id
    }
    $out.Add((Remove-EmptyKeys $c))
  }
  return [object[]]$out.ToArray()
}

function Import-ChartQuestionFamily {
  param([Parameter(Mandatory)]$Live, [Parameter(Mandatory)][System.Collections.IDictionary]$Family, [Parameter(Mandatory)][System.Collections.IDictionary]$Parent, [Parameter(Mandatory)]$Paths)
  # foreach, not @(...): @() over a List[object] throws 'Argument types do not
  # match' on this pwsh (measured 2026-10-05).
  $qs = [object[]]@(foreach ($x in $Live.ReportQuestions) { $x })
  if ($qs.Count -eq 0) { throw 'chart-questions importer: 0 questions harvested from REPORT_QUESTIONS' }
  if ($qs.Count -ne $Live.ReportQuestionCount) { throw "chart-questions importer: $($qs.Count) catalog rows vs REPORT_QUESTION_COUNT = $($Live.ReportQuestionCount)" }
  $menuIds = [string[]]@($qs | ForEach-Object { $_.Id }); $setIds = [string[]]@($Live.ChartValidateSet)
  $noMenu = @($setIds | Where-Object { $menuIds -cnotcontains $_ }); $noScript = @($menuIds | Where-Object { $setIds -cnotcontains $_ })
  if ($noMenu.Count -or $noScript.Count) {
    throw ("chart-questions importer: catalog and ValidateSet differ -- in New-DiagramArtifact.ps1 only: [{0}]; in REPORT_QUESTIONS only: [{1}]" -f ($noMenu -join ' '), ($noScript -join ' '))
  }
  foreach ($ov in @($Family['children'].get_Keys())) { if ($menuIds -cnotcontains $ov) { throw "chart-questions importer: override '$ov' names a question that no longer exists (did you mean: $((Get-NearestCandidates -Value $ov -Candidates $menuIds) -join ', '))" } }
  $out = New-Object 'System.Collections.Generic.List[object]'
  $named = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($q in $qs) {
    $title = ($q.Caption -replace '\.\.\.$', '').Trim()
    # Spec 7: the emitter is OPTIONAL per child and checked for existence when
    # given. It is never derived from the id (who-writes and who-reads share
    # Emit-MemberAccess.ps1); the two-way SET check below catches an emitter
    # script on disk that no child names.
    $emitter = [string](Get-OverrideValue $Family $q.Id 'emitter' '')
    if ($emitter) {
      if (-not (Test-RepoRelativeExists $Paths $emitter)) { throw "chart-questions importer: emitter '$emitter' for '$($q.Id)' does not exist" }
      [void]$named.Add((Split-Path -Leaf $emitter))
    }
    if (-not $Live.GroupCaptions.ContainsKey($q.Kind)) { throw "chart-questions importer: no ReportGroupCaption for Kind $($q.Kind)" }
    $sub = [string]$Live.GroupCaptions[$q.Kind]
    # The submenu the questions hang under is family DATA (defaults.menuPrefix),
    # so move-menu can relocate the whole family in one edit.
    $prefix = [string](Get-OverrideValue $Family $q.Id 'menuPrefix' 'drag-lint > Reports')
    $c = [ordered]@{
      id = 'chart.' + $q.Id; title = $title; group = 'diagrams-charts'; owner = 'CHARTS'; status = 'shipped'
      since = [string](Get-OverrideValue $Family $q.Id 'since' $Parent['since'])
      summary = "$title -- chart question ($sub)"
      wikiPage = [string](Get-OverrideValue $Family $q.Id 'wikiPage' ('ask-' + $q.Id))
      surfaces = @(
        [ordered]@{ type = 'ide-menu'; path = $prefix + ' > ' + $q.Caption },
        [ordered]@{ type = 'script'; path = 'charts\src\Ask-Report.ps1'; args = '-Question ' + $q.Id },
        [ordered]@{ type = 'script'; path = 'charts\src\New-DiagramArtifact.ps1'; args = '-Question ' + $q.Id })
      audience = 'both'
      requires = @(Get-OverrideValue $Family $q.Id 'requires' @())
      aliases = @(Get-OverrideValue $Family $q.Id 'aliases' @()); related = @(Get-OverrideValue $Family $q.Id 'related' @())
      notes = [string](Get-OverrideValue $Family $q.Id 'notes' '')
      tests = @(Get-OverrideValue $Family $q.Id 'tests' @())
      parent = [string]$Parent['id']; subgroup = $sub; emitter = $emitter
    }
    $ho = Get-OverrideValue $Family $q.Id 'homeOrder' $null
    if ($null -ne $ho) { $c['homeOrder'] = [int]$ho }
    $out.Add((Remove-EmptyKeys $c))
  }
  $disk = [string[]]@($Live.EmitterFiles)
  $unnamed = @($disk | Where-Object { -not $named.Contains($_) })
  $ghost = @(@($named) | Sort-Object | Where-Object { $disk -notcontains $_ })
  if ($unnamed.Count -or $ghost.Count) { throw ("chart-questions importer: emitter set drift -- on disk but no child names it: [{0}]; named but not on disk: [{1}]" -f ($unnamed -join ' '), ($ghost -join ' ')) }
  return [object[]]$out.ToArray()
}

function Get-RegistryChildren {
  param([Parameter(Mandatory)]$Live, [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Entries, [Parameter(Mandatory)]$Paths)
  $out = [ordered]@{}
  $familyEntries = @($Entries | Where-Object { $_ -is [System.Collections.IDictionary] -and $_.Contains('family') })
  $defs = @(if (Test-Path -LiteralPath $Paths.Families) { Get-ChildItem -LiteralPath $Paths.Families -Filter '*.json' -File | ForEach-Object { $_.BaseName } })
  foreach ($fe in $familyEntries) {
    $fam = [string]$fe['family']
    if ($defs -cnotcontains $fam) { throw "family '$fam' (entry '$($fe['id'])') has no features\families\$fam.json" }
  }
  foreach ($d in $defs) { if ($script:FamilyImporters -cnotcontains $d) { throw "features\families\$d.json has no importer (known: $($script:FamilyImporters -join ', '))" } }
  # One context: built before the definitions are read (their lastVerified is
  # validated against it), then extended with the child ids for 'related'.
  $ctx = Get-RegistryContext -Paths $Paths -ExtraIds ([string[]]@($Entries | ForEach-Object { [string]$_['id'] }))
  $parents = @{}
  foreach ($fam in $script:FamilyImporters) {
    if ($defs -cnotcontains $fam) { continue }
    $def = Read-FamilyDefinition -Path (Join-Path $Paths.Families "$fam.json") -Context $ctx
    if ([string]$def['family'] -cne $fam) { throw "features\families\$fam.json declares family '$($def['family'])'; it must equal the file name" }
    $parent = @($familyEntries | Where-Object { [string]$_['id'] -ceq [string]$def['entry'] -and [string]$_['family'] -ceq $fam })
    if ($parent.Count -ne 1) { throw "features\families\$fam.json names entry '$($def['entry'])', but no hand entry with id '$($def['entry'])' and family '$fam' exists" }
    $parents[$fam] = $parent[0]
    $kids = if ($fam -eq 'lint-rules') { @(Import-LintRuleFamily -Live $Live -Family $def -Parent $parent[0]) } else { @(Import-ChartQuestionFamily -Live $Live -Family $def -Parent $parent[0] -Paths $Paths) }
    $out[$fam] = $kids
  }
  foreach ($v in $out.get_Values()) { foreach ($c in $v) { [void]$ctx.KnownIds.Add([string]$c['id']) } }
  $problems = New-Object 'System.Collections.Generic.List[string]'
  foreach ($fam in $out.get_Keys()) {
    foreach ($c in $out[$fam]) {
      # A child's since that differs from its parent's came from a per-child
      # override: exempt from the CHANGELOG-heading check (spec 7).
      $ovSince = ([string]$c['since']) -cne ([string]$parents[$fam]['since'])
      foreach ($x in @(Test-FeatureEntry -Entry $c -Context $ctx -Stem ([string]$c['id']) -Child -SinceOverride:$ovSince)) { $problems.Add($x) }
    }
  }
  if ($problems.Count -gt 0) { throw ("family children failed validation:`n" + ($problems -join "`n")) }
  return $out
}

# ---------------------------------------------------------------------------
# Registry engine operations (spec 17)
# ---------------------------------------------------------------------------
function ConvertFrom-SurfaceSpec {
  param([Parameter(Mandatory)][string]$Spec)
  $i = $Spec.IndexOf(':')
  if ($i -lt 1) { throw "surface spec '$Spec': expected <type>:<fields>" }
  $type = $Spec.Substring(0, $i).Trim(); $rest = $Spec.Substring($i + 1).Trim()
  if (-not $script:SurfaceKeys.Contains($type)) { throw "surface spec '$Spec': unknown type '$type' (one of: $($script:SurfaceKeys.Keys -join ' '))" }
  $parts = @($rest -split '\|', 2 | ForEach-Object { $_.Trim() })
  $s = [ordered]@{ type = $type }
  switch ($type) {
    'cli'         { $vs = @($parts[0] -split '/', 2); $s['verb'] = $vs[0]; if ($vs.Count -gt 1 -and $vs[1]) { $s['sub'] = $vs[1] }; if ($parts.Count -gt 1 -and $parts[1]) { $s['example'] = $parts[1] } }
    'ide-menu'    { $s['path'] = $rest }
    'ide-context' { if ($parts.Count -lt 2) { throw "surface spec '$Spec': ide-context needs <host>|<caption>" }; $s['host'] = $parts[0]; $s['caption'] = $parts[1] }
    'ide-about'   { $s['caption'] = $rest }
    'tool-window' { $s['path'] = $rest }
    'shortcut'    { $s['keys'] = $rest }
    'lsp'         { $s['method'] = $rest }
    'mcp'         { $s['tool'] = $rest }
    'script'      { $s['path'] = $parts[0]; if ($parts.Count -gt 1 -and $parts[1]) { $s['args'] = $parts[1] } }
    'exe'         { $s['name'] = $parts[0]; if ($parts.Count -gt 1 -and $parts[1]) { $s['menu'] = $parts[1] } }
    'workflow'    { $s['doc'] = $rest }
  }
  return $s
}

function Get-CurrentBuildVersion {
  param([Parameter(Mandatory)]$Paths)
  $m = [regex]::Match((Get-Content -LiteralPath $Paths.CoreModel -Raw), "DRAGLINT_VERSION\s*=\s*'([^']+)'")
  if (-not $m.Success) { throw "DRAGLINT_VERSION not found in $($Paths.CoreModel)" }
  return $m.Groups[1].Value
}

# groups.json / teams.json canonical layout (spec 5.3): one row per line, keys
# id, title, order, summary. ConvertTo-CanonicalJson would explode every row and
# (ConvertFrom-Json -AsHashtable returns an OrderedHashtable, which
# ConvertTo-OrderedObject sorts) reorder the keys alphabetically.
$script:ListRowKeys = @('id', 'title', 'order', 'summary')
function ConvertTo-RegistryListJson([string]$Key, [object[]]$Rows) {
  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.Append("{`r`n  "); Write-JsonString $sb $Key; [void]$sb.Append(": [`r`n")
  for ($i = 0; $i -lt $Rows.Count; $i++) {
    $r = $Rows[$i]
    foreach ($k in $r.get_Keys()) { if ($script:ListRowKeys -notcontains $k) { throw "$Key[$i]: unknown key '$k' (allowed: $($script:ListRowKeys -join ', '))" } }
    [void]$sb.Append('    { ')
    $first = $true
    foreach ($k in $script:ListRowKeys) {
      if (-not $r.Contains($k)) { continue }
      if (-not $first) { [void]$sb.Append(', ') }; $first = $false
      Write-JsonString $sb $k; [void]$sb.Append(': '); Write-JsonValue $sb $r[$k] 0
    }
    [void]$sb.Append(' }'); if ($i -lt $Rows.Count - 1) { [void]$sb.Append(',') }; [void]$sb.Append("`r`n")
  }
  [void]$sb.Append("  ]`r`n}`r`n")
  return $sb.ToString()
}
function Read-RegistryList([string]$File, [string]$Key) {
  $o = (Get-Content -LiteralPath $File -Raw) | ConvertFrom-Json -AsHashtable -Depth 8
  return ,@(foreach ($x in @($o[$Key])) { $x })
}
# Computes, WITHOUT writing, the new groups.json / teams.json text with one row
# appended (order = max + 10). Returns { File; Text; Row }; the caller writes
# Text once everything else it depends on has been validated.
$script:ListIdRule = @{ groups = @('^[a-z][a-z0-9-]*$', 'kebab-case'); teams = @('^[A-Z][A-Z0-9-]*$', 'UPPER-CASE') }
function New-RegistryListAddition([string]$File, [string]$Key, [string]$Id, [string]$Title, [string]$Summary) {
  if ($Id -cnotmatch $script:ListIdRule[$Key][0]) { throw "$Key`: id '$Id' must be $($script:ListIdRule[$Key][1])" }
  $list = Read-RegistryList $File $Key
  if (@($list | Where-Object { [string]$_['id'] -eq $Id }).Count -gt 0) { throw "$Key`: '$Id' already exists in $File" }
  $max = 0; foreach ($x in $list) { if ([int]$x['order'] -gt $max) { $max = [int]$x['order'] } }
  $row = [ordered]@{ id = $Id; title = $Title; order = ($max + 10); summary = $Summary }
  $list += $row
  return [pscustomobject]@{ File = $File; Text = (ConvertTo-RegistryListJson $Key $list); Row = $row }
}
function Add-RegistryGroup { param([Parameter(Mandatory)]$Paths, [Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][string]$Title, [Parameter(Mandatory)][string]$Summary)
  $a = New-RegistryListAddition $Paths.Groups 'groups' $Id $Title $Summary
  [IO.File]::WriteAllText($a.File, $a.Text, [Text.Encoding]::ASCII) }
function Add-RegistryTeam { param([Parameter(Mandatory)]$Paths, [Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][string]$Title, [Parameter(Mandatory)][string]$Summary)
  $a = New-RegistryListAddition $Paths.Teams 'teams' $Id $Title $Summary
  [IO.File]::WriteAllText($a.File, $a.Text, [Text.Encoding]::ASCII) }

function Get-ChildIdsIfNeeded($Paths, [System.Collections.IDictionary]$Entry, $Context) {
  # Children are only needed when the entry refers to one; Get-LiveSurface costs ~1 s.
  # Get-EntryList is WRAPPED: iterate it, never @(...) it (that nests the array).
  $needs = @(foreach ($x in (Get-EntryList $Entry 'related')) { [string]$x }) + @($(if ($Entry.Contains('supersededBy')) { [string]$Entry['supersededBy'] }))
  if (@($needs | Where-Object { $_ -like 'rule.*' -or $_ -like 'chart.*' }).Count -eq 0) { return @() }
  $live = Get-LiveSurface -Paths $Paths
  $kids = Get-RegistryChildren -Live $live -Entries @($Context.Entries | ForEach-Object { $_.Entry }) -Paths $Paths
  return @($kids.get_Values() | ForEach-Object { $_ } | ForEach-Object { [string]$_['id'] })
}

function New-FeatureEntry {
  param([Parameter(Mandatory)]$Paths, [Parameter(Mandatory)][hashtable]$Fields, [Parameter(Mandatory)][string]$By,
        [switch]$NewGroup, [string]$GroupTitle, [string]$GroupSummary, [switch]$NewTeam, [string]$TeamTitle, [string]$TeamSummary)
  $id = [string]$Fields['id']
  if (-not $id) { throw 'add: -Id is required' }
  $file = Join-Path $Paths.Entries "$id.json"
  if (Test-Path -LiteralPath $file) { throw "add: entry '$id' already exists ($file); use update" }
  # ATOMIC: a new group / team goes into the in-memory context only; the list
  # files are written after the entry has validated, right before the entry.
  $ctx = Get-RegistryContext -Paths $Paths
  $listWrites = New-Object 'System.Collections.Generic.List[object]'
  $group = [string]$Fields['group']; $owner = [string]$Fields['owner']
  if ($group -and -not $ctx.Groups.Contains($group)) {
    if (-not $NewGroup) { throw "add: unknown group '$group' (one of: $($ctx.Groups.get_Keys() -join ' ')); pass -NewGroup -GroupTitle <t> -GroupSummary <s> to create it" }
    if (-not $GroupTitle -or -not $GroupSummary) { throw 'add: -NewGroup needs -GroupTitle and -GroupSummary' }
    $a = New-RegistryListAddition $Paths.Groups 'groups' $group $GroupTitle $GroupSummary
    $listWrites.Add($a); $ctx.Groups[$group] = [pscustomobject]$a.Row
  }
  if ($owner -and -not $ctx.Teams.Contains($owner)) {
    if (-not $NewTeam) { throw "add: unknown owner '$owner' (one of: $(@($ctx.Teams) -join ' ')); pass -NewTeam -TeamTitle <t> -TeamSummary <s> to create it" }
    if (-not $TeamTitle -or -not $TeamSummary) { throw 'add: -NewTeam needs -TeamTitle and -TeamSummary' }
    $a = New-RegistryListAddition $Paths.Teams 'teams' $owner $TeamTitle $TeamSummary
    $listWrites.Add($a); [void]$ctx.Teams.Add($owner)
  }
  $e = [ordered]@{}
  foreach ($k in $ctx.KeyOrder) { if ($Fields.ContainsKey($k) -and -not (Test-EmptyValue $Fields[$k])) { $e[$k] = $Fields[$k] } }
  if (-not $e.Contains('status')) { $e['status'] = 'shipped' }
  if (-not $e.Contains('audience')) { $e['audience'] = 'both' }
  $build = Get-CurrentBuildVersion -Paths $Paths
  if (-not $e.Contains('since') -and $e['status'] -ne 'planned') { $e['since'] = $build }
  if (-not $e.Contains('lastVerified')) { $e['lastVerified'] = [ordered]@{ date = (Get-Date -Format 'yyyy-MM-dd'); by = $By; build = $build } }
  # Extend the SAME context (a fresh Get-RegistryContext would drop the
  # in-memory group / team).
  foreach ($x in @(Get-ChildIdsIfNeeded $Paths $e $ctx)) { [void]$ctx.KnownIds.Add($x) }
  $problems = @(Test-FeatureEntry -Entry $e -Context $ctx -Stem $id)
  if ($problems.Count) { throw ("add: entry '$id' is not valid; nothing written:`n  " + ($problems -join "`n  ")) }
  # Render before the first write: the serialiser throws on non-ASCII.
  [void](ConvertTo-CanonicalJson -Value (ConvertTo-CanonicalEntry -Entry $e -KeyOrder $ctx.KeyOrder))
  foreach ($a in $listWrites) { [IO.File]::WriteAllText($a.File, $a.Text, [Text.Encoding]::ASCII) }
  [void](Write-FeatureEntry -Entry $e -Path $file -KeyOrder $ctx.KeyOrder)
  return $file
}

function Update-FeatureEntry {
  param([Parameter(Mandatory)]$Paths, [Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][hashtable]$Set)
  $file = Join-Path $Paths.Entries "$Id.json"
  if (-not (Test-Path -LiteralPath $file)) { throw "update: no entry '$Id' ($file)" }
  $r = Read-FeatureEntry -Path $file
  $e = $r.Entry
  foreach ($k in $Set.get_Keys()) { if ($null -eq $Set[$k] -or (Test-EmptyValue $Set[$k])) { $e.Remove($k) } else { $e[$k] = $Set[$k] } }
  $ctx = Get-RegistryContext -Paths $Paths
  $ctx = Get-RegistryContext -Paths $Paths -ExtraIds (Get-ChildIdsIfNeeded $Paths $e $ctx)
  $problems = @(Test-FeatureEntry -Entry $e -Context $ctx -Stem $Id)
  if ($problems.Count) { throw ("update: entry '$Id' would not be valid; file untouched:`n  " + ($problems -join "`n  ")) }
  [void](Write-FeatureEntry -Entry $e -Path $file -KeyOrder $ctx.KeyOrder)
  return $file
}

function Get-AllRegistryItems($Paths, [bool]$IncludeChildren) {
  $ctx = Get-RegistryContext -Paths $Paths
  $items = @($ctx.Entries | ForEach-Object { [pscustomobject]@{ Entry = $_.Entry; File = $_.Path } })
  if ($IncludeChildren) {
    $live = Get-LiveSurface -Paths $Paths
    $kids = Get-RegistryChildren -Live $live -Entries @($ctx.Entries | ForEach-Object { $_.Entry }) -Paths $Paths
    foreach ($fam in $kids.get_Keys()) { foreach ($c in $kids[$fam]) { $items += [pscustomobject]@{ Entry = $c; File = (Join-Path $Paths.Families "$fam.json") } } }
  }
  return ,$items
}

function Find-FeatureEntry {
  param([Parameter(Mandatory)]$Paths, [Parameter(Mandatory)][string]$Text, [switch]$IncludeChildren)
  $needle = $Text.ToLowerInvariant()
  $rows = foreach ($it in (Get-AllRegistryItems $Paths $IncludeChildren.IsPresent)) {
    $e = $it.Entry; $hit = ''
    foreach ($k in @('id', 'title', 'summary', 'intro', 'wikiPage', 'notes')) { if ($e.Contains($k) -and ([string]$e[$k]).ToLowerInvariant().Contains($needle)) { $hit = $k; break } }
    if (-not $hit) { foreach ($a in (Get-EntryList $e 'aliases')) { if (([string]$a).ToLowerInvariant().Contains($needle)) { $hit = 'aliases'; break } } }
    if (-not $hit) { foreach ($s in (Get-EntryList $e 'surfaces')) { if ((ConvertTo-CanonicalJson -Value $s).ToLowerInvariant().Contains($needle)) { $hit = 'surfaces'; break } } }
    if ($hit) { [pscustomobject]@{ Id = [string]$e['id']; Title = [string]$e['title']; Group = [string]$e['group']; Owner = [string]$e['owner']; Status = [string]$e['status']; WikiPage = [string]$e['wikiPage']; Hit = $hit } }
  }
  return ,@($rows)
}

function ConvertTo-MenuKey {
  param([Parameter(Mandatory)][string]$Path)
  $segs = @($Path -split '\s+>\s+' | ForEach-Object { Get-CaptionKey -S $_ } | Where-Object { $_ })
  return ($segs -join ' > ')
}

function Test-MenuNodeCovers([string]$NodeKey, [string]$PathKey) { return (($PathKey -eq $NodeKey) -or $PathKey.StartsWith($NodeKey + ' > ')) }

# One row per "menuPrefix" VALUE in a family definition (defaults and any
# per-child override), read from the RAW text so move-menu can rewrite the value
# in place and blast-radius sees exactly the set move-menu would touch.
# chart-questions with no defaults.menuPrefix gets a synthetic row (Index -1)
# for the importer's fallback 'drag-lint > Reports'. Every family file is read
# through Read-FamilyDefinition -Context, so a broken one throws here.
# Returns object[] (WRAPPED) of { Family; File; EntryId; Parent; Prefix; Index; Length }.
function Get-FamilyMenuPrefixes($Paths, $Context) {
  $out = New-Object 'System.Collections.Generic.List[object]'
  if (-not (Test-Path -LiteralPath $Paths.Families)) { return ,$out.ToArray() }
  foreach ($f in (Get-ChildItem -LiteralPath $Paths.Families -Filter '*.json' -File | Sort-Object Name)) {
    $def = Read-FamilyDefinition -Path $f.FullName -Context $Context
    $raw = [IO.File]::ReadAllText($f.FullName)
    $par = @($Context.Entries | Where-Object { $_.Stem -ceq [string]$def['entry'] })
    $pe = if ($par.Count -eq 1) { $par[0].Entry } else { $null }
    foreach ($m in [regex]::Matches($raw, '"menuPrefix"\s*:\s*"((?:[^"\\]|\\.)*)"')) {
      $out.Add([pscustomobject]@{ Family = [string]$def['family']; File = $f.FullName; EntryId = [string]$def['entry']; Parent = $pe
                                  Prefix = [string]('"' + $m.Groups[1].Value + '"' | ConvertFrom-Json); Index = $m.Groups[1].Index - 1; Length = $m.Groups[1].Length + 2 })
    }
    if ([string]$def['family'] -ceq 'chart-questions' -and -not $def['defaults'].Contains('menuPrefix')) {
      $out.Add([pscustomobject]@{ Family = 'chart-questions'; File = $f.FullName; EntryId = [string]$def['entry']; Parent = $pe; Prefix = 'drag-lint > Reports'; Index = -1; Length = 0 })
    }
  }
  return ,$out.ToArray()
}

function Get-FeatureBlastRadius {
  param([Parameter(Mandatory)]$Paths, [string]$MenuPath, [string]$Verb, [string]$WikiPage, [string]$Group, [switch]$IncludeChildren)
  if (-not ($MenuPath -or $Verb -or $WikiPage -or $Group)) { throw 'blast-radius: give -MenuPath, -Verb, -WikiPage or -Group' }
  $nodeKey = if ($MenuPath) { ConvertTo-MenuKey -Path $MenuPath } else { '' }
  $rows = New-Object 'System.Collections.Generic.List[object]'
  # Spec 18: blast-radius runs BEFORE a move, so it sees everything move-menu
  # would touch -- including a family whose menuPrefix sits at or under the
  # node (one row per family; its children with -IncludeChildren).
  if ($nodeKey) {
    $ctx = Get-RegistryContext -Paths $Paths
    $byFamily = [ordered]@{}
    foreach ($fp in (Get-FamilyMenuPrefixes $Paths $ctx)) {
      if (-not (Test-MenuNodeCovers $nodeKey (ConvertTo-MenuKey -Path $fp.Prefix))) { continue }
      if (-not $byFamily.Contains($fp.Family)) { $byFamily[$fp.Family] = New-Object 'System.Collections.Generic.List[object]' }
      $byFamily[$fp.Family].Add($fp)
    }
    foreach ($fam in $byFamily.get_Keys()) {
      $fps = $byFamily[$fam]; $pe = $fps[0].Parent
      $pv = { param($k) if ($null -ne $pe -and $pe.Contains($k)) { [string]$pe[$k] } else { '' } }
      if ($Group -and (& $pv 'group') -ne $Group) { continue }
      if ($WikiPage -and (& $pv 'wikiPage') -ne $WikiPage) { continue }
      $surf = (@($fps | ForEach-Object { $_.Prefix + ' > *' } | Select-Object -Unique) -join '; ') + " (family $fam)"
      $rows.Add([pscustomobject]@{ Id = $fps[0].EntryId; Title = $(if (& $pv 'title') { & $pv 'title' } else { $fam }); Owner = (& $pv 'owner'); WikiPage = (& $pv 'wikiPage'); Surface = $surf; File = $fps[0].File })
    }
  }
  foreach ($it in (Get-AllRegistryItems $Paths $IncludeChildren.IsPresent)) {
    $e = $it.Entry
    if ($Group -and [string]$e['group'] -ne $Group) { continue }
    if ($WikiPage -and [string]$e['wikiPage'] -ne $WikiPage) { continue }
    $matched = @()
    foreach ($s in (Get-EntryList $e 'surfaces')) {
      $t = [string]$s['type']
      if ($nodeKey -and $t -eq 'ide-menu' -and (Test-MenuNodeCovers $nodeKey (ConvertTo-MenuKey -Path ([string]$s['path'])))) { $matched += [string]$s['path'] }
      if ($Verb -and $t -eq 'cli' -and [string]$s['verb'] -eq $Verb) { $matched += ('cli ' + $Verb + $(if ($s.Contains('sub')) { ' ' + $s['sub'] } else { '' })) }
    }
    if (($nodeKey -or $Verb) -and $matched.Count -eq 0) { continue }
    foreach ($m in @($(if ($matched.Count) { $matched } else { @('') }))) {
      $rows.Add([pscustomobject]@{ Id = [string]$e['id']; Title = [string]$e['title']; Owner = [string]$e['owner']; WikiPage = [string]$e['wikiPage']; Surface = $m; File = $it.File })
    }
  }
  return ,$rows.ToArray()
}

function Move-FeatureMenuPath {
  param([Parameter(Mandatory)]$Paths, [Parameter(Mandatory)][string]$From, [Parameter(Mandatory)][string]$To, [switch]$WhatIf)
  # ATOMIC: every match, the family reads and the no-match decision are
  # computed first; files are written only at the end, after every text has
  # been rendered.
  if ($To -cne 'drag-lint' -and $To -notlike 'drag-lint > *') { throw "move-menu: -To '$To' must be 'drag-lint' or start 'drag-lint > ' (full path, every level)" }
  $fromKey = ConvertTo-MenuKey -Path $From
  $fromCount = @($From -split '\s+>\s+').Count
  $ctx = Get-RegistryContext -Paths $Paths
  $rows = New-Object 'System.Collections.Generic.List[object]'
  $writes = New-Object 'System.Collections.Generic.List[object]'
  foreach ($r in $ctx.Entries) {
    $copy = ConvertTo-OrderedObject $r.Entry   # deep copy; $r.Entry is never mutated
    $changed = $false
    foreach ($s in (Get-EntryList $copy 'surfaces')) {
      if ([string]$s['type'] -ne 'ide-menu') { continue }
      $old = [string]$s['path']
      if (-not (Test-MenuNodeCovers $fromKey (ConvertTo-MenuKey -Path $old))) { continue }
      $tail = @(@($old -split '\s+>\s+') | Select-Object -Skip $fromCount)
      $new = (@($To) + $tail) -join ' > '
      $rows.Add([pscustomobject]@{ Id = $r.Stem; Old = $old; New = $new; WikiPage = [string]$r.Entry['wikiPage']; File = $r.Path })
      $s['path'] = $new; $changed = $true
    }
    if ($changed) { $writes.Add([pscustomobject]@{ File = $r.Path; Entry = $copy; Text = $null }) }
  }
  # The family files are hand-laid-out (one child per line): the menuPrefix
  # VALUES are rewritten in place, so the diff is the value, not the file.
  $famEdits = [ordered]@{}
  foreach ($fp in (Get-FamilyMenuPrefixes $Paths $ctx)) {
    if (-not (Test-MenuNodeCovers $fromKey (ConvertTo-MenuKey -Path $fp.Prefix))) { continue }
    if ($fp.Index -lt 0) { throw "move-menu: $($fp.File) has no defaults.menuPrefix (the importer falls back to '$($fp.Prefix)'); add it before moving that node; nothing changed" }
    $tail = @(@($fp.Prefix -split '\s+>\s+') | Select-Object -Skip $fromCount)
    $new = (@($To) + $tail) -join ' > '
    $sb = [System.Text.StringBuilder]::new(); Write-JsonString $sb $new
    if (-not $famEdits.Contains($fp.File)) { $famEdits[$fp.File] = New-Object 'System.Collections.Generic.List[object]' }
    $famEdits[$fp.File].Add([pscustomobject]@{ Index = $fp.Index; Length = $fp.Length; Text = $sb.ToString() })
    $page = if ($null -ne $fp.Parent -and $fp.Parent.Contains('wikiPage')) { [string]$fp.Parent['wikiPage'] } else { '' }
    $rows.Add([pscustomobject]@{ Id = $fp.EntryId; Old = $fp.Prefix + ' > *'; New = $new + ' > *'; WikiPage = $page; File = $fp.File })
  }
  if ($rows.Count -eq 0) { throw "move-menu: no ide-menu surface sits at or under '$From' (compared after caption normalisation); nothing changed" }
  # .ToArray(), not @(): @() over a List[object] throws 'Argument types do not match' on pwsh 7.6.
  if ($WhatIf) { return ,$rows.ToArray() }
  foreach ($w in $writes) { $w.Text = ConvertTo-CanonicalJson -Value (ConvertTo-CanonicalEntry -Entry $w.Entry -KeyOrder $ctx.KeyOrder) }
  $famTexts = [ordered]@{}
  foreach ($f in $famEdits.get_Keys()) {
    $raw = [IO.File]::ReadAllText($f); $ed = @($famEdits[$f] | Sort-Object Index -Descending)
    foreach ($x in $ed) { $raw = $raw.Remove($x.Index, $x.Length).Insert($x.Index, $x.Text) }
    $famTexts[$f] = $raw
  }
  foreach ($w in $writes) { [IO.File]::WriteAllText($w.File, $w.Text, [Text.Encoding]::ASCII) }
  foreach ($f in $famTexts.get_Keys()) { [IO.File]::WriteAllText($f, $famTexts[$f], [Text.Encoding]::ASCII) }
  return ,$rows.ToArray()
}

function Set-FeatureDeprecated {
  param([Parameter(Mandatory)]$Paths, [Parameter(Mandatory)][string]$Id, [string]$SupersededBy, [string]$RemovedIn)
  $set = @{ status = 'deprecated' }
  if ($SupersededBy) { $set['supersededBy'] = $SupersededBy }
  if ($RemovedIn) { $set['removedIn'] = $RemovedIn }
  return (Update-FeatureEntry -Paths $Paths -Id $Id -Set $set)
}

function Invoke-RegistryNormalise {
  param([Parameter(Mandatory)]$Paths)
  $ctx = Get-RegistryContext -Paths $Paths
  $changed = New-Object 'System.Collections.Generic.List[string]'
  foreach ($r in $ctx.Entries) { if (Write-FeatureEntry -Entry $r.Entry -Path $r.Path -KeyOrder $ctx.KeyOrder) { $changed.Add($r.Path) } }
  # groups.json / teams.json have a canonical row layout (spec 5.3). The other
  # data files are hand-laid-out tables (families: one child per line), so they
  # are normalised at the BYTE level only -- CRLF, trailing newline, no BOM --
  # never re-serialised; non-ASCII is refused, not rewritten. The page
  # templates (features\templates) get the same byte-level pass: check A
  # polices their ASCII/CRLF, so normalise must be able to repair them.
  foreach ($lf in @(@($Paths.Groups, 'groups'), @($Paths.Teams, 'teams'))) {
    $text = ConvertTo-RegistryListJson $lf[1] (Read-RegistryList $lf[0] $lf[1])
    if ([Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($lf[0])) -cne $text) { [IO.File]::WriteAllText($lf[0], $text, [Text.Encoding]::ASCII); $changed.Add($lf[0]) }
  }
  $byteFiles = @($Paths.Exemptions, $Paths.RelatedProjects) +
               @(Get-ChildItem -LiteralPath $Paths.Families -Filter '*.json' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) +
               @(Get-ChildItem -LiteralPath $Paths.Templates -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
  foreach ($f in $byteFiles) {
    if (-not (Test-Path -LiteralPath $f)) { continue }
    $b = [IO.File]::ReadAllBytes($f)
    $start = if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { 3 } else { 0 }
    for ($i = $start; $i -lt $b.Length; $i++) { if ($b[$i] -gt 127) { throw ("normalise: {0}: non-ASCII byte 0x{1:X2} at byte {2}; fix it by hand" -f $f, $b[$i], $i) } }
    $text = [Text.Encoding]::ASCII.GetString($b, $start, $b.Length - $start)
    $text = $text -replace "`r`n|`r|`n", "`r`n"   # a lone CR too: Test-AsciiCrlfFile rejects it
    if (-not $text.EndsWith("`r`n")) { $text += "`r`n" }
    if ([Text.Encoding]::ASCII.GetString($b) -cne $text) { [IO.File]::WriteAllText($f, $text, [Text.Encoding]::ASCII); $changed.Add($f) }
  }
  return ,[string[]]$changed.ToArray()
}

# Get-EntrySkeleton -- the JSON a check-B failure prints for the implementer
# to paste into features\entries\<id>.json. SINGLE OBJECT ([string], CRLF,
# canonical). since and lastVerified.build come from the live product
# version; wikiPage is a docs\wiki page whose stem equals the id (exact case
# first, then case-insensitively, printed in the page's own case), else a
# placeholder. Placeholders are <...> so the result never validates as-is.
function Get-EntrySkeleton {
  param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][System.Collections.IDictionary]$Surface, [Parameter(Mandatory)]$Live, [Parameter(Mandatory)]$Context)
  $page = '<page stem under docs\wiki>'
  if ($Context.WikiPages.Contains($Id)) { $page = $Id }
  else { foreach ($w in $Context.WikiPages) { if ([string]::Equals($w, $Id, [StringComparison]::OrdinalIgnoreCase)) { $page = $w; break } } }
  $sk = [ordered]@{
    id = $Id; title = '<the name a human says>'; group = ('<one of: ' + (@($Context.Groups.get_Keys()) -join ' ') + '>'); owner = ('<one of: ' + (@($Context.Teams) -join ' ') + '>')
    status = 'shipped'; since = $Live.Versions.Product; summary = '<one line, 20..160 chars, no trailing period>'; intro = '<1..5 sentences: what it does, when to reach for it, what it needs>'
    wikiPage = $page; surfaces = @($Surface); audience = 'both'
    lastVerified = [ordered]@{ date = (Get-Date -Format 'yyyy-MM-dd'); by = '<you>'; build = $Live.Versions.Product }
  }
  return (ConvertTo-CanonicalJson -Value $sk)
}

# The caption key of an IDE surface's LEAF: the last ' > ' segment of an
# ide-menu / tool-window path, or the caption of an ide-context / ide-about
# surface. v1 checks leaves only (spec 18; full-path nesting is v2, once the
# plugin has a declarative menu table). '' for every other surface type.
function Get-LeafKey([System.Collections.IDictionary]$S) {
  switch ([string]$S['type']) {
    'ide-menu'    { return (Get-CaptionKey -S (([string]$S['path'] -split '\s+>\s+')[-1])) }
    'tool-window' { return (Get-CaptionKey -S (([string]$S['path'] -split '\s+>\s+')[-1])) }
    'ide-context' { return (Get-CaptionKey -S ([string]$S['caption'])) }
    'ide-about'   { return (Get-CaptionKey -S ([string]$S['caption'])) }
  }
  return ''
}

# The registry's caption match (checks B and C), STRICTER than the shared
# Test-CaptionKeyMatch that docs-sync check 5 uses for abbreviated prose: an
# exact key, or a prefix either way only when the SHORTER key is >= 12
# characters. Five registered keys are <= 10 characters ('about', 'close',
# 'drag-lint', 'fix it', 'refresh'), and under the loose rule every new caption
# starting with one of them ('Refresh index...') would pass B unregistered.
$script:MinCaptionPrefix = 12
function Test-RegistryCaptionMatch([string]$Key, [string[]]$Keys) {
  if (-not $Key) { return $false }
  foreach ($k in $Keys) {
    if (-not $k) { continue }
    if ($k -ceq $Key) { return $true }
    $short = if ($k.Length -lt $Key.Length) { $k } else { $Key }
    if ($short.Length -lt $script:MinCaptionPrefix) { continue }
    if ($k.StartsWith($Key, [StringComparison]::Ordinal) -or $Key.StartsWith($k, [StringComparison]::Ordinal)) { return $true }
  }
  return $false
}

# Nearest live captions for a (usually abbreviated) caption key: each candidate
# is scored both whole and cut to the key's length, because entries abbreviate
# on purpose ("Call Graph" for "Call Graph (Butterfly)...") and a whole-string
# Levenshtein then ranks "Close" above the caption that was meant. WRAPPED.
function Get-NearestCaption([string]$Key, [string[]]$Captions) {
  $pool = @{}
  foreach ($c in $Captions) {
    $pool[$c] = $c
    $ck = Get-CaptionKey -S $c
    if ($ck.Length -gt $Key.Length) { $cut = $ck.Substring(0, $Key.Length); if (-not $pool.ContainsKey($cut)) { $pool[$cut] = $c } }
  }
  $seen = New-Object 'System.Collections.Generic.List[string]'
  foreach ($n in (Get-NearestCandidates -Value $Key -Candidates ([string[]]@($pool.get_Keys())) -Top 12)) { $o = [string]$pool[$n]; if (-not $seen.Contains($o)) { $seen.Add($o) }; if ($seen.Count -ge 3) { break } }
  return ,[string[]]$seen.ToArray()
}

function Get-ExemptionMap($Context, [string]$Kind) {
  if ($Context.Exemptions -is [System.Collections.IDictionary] -and $Context.Exemptions.Contains($Kind) -and $Context.Exemptions[$Kind] -is [System.Collections.IDictionary]) { return $Context.Exemptions[$Kind] }
  return [ordered]@{}
}

# Invoke-RegistryCheck -- the guard's checks (spec 9). SINGLE OBJECT
# { Failures; Notes; Stats }. Failure strings are prefixed 'A: '..'D: ';
# check E (staleness) and the seed-backlog debt land in Notes ('stale: ...',
# 'backlog: <TEAM> <n> remaining ...'), never in Failures.
# -Level WellFormed runs check A only (no engine, no live harvest).
# -Level Full (default) adds B, C, D and E; -Live reuses a Get-LiveSurface
# result; -SkipGenerated skips D. The -Inject* parameters exist for the
# guard's positive controls: they add in-memory entries, --help verbs, live
# main-menu captions and (-InjectContextCaptions) Structure-form context-menu
# captions to the run, and never touch a file.
function Invoke-RegistryCheck {
  param([Parameter(Mandatory)]$Paths, [ValidateSet('WellFormed', 'Full')][string]$Level = 'Full', $Live = $null, [switch]$SkipGenerated,
        [object[]]$InjectEntries = @(), [string[]]$InjectHelpVerbs = @(), [string[]]$InjectCaptions = @(), [string[]]$InjectContextCaptions = @())
  $fail = New-Object 'System.Collections.Generic.List[string]'
  $notes = New-Object 'System.Collections.Generic.List[string]'
  $stats = [ordered]@{}
  # ---- A. well-formed ------------------------------------------------------
  if (-not (Test-Path -LiteralPath $Paths.Entries)) { $fail.Add("A: $($Paths.Entries) does not exist") }
  $ctx = $null
  try { $ctx = Get-RegistryContext -Paths $Paths } catch { $fail.Add("A: cannot load the registry: $($_.Exception.Message)") }
  if ($null -eq $ctx) { return [pscustomobject]@{ Failures = $fail; Notes = $notes; Stats = $stats } }
  # Non-empty groups are a Full-level property: a scratch registry with three
  # entries is well-formed, it is just not complete.
  foreach ($pr in @(Test-GroupsAndTeams -Context $ctx -RequireNonEmptyGroups:($Level -eq 'Full'))) { $fail.Add("A: $pr") }
  # Not $home: $HOME is a read-only automatic variable and the assignment throws.
  $homeSeen = @{}
  foreach ($r in $ctx.Entries) {
    $canon = Test-EntryCanonicalBytes -Read $r -KeyOrder $ctx.KeyOrder; if ($canon) { $fail.Add("A: $canon") }
    if ($r.Entry.Contains('homeOrder')) { $ho = [int]$r.Entry['homeOrder']; if ($homeSeen.ContainsKey($ho)) { $fail.Add("A: $($r.Stem).json: homeOrder $ho is also used by $($homeSeen[$ho])") } else { $homeSeen[$ho] = $r.Stem } }
  }
  foreach ($f in @(Get-ChildItem -LiteralPath $Paths.Templates -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) + @($Paths.RelatedProjects, $Paths.Exemptions, $Paths.SeedBacklog) + @(Get-ChildItem -LiteralPath $Paths.Families -Filter '*.json' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })) {
    if (Test-Path -LiteralPath $f) { $asc = Test-AsciiCrlfFile -Path $f; if ($asc) { $fail.Add("A: $asc") } }
  }
  $families = [ordered]@{}
  foreach ($f in (Get-ChildItem -LiteralPath $Paths.Families -Filter '*.json' -File -ErrorAction SilentlyContinue)) { try { $families[$f.BaseName] = Read-FamilyDefinition -Path $f.FullName -Context $ctx } catch { $fail.Add("A: $($_.Exception.Message)") } }
  $stats['entries'] = $ctx.Entries.Count
  foreach ($g in @($ctx.Groups.get_Keys())) { $stats["group:$g"] = @($ctx.Entries | Where-Object { [string]$_.Entry['group'] -eq $g }).Count }
  if ($Level -eq 'WellFormed') {
    foreach ($r in $ctx.Entries) { foreach ($pr in @(Test-FeatureEntry -Entry $r.Entry -Context $ctx -Stem $r.Stem)) { $fail.Add("A: $pr") } }
    return [pscustomobject]@{ Failures = $fail; Notes = $notes; Stats = $stats }
  }
  # ---- Full: live surface + family children ----------------------------------
  if ($null -eq $Live) { try { $Live = Get-LiveSurface -Paths $Paths } catch { $fail.Add("B: live surface: $($_.Exception.Message)"); return [pscustomobject]@{ Failures = $fail; Notes = $notes; Stats = $stats } } }
  $hand = [object[]]@(@(foreach ($r in $ctx.Entries) { $r.Entry }) + @($InjectEntries))
  $children = [ordered]@{}
  try { $children = Get-RegistryChildren -Live $Live -Entries $hand -Paths $Paths }
  catch {
    # The importer throws for three reasons; file each under the check it is.
    $m = $_.Exception.Message
    $letter = if ($m -like 'family children failed validation*') { 'A' } elseif ($m -like '*override*') { 'C' } else { 'B' }
    $fail.Add("${letter}: family import: $m")
  }
  $childList = [object[]]@(foreach ($v in $children.get_Values()) { foreach ($c in $v) { $c } })
  $allIds = [string[]]@(@(foreach ($e in $hand) { [string]$e['id'] }) + @(foreach ($c in $childList) { [string]$c['id'] }))
  $ctx = Get-RegistryContext -Paths $Paths -ExtraIds $allIds
  foreach ($e in $hand) { foreach ($pr in @(Test-FeatureEntry -Entry $e -Context $ctx -Stem ([string]$e['id']))) { $fail.Add("A: $pr") } }
  $helpVerbs = [string[]]@(@(foreach ($v in $Live.HelpVerbs) { $v }) + @($InjectHelpVerbs))
  # foreach, not @(...): Captions is a HashSet and @() over a generic
  # collection is not safe on this pwsh (see Import-ChartQuestionFamily).
  $captions = [string[]]@(@(foreach ($c in $Live.Captions) { $c }) + @($InjectCaptions))
  $liveKeys = [string[]]@(foreach ($c in $captions) { $k = Get-CaptionKey -S $c; if ($k) { $k } })
  # An ide-about surface may name a dialog button of the About window.
  $aboutKeys = [string[]]@(@($liveKeys) + @(foreach ($c in @(if ($Live.PSObject.Properties.Name -contains 'DialogButtons') { $Live.DialogButtons })) { $k = Get-CaptionKey -S $c; if ($k) { $k } }))
  $ctxCaptions = [ordered]@{}
  if ($Live.PSObject.Properties.Name -contains 'ContextCaptions') { foreach ($h in @($Live.ContextCaptions.get_Keys())) { $ctxCaptions[$h] = [string[]]@($Live.ContextCaptions[$h]) } }
  if (@($InjectContextCaptions).Count) { $ctxCaptions['Structure form'] = [string[]]@(@(if ($ctxCaptions.Contains('Structure form')) { $ctxCaptions['Structure form'] }) + @($InjectContextCaptions)) }
  $verbSubs = $Live.SubMap.VerbSubs
  $subVerbs = [string[]]@($verbSubs.get_Keys())
  $all = [object[]]@($hand + $childList)
  # ---- B. live -> registry ----------------------------------------------------
  $regVerbs = @{}; $regSubs = @{}
  $regKeys = New-Object 'System.Collections.Generic.List[string]'
  $regExes = New-Object 'System.Collections.Generic.List[string]'
  $regCtx = @{}   # ide-context host -> leaf keys registered on it
  foreach ($e in $all) {
    if ([string]$e['status'] -eq 'planned') { continue }
    foreach ($s in (Get-EntryList $e 'surfaces')) {
      switch ([string]$s['type']) {
        'cli' { $regVerbs[[string]$s['verb']] = $true; if ($s.Contains('sub')) { $regSubs[[string]$s['verb'] + ' ' + [string]$s['sub']] = $true } }
        'exe' { $regExes.Add([string]$s['name']) }
        default {
          $k = Get-LeafKey $s; if ($k) { $regKeys.Add($k) }
          if ($k -and [string]$s['type'] -eq 'ide-context') { $hk = [string]$s['host']; if (-not $regCtx.ContainsKey($hk)) { $regCtx[$hk] = New-Object 'System.Collections.Generic.List[string]' }; $regCtx[$hk].Add($k) }
        }
      }
    }
  }
  $regKeyArr = [string[]]$regKeys.ToArray()
  $exVerbs = Get-ExemptionMap $ctx 'verbs'; $exCaps = Get-ExemptionMap $ctx 'captions'; $exExes = Get-ExemptionMap $ctx 'exes'
  foreach ($v in $helpVerbs) {
    if ($regVerbs.ContainsKey($v) -or $exVerbs.Contains($v)) { continue }
    $sk = Get-EntrySkeleton -Id $v -Surface ([ordered]@{ type = 'cli'; verb = $v }) -Live $Live -Context $ctx
    $fail.Add("B: every --help verb is registered -- unregistered: '$v'`n   ^ no entry claims it. Create features\entries\$v.json (tools\feature-registry.ps1 add -Id $v ...), then run tools\build-feature-pages.ps1 and commit the regenerated pages:`n" + ($sk.TrimEnd() -replace '(?m)^', '   '))
  }
  foreach ($verb in $subVerbs) {
    # Get-EntryList is WRAPPED: iterate it with foreach, never pipe it (the
    # pipeline would hand Where-Object the whole array as one item).
    $owners = @(foreach ($he in $hand) { foreach ($hs in (Get-EntryList $he 'surfaces')) { if ([string]$hs['type'] -eq 'cli' -and [string]$hs['verb'] -eq $verb) { $he; break } } })
    # An internal verb's subcommands are its own business (the selftest dispatcher).
    if (@($owners | Where-Object { [string]$_['status'] -eq 'internal' }).Count -gt 0) { continue }
    foreach ($sub in @($verbSubs[$verb])) {
      if ($regSubs.ContainsKey("$verb $sub") -or $exVerbs.Contains("$verb $sub")) { continue }
      $sk = Get-EntrySkeleton -Id "$verb-$sub" -Surface ([ordered]@{ type = 'cli'; verb = $verb; sub = $sub }) -Live $Live -Context $ctx
      $fail.Add("B: every subcommand is registered -- unregistered: '$verb $sub'`n   ^ add { `"type`": `"cli`", `"verb`": `"$verb`", `"sub`": `"$sub`" } to the entry that owns it, or create features\entries\$verb-$sub.json:`n" + ($sk.TrimEnd() -replace '(?m)^', '   '))
    }
  }
  foreach ($cap in $captions) {
    $k = Get-CaptionKey -S $cap
    if (-not $k) { continue }
    if ((Test-RegistryCaptionMatch -Key $k -Keys $regKeyArr) -or $exCaps.Contains($cap)) { continue }
    $sid = ($cap.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    $sk = Get-EntrySkeleton -Id $sid -Surface ([ordered]@{ type = 'ide-menu'; path = "drag-lint > <submenu> > $cap" }) -Live $Live -Context $ctx
    $fail.Add("B: every live IDE caption is registered -- unregistered: '$cap'`n   ^ no ide-menu/ide-context/ide-about/tool-window surface matches it (exact, or a prefix of >= 12 characters; nearest registered: $((Get-NearestCandidates -Value $k -Candidates $regKeyArr) -join ' | ')). Register it, or add it to features\exemptions.json captions WITH a reason if it is a container or header:`n" + ($sk.TrimEnd() -replace '(?m)^', '   '))
  }
  foreach ($h in @($ctxCaptions.get_Keys())) {
    $hostKeys = if ($regCtx.ContainsKey($h)) { [string[]]$regCtx[$h].ToArray() } else { [string[]]@() }
    foreach ($cap in $ctxCaptions[$h]) {
      $k = Get-CaptionKey -S $cap
      if (-not $k -or (Test-RegistryCaptionMatch -Key $k -Keys $hostKeys)) { continue }
      $sid = ($cap.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
      $sk = Get-EntrySkeleton -Id $sid -Surface ([ordered]@{ type = 'ide-context'; host = $h; caption = $cap }) -Live $Live -Context $ctx
      $fail.Add("B: every context-menu item is registered -- unregistered: '$cap' ($h)`n   ^ no ide-context surface with host '$h' matches it (exact, or a prefix of >= 12 characters). Add { `"type`": `"ide-context`", `"host`": `"$h`", `"caption`": `"$cap`" } to the entry that owns it, or create:`n" + ($sk.TrimEnd() -replace '(?m)^', '   '))
    }
  }
  foreach ($x in @($Live.PackExes)) { if ($regExes -notcontains $x -and -not $exExes.Contains($x)) { $fail.Add("B: every release payload exe is registered -- '$x' is packed by build\pack-lint-release.ps1 and no entry has an exe surface for it (add { `"type`": `"exe`", `"name`": `"$x`" } to the entry that owns it, or exempt it in features\exemptions.json exes WITH a reason)") } }
  # Exemption lists are asserted BOTH ways: still live, and still unregistered.
  foreach ($k in @($exVerbs.get_Keys())) {
    $m = [regex]::Match([string]$k, '^(\S+) (\S+)$')
    $liveOk = if ($m.Success) { ($subVerbs -contains $m.Groups[1].Value) -and (@($verbSubs[$m.Groups[1].Value]) -contains $m.Groups[2].Value) } else { $helpVerbs -contains $k }
    if (-not $liveOk) { $fail.Add("B: exemptions.json verbs: '$k' is no longer a --help verb or subcommand -- delete the exemption"); continue }
    if (($m.Success -and $regSubs.ContainsKey($k)) -or (-not $m.Success -and $regVerbs.ContainsKey($k))) { $fail.Add("B: exemptions.json verbs: '$k' is registered after all -- delete the exemption") }
  }
  foreach ($k in @($exCaps.get_Keys())) {
    if ($captions -cnotcontains $k) { $fail.Add("B: exemptions.json captions: '$k' is no longer a live caption (nearest: $((Get-NearestCandidates -Value $k -Candidates $captions) -join ' | ')) -- delete or correct the exemption") }
    elseif (Test-RegistryCaptionMatch -Key (Get-CaptionKey -S $k) -Keys $regKeyArr) { $fail.Add("B: exemptions.json captions: '$k' is covered by a registered surface after all -- delete the exemption") }
  }
  foreach ($k in @($exExes.get_Keys())) { if (@($Live.PackExes) -notcontains $k) { $fail.Add("B: exemptions.json exes: '$k' is no longer packed -- delete the exemption") } }
  $exCount = @($exVerbs.get_Keys()).Count + @($exCaps.get_Keys()).Count + @($exExes.get_Keys()).Count
  if ($exCount) { $notes.Add("exempt with reason: $(@($exVerbs.get_Keys()).Count) verb(s), $(@($exCaps.get_Keys()).Count) caption(s), $(@($exExes.get_Keys()).Count) exe(s) -- features\exemptions.json") }
  # ---- C. registry -> live ----------------------------------------------------
  foreach ($e in $all) {
    $st = [string]$e['status']; $id = [string]$e['id']
    if ($st -eq 'planned') { $notes.Add("planned, surfaces not checked: $id"); continue }
    if ($st -eq 'deprecated' -and $e.Contains('removedIn')) { $notes.Add("removed in $($e['removedIn']), surfaces not checked: $id"); continue }
    foreach ($s in (Get-EntryList $e 'surfaces')) {
      switch ([string]$s['type']) {
        'cli' {
          $v = [string]$s['verb']
          if ($st -eq 'internal') { if ($Live.DispatchVerbs -notcontains $v) { $fail.Add("C: $id`: internal verb '$v' is not dispatched by the CLI (nearest: $((Get-NearestCandidates -Value $v -Candidates $Live.DispatchVerbs) -join ', '))") } }
          elseif ($helpVerbs -notcontains $v) { $fail.Add("C: $id`: cli verb '$v' is not in --help (nearest: $((Get-NearestCandidates -Value $v -Candidates $helpVerbs) -join ', ')) -- if it was retired, deprecate the entry with removedIn") }
          if ($s.Contains('sub')) {
            $subs = if ($subVerbs -contains $v) { [string[]]@($verbSubs[$v]) } else { [string[]]@() }
            if ($subs -notcontains [string]$s['sub']) { $fail.Add("C: $id`: subcommand '$v $($s['sub'])' is not dispatched (nearest: $((Get-NearestCandidates -Value ([string]$s['sub']) -Candidates $subs) -join ', '))") }
          }
        }
        'mcp' { if ($Live.McpTools -notcontains [string]$s['tool']) { $fail.Add("C: $id`: mcp tool '$($s['tool'])' is not in HandleToolsList (nearest: $((Get-NearestCandidates -Value ([string]$s['tool']) -Candidates $Live.McpTools) -join ', '))") } }
        'ide-context' {
          # Checked against ITS host's context menu, never the main menu.
          $h = [string]$s['host']; $k = Get-LeafKey $s
          if (-not $ctxCaptions.Contains($h)) { $fail.Add("C: $id`: ide-context host '$h' has no live harvest (harvested hosts: $(@($ctxCaptions.get_Keys()) -join ', ')) -- teach Get-LiveSurface to read that host's menu before registering against it") }
          else {
            $hostKeys = [string[]]@(foreach ($c in $ctxCaptions[$h]) { Get-CaptionKey -S $c })
            if (-not (Test-RegistryCaptionMatch -Key $k -Keys $hostKeys)) { $fail.Add("C: $id`: ide-context '$($s['caption'])' is not on the $h context menu (nearest: $((Get-NearestCaption -Key $k -Captions $ctxCaptions[$h]) -join ' | ')) -- the usual cause is a renamed item: update the entry") }
          }
        }
        { $_ -in @('ide-menu', 'ide-about', 'tool-window') } {
          $k = Get-LeafKey $s
          if (-not (Test-RegistryCaptionMatch -Key $k -Keys $(if ([string]$s['type'] -eq 'ide-about') { $aboutKeys } else { $liveKeys }))) {
            $near = Get-NearestCaption -Key $k -Captions $captions
            $where = if ($s.Contains('path')) { $s['path'] } else { $s['caption'] }
            $fail.Add("C: $id`: $($s['type']) '$where' matches no live caption (nearest: $($near -join ' | ')) -- the usual cause is a renamed or moved menu item: tools\feature-registry.ps1 move-menu, or update the entry")
          }
        }
      }
    }
  }
  # ---- seed backlog, two-way (spec 15.2: a debt, not a suppression) ----------------
  if (Test-Path -LiteralPath $Paths.SeedBacklog) {
    $bl = Get-Content -LiteralPath $Paths.SeedBacklog -Raw | ConvertFrom-Json
    $byStem = @{}; foreach ($r in $ctx.Entries) { $byStem[$r.Stem] = $r.Entry }
    foreach ($team in $bl.teams.PSObject.Properties) {
      $remaining = 0
      foreach ($bid in @($team.Value)) {
        if (-not $byStem.ContainsKey([string]$bid)) { $fail.Add("A: seed-backlog.json: '$bid' ($($team.Name)) is not an entry (nearest: $((Get-NearestCandidates -Value ([string]$bid) -Candidates @($byStem.get_Keys())) -join ', ')) -- delete it from the backlog"); continue }
        $be = $byStem[[string]$bid]
        $owed = (-not $be.Contains('intro')) -or (-not $be.Contains('lastVerified')) -or ([string]$be['since'] -eq '0.0.0')
        if ($owed) { $remaining++ } else { $fail.Add("A: seed-backlog.json: '$bid' now has intro, lastVerified and a real since -- delete it from the backlog (the list is a debt, not a suppression)") }
      }
      $notes.Add("backlog: $($team.Name) $remaining remaining (intro + lastVerified owed; deadline: $($bl.deadline))")
    }
  }
  # ---- D. generated outputs current and untouched --------------------------------
  if (-not $SkipGenerated) {
    try {
      $gen = Invoke-RegistryGenerate -Paths $Paths -Check
      foreach ($c in $gen.Changed) { $fail.Add("D: $($c.Path) differs from a fresh render -- run tools\build-feature-pages.ps1 and commit (or revert the hand edit)`n" + ($c.Diff.TrimEnd() -replace '(?m)^', '   ')) }
    } catch { $fail.Add("D: generator: $($_.Exception.Message)") }
  }
  # ---- E. staleness: WARN only -----------------------------------------------------
  $stale = New-Object 'System.Collections.Generic.List[object]'
  $verified = @(foreach ($e in $hand) { if ($e.Contains('lastVerified')) { [pscustomobject]@{ Id = [string]$e['id']; Lv = $e['lastVerified'] } } }) +
              @(foreach ($fk in @($families.get_Keys())) { [pscustomobject]@{ Id = "family:$fk"; Lv = $families[$fk]['lastVerified'] } })
  foreach ($x in $verified) {
    $d = [datetime]::MinValue
    if (-not [datetime]::TryParseExact([string]$x.Lv['date'], 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$d)) { continue }   # A reports it
    if (((Get-Date).Date - $d.Date).TotalDays -gt 90) { $stale.Add([pscustomobject]@{ Id = $x.Id; Date = $d }) }
  }
  if ($stale.Count) { $oldest = @($stale | Sort-Object Date, Id)[0]; $notes.Add("stale: $($stale.Count) entries older than 90 days, oldest $($oldest.Id) ($($oldest.Date.ToString('yyyy-MM-dd'))) -- the periodic review's input, not a failure") }
  $stats['children'] = $childList.Count
  $stats['stale'] = $stale.Count
  return [pscustomobject]@{ Failures = $fail; Notes = $notes; Stats = $stats }
}

# ---------------------------------------------------------------------------
# Generator (spec 8): the pages the registry OWNS. Render-* are module-internal
# ('Render' is not an approved verb; exporting them would make Import-Module
# warn). Callers use Invoke-RegistryGenerate; tests reach a renderer through
# & (Get-Module FeatureRegistry) { Render-HomePage -Model $args[0] } $model.
# Every path comes from the -Paths object (Get-RegistryPaths, $PSScriptRoot
# relative), never from the CWD, so a run from any directory is byte-identical.
# ---------------------------------------------------------------------------
$script:WikiUrl = 'https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/'

# WRAPPED: returns ,[object[]] sorted by an ordinal string key.
function Sort-ByOrdinalKey([object[]]$Items, [scriptblock]$KeyOf) {
  if ($null -eq $Items -or $Items.Count -eq 0) { return ,@() }
  $keys = [string[]]@(foreach ($i in $Items) { [string](& $KeyOf $i) })
  $arr = [object[]]$Items.Clone()
  # The casts are load-bearing: with a typed string[] and a StringComparer,
  # pwsh 7.6 binds a generic overload that sorts the KEYS ONLY and leaves the
  # items where they were (measured 2026-10-05 -- every generated list came
  # out in file/id order). The non-generic Sort(Array, Array, IComparer)
  # moves both. Keys that want case-insensitivity lower-case themselves.
  [Array]::Sort([Array]$keys, [Array]$arr, [System.Collections.IComparer][System.StringComparer]::Ordinal)
  return ,$arr
}

function Get-RegistryModel {
  param([Parameter(Mandatory)]$Paths, $Live = $null)
  # Templates first: a non-ASCII byte is a generator failure with file:line,
  # and it should not wait for the engine harvest.
  $templates = @{}
  foreach ($t in 'Home.intro.md', 'Features.intro.md', 'Quick-Help.intro.md') {
    $f = Join-Path $Paths.Templates $t
    if (-not (Test-Path -LiteralPath $f)) { throw "template missing: $f" }
    $asc = Test-AsciiCrlfFile -Path $f; if ($asc) { throw "template: $asc" }
    $templates[$t] = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($f))
  }
  if ($null -eq $Live) { $Live = Get-LiveSurface -Paths $Paths }
  $ctx = Get-RegistryContext -Paths $Paths
  $entries = [object[]]@(foreach ($r in $ctx.Entries) { ConvertTo-CanonicalEntry -Entry $r.Entry -KeyOrder $ctx.KeyOrder })
  # An empty registry (before the seed) has no parent entry for any family:
  # there is nothing to hang children on, so none are imported.
  $children = if ($entries.Count -eq 0) { [ordered]@{} } else { Get-RegistryChildren -Live $Live -Entries $entries -Paths $Paths }
  $groups = [object[]]@($ctx.Groups.get_Values() | Sort-Object { [int]$_.order })
  $sorted = Sort-ByOrdinalKey $entries { param($e) ('{0:D6}|{1}|{2}' -f [int]$ctx.Groups[[string]$e['group']].order, ([string]$e['title']).ToLowerInvariant(), [string]$e['id']) }
  $related = [object[]]@((Get-Content -LiteralPath $Paths.RelatedProjects -Raw | ConvertFrom-Json).projects)
  return [pscustomobject]@{ Live = $Live; Context = $ctx; Entries = $sorted; Children = $children; Groups = $groups; Templates = $templates; Related = $related }
}

function Get-FamilyCountText($Model, [System.Collections.IDictionary]$Entry) {
  $fam = [string]$Entry['family']
  if (-not $Model.Children.Contains($fam)) { return '' }
  $n = @($Model.Children[$fam]).Count
  if ($fam -eq 'lint-rules') { $fx = @($Model.Live.RuleCatalog.rules | Where-Object { $_.fixable }).Count; return "$n rules, $fx fixable" }
  return "$n questions"
}

function Format-CliSurface($S) { return '`' + [string]$S['verb'] + $(if ($S.Contains('sub')) { ' ' + [string]$S['sub'] } else { '' }) + '`' }

function Format-SurfaceCell([System.Collections.IDictionary]$Entry) {
  $parts = foreach ($s in (Get-EntryList $Entry 'surfaces')) {
    switch ([string]$s['type']) {
      'cli'         { Format-CliSurface $s }
      'ide-menu'    { [string]$s['path'] }
      'ide-context' { [string]$s['host'] + ': ' + [string]$s['caption'] }
      'ide-about'   { 'About window: ' + [string]$s['caption'] }
      'tool-window' { [string]$s['path'] }
      'shortcut'    { 'shortcut ' + [string]$s['keys'] }
      'lsp'         { '`lsp ' + [string]$s['method'] + '`' }
      'mcp'         { '`mcp ' + [string]$s['tool'] + '`' }
      'script'      { '`' + [string]$s['path'] + $(if ($s.Contains('args')) { ' ' + [string]$s['args'] } else { '' }) + '`' }
      'exe'         { '`' + [string]$s['name'] + '`' + $(if ($s.Contains('menu')) { ' (' + [string]$s['menu'] + ')' } else { '' }) }
      'workflow'    { 'procedure: `' + [string]$s['doc'] + '`' }
    }
  }
  return (@($parts) -join '; ')
}

function Get-StatusCell([System.Collections.IDictionary]$Entry) { $s = [string]$Entry['status']; if ($s -eq 'shipped') { return '' } else { return $s } }

function Render-HomePage {
  param([Parameter(Mandatory)]$Model)
  $v = $Model.Live.Versions
  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.Append($Model.Templates['Home.intro.md'].TrimEnd() + "`r`n`r`n")
  [void]$sb.Append("**Status: alpha** (current release v$($v.Product); extractor $($v.Extractor), resolver $($v.Resolver), index schema $($v.Schema)). Expect breaking changes. The index format is stable within a schema version; the CLI surface is not yet frozen.`r`n`r`n")
  [void]$sb.Append("## Start here`r`n`r`n| Page | For |`r`n|---|---|`r`n")
  [void]$sb.Append("| **[Features](Features)** | Everything it does, grouped |`r`n")
  [void]$sb.Append("| **[Feature Index](Feature-Index)** | Every feature by the surface it is reached from |`r`n")
  [void]$sb.Append("| **[Quick Help](Quick-Help)** | One line per feature, with the short help and the aliases people search for |`r`n")
  $withHome = [object[]]@(@($Model.Entries | Where-Object { $_.Contains('homeOrder') }) + @(foreach ($list in $Model.Children.get_Values()) { foreach ($c in $list) { if ($c.Contains('homeOrder')) { $c } } }))
  foreach ($e in (Sort-ByOrdinalKey $withHome { param($x) ('{0:D6}|{1}' -f [int]$x['homeOrder'], [string]$x['id']) })) {
    [void]$sb.Append("| **[$($e['title'])]($($e['wikiPage']))** | $($e['summary']) |`r`n")
  }
  [void]$sb.Append("`r`n## Related projects`r`n`r`n")
  foreach ($r in $Model.Related) { [void]$sb.Append("* **$($r.name)** -- $($r.summary)`r`n") }
  [void]$sb.Append("`r`n## Links`r`n`r`n* [Issues](https://github.com/Alexl-git/Delphi-RAG-Lint/issues)`r`n* [Releases](https://github.com/Alexl-git/Delphi-RAG-Lint/releases)`r`n* ``CHANGELOG.md`` in the repository root`r`n`r`n")
  [void]$sb.Append("*Generated by ``tools\build-feature-pages.ps1`` from ``features\``; do not edit by hand.*`r`n")
  return $sb.ToString()
}

function Render-RuleStats($Model) {
  $cat = $Model.Live.RuleCatalog
  $t = [int]$cat.summary.total; $fx = @($cat.rules | Where-Object { $_.fixable }).Count; $on = @($cat.rules | Where-Object { $_.default_enabled }).Count
  $bi = @($cat.rules | Where-Object { $_.source -eq 'builtin' }).Count; $ex = @($cat.rules | Where-Object { $_.source -eq 'scm' }).Count
  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.Append("**$t rules. $fx have an auto-fix. $on are on by default.** $bi are built-in checks; $ex are external tree-sitter ``.scm`` rules you can read and extend in ``rules\``. Run ``drag-lint rules`` for the always-current catalogue.`r`n`r`n")
  [void]$sb.Append("| Category | Rules | With auto-fix |`r`n|---|---:|---:|`r`n")
  foreach ($c in (Sort-ByOrdinalKey ([object[]]@($cat.summary.per_category)) { param($c) [string]$c.category })) {
    $f = @($cat.rules | Where-Object { $_.category -eq $c.category -and $_.fixable }).Count
    [void]$sb.Append("| $($c.category) | $($c.count) | $(if ($f) { $f } else { '-' }) |`r`n")
  }
  [void]$sb.Append("| **Total** | **$t** | **$fx** |`r`n`r`n")
  return $sb.ToString()
}

function Render-FeaturesPage {
  param([Parameter(Mandatory)]$Model)
  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.Append($Model.Templates['Features.intro.md'].TrimEnd() + "`r`n`r`n---`r`n`r`n")
  foreach ($g in $Model.Groups) {
    [void]$sb.Append("## $($g.title)`r`n`r`n$($g.summary)`r`n`r`n")
    $rows = @($Model.Entries | Where-Object { [string]$_['group'] -eq [string]$g.id })
    foreach ($fe in @($rows | Where-Object { $_.Contains('family') -and [string]$_['family'] -eq 'lint-rules' })) { [void]$sb.Append((Render-RuleStats $Model)) }
    [void]$sb.Append("| Feature | Surfaces | Status |`r`n|---|---|---|`r`n")
    foreach ($e in $rows) {
      $cell = if ($e.Contains('family')) { (Get-FamilyCountText $Model $e) + '; ' + (Format-SurfaceCell $e) } else { Format-SurfaceCell $e }
      $ex = @((Get-EntryList $e 'examples') | Where-Object { [string]$_['kind'] -eq 'file' -and [string]$_['path'] -like 'docs\wiki\*.md' })
      $exText = ''
      if ($ex.Count) { $stem = [IO.Path]::GetFileNameWithoutExtension([string]$ex[0]['path']); $exText = " (worked example: [$($stem.Replace('-', ' '))]($stem))" }
      [void]$sb.Append("| [$($e['title'])]($($e['wikiPage']))$exText | $cell | $(Get-StatusCell $e) |`r`n")
    }
    [void]$sb.Append("`r`n")
  }
  [void]$sb.Append("---`r`n`r`n*Generated by ``tools\build-feature-pages.ps1`` from ``features\``; counts come from ``drag-lint rules --json`` at generation time. Do not edit by hand.*`r`n")
  return $sb.ToString()
}

function Format-IndexLine($E, [string]$Detail) { return "* [$($E['title'])]($($E['wikiPage']))" + $(if ($Detail) { " -- $Detail" } else { '' }) + "`r`n" }

function Render-FeatureIndexPage {
  param([Parameter(Mandatory)]$Model)
  $hand = @($Model.Entries | Where-Object { [string]$_['status'] -notin @('planned', 'internal') })
  $byTitle = { param($e) ([string]$e['title']).ToLowerInvariant() + '|' + [string]$e['id'] }
  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.Append("# Feature Index`r`n`r`nEvery registered feature, by the surface it is reached from. Generated by ``tools\build-feature-pages.ps1`` from ``features\entries\*.json`` and the two imported families; do not edit by hand. See also [Features](Features) for the grouped overview, [Quick Help](Quick-Help) for one line per feature, and [IDE Menu Reference](IDE-Menu-Reference) for the menu layout.`r`n`r`n")
  # The H2 names are a CONTRACT: build-manual.ps1 keys on them (spec 8).
  $sections = [ordered]@{
    'Main menu'         = @('ide-menu', 'ide-about')
    'Right-click menus' = @('ide-context')
    'Tool windows'      = @('tool-window')
    'CLI verbs'         = @('cli')
    'Scripts and tools' = @('script', 'exe', 'workflow')
  }
  foreach ($name in $sections.Keys) {
    [void]$sb.Append("## $name`r`n`r`n")
    $types = $sections[$name]
    $rows = [object[]]@($hand | Where-Object { @((Get-EntryList $_ 'surfaces') | Where-Object { $types -contains [string]$_['type'] }).Count -gt 0 })
    foreach ($e in (Sort-ByOrdinalKey $rows $byTitle)) {
      $mine = @((Get-EntryList $e 'surfaces') | Where-Object { $types -contains [string]$_['type'] })
      $detail = switch ($name) {
        'Main menu'         { (@($mine | ForEach-Object { if ([string]$_['type'] -eq 'ide-about') { 'About window: ' + [string]$_['caption'] } else { [string]$_['path'] } }) -join '; ') }
        'Right-click menus' { (@($mine | ForEach-Object { [string]$_['host'] + ': ' + [string]$_['caption'] }) -join '; ') }
        'Tool windows'      { (@($mine | ForEach-Object { [string]$_['path'] }) -join '; ') }
        'CLI verbs'         { (@($mine | ForEach-Object { Format-CliSurface $_ }) -join ', ') }
        'Scripts and tools' { (@(foreach ($s in $mine) { switch ([string]$s['type']) { 'script' { '`' + [string]$s['path'] + '`' } 'exe' { '`' + [string]$s['name'] + '`' } 'workflow' { 'procedure' } } }) -join ', ') }
      }
      [void]$sb.Append((Format-IndexLine $e $detail))
    }
    [void]$sb.Append("`r`n")
  }
  [void]$sb.Append("## Diagrams and charts`r`n`r`nEvery chart question, by its **drag-lint > Reports** caption in RAD Studio. Outside the IDE ask the same question with ``charts\src\Ask-Report.ps1 -Question <id>`` -- see [Charts and the IDE](Charts-and-the-IDE). Script paths are relative to a repository clone in v1.`r`n`r`n")
  if ($Model.Children.Contains('chart-questions')) {
    foreach ($c in $Model.Children['chart-questions']) { [void]$sb.Append("* [$($c['title'])]($($c['wikiPage'])) -- ``$(([string]$c['id']).Substring(6))`` ($($c['subgroup']))`r`n") }
  }
  [void]$sb.Append("`r`n## Lint rules`r`n`r`nOne line per rule, linking the rule reference. Counts: see [Features](Features#linting).`r`n`r`n")
  if ($Model.Children.Contains('lint-rules')) {
    $byId = @{}; foreach ($r0 in @($Model.Live.RuleCatalog.rules)) { $byId[[string]$r0.id] = $r0 }
    foreach ($c in $Model.Children['lint-rules']) {
      $rid = [string]$c['wikiAnchor']; $r = $byId[$rid]
      [void]$sb.Append("* [$rid]($($c['wikiPage'])#$rid) -- $($r.category), $($r.default_severity)$(if ($r.fixable) { ', fixable' } else { '' })`r`n")
    }
  }
  [void]$sb.Append("`r`n")
  return $sb.ToString()
}

function Render-QuickHelpPage {
  param([Parameter(Mandatory)]$Model)
  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.Append($Model.Templates['Quick-Help.intro.md'].TrimEnd() + "`r`n`r`n")
  $declared = New-Object 'System.Collections.Generic.List[string]'
  foreach ($g in $Model.Groups) {
    $rows = @($Model.Entries | Where-Object { [string]$_['group'] -eq [string]$g.id })
    if ($rows.Count -eq 0) { continue }
    [void]$sb.Append("## $($g.title)`r`n`r`n")
    foreach ($e in $rows) {
      if ($e.Contains('family')) {
        [void]$sb.Append("* **$($e['title'])** -- $(Get-FamilyCountText $Model $e). $($e['summary']). [More]($($e['wikiPage']))`r`n")
      } else {
        $intro = if ($e.Contains('intro')) { ' ' + [string]$e['intro'] } else { '' }
        $st = if ([string]$e['status'] -ne 'shipped') { ' (' + [string]$e['status'] + ')' } else { '' }
        [void]$sb.Append("* **$($e['title'])**$st -- $($e['summary']).$intro [More]($($e['wikiPage']))`r`n")
        $al = Get-EntryList $e 'aliases'; if ($al.Count) { [void]$sb.Append("  aliases: $($al -join ', ')`r`n") }
      }
      foreach ($s in (Get-EntryList $e 'surfaces')) {
        switch ([string]$s['type']) {
          'shortcut'    { $declared.Add("$($e['title']): shortcut $($s['keys'])") }
          'lsp'         { $declared.Add("$($e['title']): lsp $($s['method'])") }
          'workflow'    { $declared.Add("$($e['title']): procedure $($s['doc'])") }
          'ide-context' { $declared.Add("$($e['title']): host '$($s['host'])' (the caption is verified, the host is declared)") }
          'exe'         { if ($s.Contains('menu')) { $declared.Add("$($e['title']): menu '$($s['menu'])' inside $($s['name'])") } }
        }
      }
    }
    [void]$sb.Append("`r`n")
  }
  [void]$sb.Append("## Declared, not harvested`r`n`r`nThe guard verifies CLI verbs, menu captions, MCP tools, scripts and pages. The surfaces below are declared by their entries and exercised only by the periodic review; a green battery does not prove them.`r`n`r`n")
  foreach ($d in (Sort-OrdinalUnique ([string[]]$declared.ToArray()))) { [void]$sb.Append("* $d`r`n") }
  [void]$sb.Append("`r`n*Generated by ``tools\build-feature-pages.ps1`` from ``features\``; do not edit by hand.*`r`n")
  return $sb.ToString()
}

function Render-AgentVerbsBlock {
  param([Parameter(Mandatory)]$Model)
  $rows = New-Object 'System.Collections.Generic.List[object]'
  foreach ($e in $Model.Entries) {
    if ([string]$e['audience'] -notin @('agent', 'both')) { continue }
    if ([string]$e['status'] -eq 'planned') { continue }
    foreach ($s in (Get-EntryList $e 'surfaces')) {
      if ([string]$s['type'] -ne 'cli') { continue }
      $verb = [string]$s['verb'] + $(if ($s.Contains('sub')) { ' ' + [string]$s['sub'] } else { '' })
      $rows.Add([pscustomobject]@{ Verb = $verb + '|' + [string]$e['id']; Line = "| ``$verb`` | [$($e['title'])]($script:WikiUrl$($e['wikiPage'])) | $($e['summary']) | $((Get-EntryList $e 'requires') -join ', ') |" })
    }
  }
  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.Append("| Verb | Feature | Summary | Requires |`r`n|---|---|---|---|`r`n")
  foreach ($r in (Sort-ByOrdinalKey ([object[]]$rows.ToArray()) { param($x) $x.Verb })) { [void]$sb.Append($r.Line + "`r`n") }
  return $sb.ToString()
}

function Render-FeatureSummaryBlock {
  param([Parameter(Mandatory)]$Model)
  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.Append("| Group | Features | Wiki |`r`n|---|---:|---|`r`n")
  foreach ($g in $Model.Groups) {
    $rows = @($Model.Entries | Where-Object { [string]$_['group'] -eq [string]$g.id })
    $extra = @($rows | Where-Object { $_.Contains('family') } | ForEach-Object { Get-FamilyCountText $Model $_ } | Where-Object { $_ })
    $anchor = ([string]$g.title).ToLowerInvariant() -replace '[^a-z0-9 -]', '' -replace ' ', '-'
    [void]$sb.Append("| [$($g.title)]($($script:WikiUrl)Features#$anchor) | $($rows.Count)$(if ($extra.Count) { ' (+ ' + ($extra -join ', ') + ')' } else { '' }) | [Quick Help]($($script:WikiUrl)Quick-Help#$anchor) |`r`n")
  }
  return $sb.ToString()
}

# lastVerified is stripped: a review date would make every review a manifest diff.
function Remove-ManifestVolatile($E) { $o = ConvertTo-OrderedObject $E; if ($o.Contains('lastVerified')) { $o.Remove('lastVerified') }; return $o }

function Render-Manifest {
  param([Parameter(Mandatory)]$Model)
  $m = [ordered]@{
    product = [string]$Model.Live.Versions.Product; extractor = [string]$Model.Live.Versions.Extractor; resolver = [string]$Model.Live.Versions.Resolver; schema = [int]$Model.Live.Versions.Schema
    groups = @(foreach ($g in $Model.Groups) { ConvertTo-OrderedObject $g })
    teams = @(foreach ($t in @((Get-Content -LiteralPath $Model.Context.Paths.Teams -Raw | ConvertFrom-Json).teams)) { ConvertTo-OrderedObject $t })
    entries = @(foreach ($e in $Model.Entries) { Remove-ManifestVolatile $e })
    families = [ordered]@{}
  }
  $childOrder = [string[]]@($Model.Context.KeyOrder + $script:ChildOnlyKeys)
  foreach ($fam in $Model.Children.get_Keys()) { $m['families'][$fam] = @(foreach ($c in $Model.Children[$fam]) { Remove-ManifestVolatile (ConvertTo-CanonicalEntry -Entry $c -KeyOrder $childOrder) }) }
  return (ConvertTo-CanonicalJson -Value $m)
}

function Update-MarkedBlock {
  param([Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Body)
  $begin = "<!-- dl:registry:begin $Name -->"; $end = "<!-- dl:registry:end $Name -->"
  $i = $Text.IndexOf($begin, [StringComparison]::Ordinal); $j = $Text.IndexOf($end, [StringComparison]::Ordinal)
  if ($i -lt 0 -or $j -lt 0 -or $j -lt $i) { throw "markers absent: '$begin' / '$end' must both exist, in that order -- the generator never appends blindly" }
  return $Text.Substring(0, $i + $begin.Length) + "`r`n" + $Body + $Text.Substring($j)
}

function Get-DiffHead {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Old, [Parameter(Mandatory)][AllowEmptyString()][string]$New, [int]$Lines = 20)
  $a = $Old -split "`r?`n"; $b = $New -split "`r?`n"
  $n = [Math]::Min($a.Count, $b.Count); $first = $n
  for ($i = 0; $i -lt $n; $i++) { if ($a[$i] -cne $b[$i]) { $first = $i; break } }
  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.Append("@@ first difference at line $($first + 1) (old $($a.Count) lines, new $($b.Count) lines)`r`n")
  $half = [Math]::Max(1, [int][Math]::Floor($Lines / 2))
  for ($i = $first; $i -lt [Math]::Min($a.Count, $first + $half); $i++) { [void]$sb.Append("-$($a[$i])`r`n") }
  for ($i = $first; $i -lt [Math]::Min($b.Count, $first + $half); $i++) { [void]$sb.Append("+$($b[$i])`r`n") }
  return $sb.ToString()
}

function Invoke-RegistryGenerate {
  param([Parameter(Mandatory)]$Paths, [switch]$Check, [string]$OutDir = '')
  $model = Get-RegistryModel -Paths $Paths
  $root = if ($OutDir) { $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutDir) } else { $Paths.Repo }
  # The marked blocks are spliced into the TRACKED README/AI-USAGE text, also
  # under -OutDir, so the OutDir copy is what the repo file would become.
  $readmeSrc = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($Paths.Readme))
  $aiSrc = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($Paths.AiUsage))
  $outputs = [ordered]@{
    'docs\wiki\Home.md'                = Render-HomePage -Model $model
    'docs\wiki\Features.md'            = Render-FeaturesPage -Model $model
    'docs\wiki\Feature-Index.md'       = Render-FeatureIndexPage -Model $model
    'docs\wiki\Quick-Help.md'          = Render-QuickHelpPage -Model $model
    'README.md'                        = Update-MarkedBlock -Text $readmeSrc -Name 'feature-summary' -Body (Render-FeatureSummaryBlock -Model $model)
    'docs\AI-USAGE.md'                 = Update-MarkedBlock -Text $aiSrc -Name 'agent-verbs' -Body (Render-AgentVerbsBlock -Model $model)
    'features\generated\manifest.json' = Render-Manifest -Model $model
  }
  foreach ($k in @($outputs.Keys)) {
    $bad = [regex]::Match($outputs[$k], '[^\x00-\x7F]')
    if ($bad.Success) { throw ("generator: non-ASCII character U+{0} in rendered {1}" -f ([int]$bad.Value[0]).ToString('X4'), $k) }
  }
  $changed = New-Object 'System.Collections.Generic.List[object]'
  $written = New-Object 'System.Collections.Generic.List[string]'
  foreach ($rel in $outputs.Keys) {
    $target = Join-Path $root $rel
    $old = if (Test-Path -LiteralPath $target) { [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($target)) } else { '' }
    if ($old -ceq $outputs[$rel]) { continue }
    $changed.Add([pscustomobject]@{ Path = $rel; Diff = (Get-DiffHead -Old $old -New $outputs[$rel]) })
    if ($Check) { continue }
    $dir = Split-Path -Parent $target; if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($target, $outputs[$rel], [Text.Encoding]::ASCII)
    $written.Add($rel)
  }
  return [pscustomobject]@{ Outputs = $outputs; Changed = [object[]]$changed.ToArray(); Written = [string[]]$written.ToArray() }
}

Export-ModuleMember -Function Get-RegistryPaths, ConvertTo-OrderedObject, ConvertTo-CanonicalJson, Get-EntryKeyOrder, ConvertTo-CanonicalEntry, Get-EntryList, Test-AsciiCrlfFile, Read-FeatureEntry, Write-FeatureEntry, Test-EntryCanonicalBytes, Get-RegistryContext, Get-NearestCandidates, Test-FeatureEntry, Test-GroupsAndTeams, Get-LiveSurface, Read-FamilyDefinition, Import-LintRuleFamily, Import-ChartQuestionFamily, Get-RegistryChildren,
  ConvertFrom-SurfaceSpec, Get-CurrentBuildVersion, Add-RegistryGroup, Add-RegistryTeam, New-FeatureEntry, Update-FeatureEntry, Find-FeatureEntry, ConvertTo-MenuKey, Get-FeatureBlastRadius, Move-FeatureMenuPath, Set-FeatureDeprecated, Invoke-RegistryNormalise, Invoke-RegistryCheck,
  Get-RegistryModel, Update-MarkedBlock, Get-DiffHead, Invoke-RegistryGenerate, Get-EntrySkeleton
