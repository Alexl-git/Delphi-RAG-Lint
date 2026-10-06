#Requires -Version 7.3
<#
  run_feature_registry_canonical.ps1 -- the registry's schema, canonical form and
  per-entry validation behave as the spec says, and cannot pass vacuously.

  Pins (Review Focus 1-3): a hand id in a family namespace is refused; a wikiPage
  in the wrong CASE is refused against the exact-case directory listing; an LF
  rewrite of a valid entry is reported as not canonical, naming the file.
#>
[CmdletBinding()]
param([string]$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path,
      [string]$WorkDir = "$env:TEMP\drag-lint-feature-registry-canonical-$PID")
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
  if (-not $Ok) { $script:Failed = $true }
}
Write-Host '== feature registry: schema + canonical form ==' -ForegroundColor Cyan
if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Path $WorkDir | Out-Null

$mod = Join-Path $Repo 'tools\FeatureRegistry.psm1'
Check 'module present' (Test-Path -LiteralPath $mod) $mod
if (-not (Test-Path -LiteralPath $mod)) { Write-Host 'FEATURE REGISTRY CANONICAL: FAIL' -ForegroundColor Red; exit 1 }
Import-Module $mod -Force
$p = Get-RegistryPaths -Repo $Repo

# --- schema and key order ---------------------------------------------------
$keys = @(Get-EntryKeyOrder -Paths $p)
Check 'entry key order read from the schema' ($keys.Count -ge 20) "($($keys.Count) keys)"
Check 'key order starts id, title, group, owner' (($keys[0..3] -join ',') -eq 'id,title,group,owner')
Check 'key order ends lastVerified, homeOrder, tests' (($keys[-3..-1] -join ',') -eq 'lastVerified,homeOrder,tests')
$schemaTypes = @((Get-Content -LiteralPath (Join-Path $p.Schema 'entry.schema.json') -Raw | ConvertFrom-Json).properties.surfaces.items.properties.type.enum)
$modTypes = @((Get-Module FeatureRegistry).SessionState.PSVariable.GetValue('SurfaceKeys').Keys)
Check 'schema surface types == module surface types' ((($schemaTypes | Sort-Object) -join ',') -eq (($modTypes | Sort-Object) -join ',')) "schema: $($schemaTypes -join ' ')"

# --- groups and teams -------------------------------------------------------
$ctx = Get-RegistryContext -Paths $p
Check 'groups.json has the 12 seed groups' ($ctx.Groups.Count -eq 12) "($($ctx.Groups.Count))"
Check 'teams.json has ENGINE CONVERTER CHARTS' (($ctx.Teams.Contains('ENGINE')) -and ($ctx.Teams.Contains('CONVERTER')) -and ($ctx.Teams.Contains('CHARTS')))
$gt = @(Test-GroupsAndTeams -Context $ctx)
Check 'groups and teams validate' ($gt.Count -eq 0) ($gt -join '; ')
Check 'CHANGELOG versions harvested' ($ctx.ChangelogVersions.Count -gt 30) "($($ctx.ChangelogVersions.Count))"
Check 'wiki page set is exact-case (rules, not Rules)' ($ctx.WikiPages.Contains('rules') -and -not $ctx.WikiPages.Contains('Rules'))

# --- canonical JSON serialiser ---------------------------------------------
$sample = [ordered]@{ b = 'x'; a = @('q', 'p'); n = 3; t = $true; o = [ordered]@{ z = 1; y = @() }; arr = @([ordered]@{ k = 'v' }) }
$expected = "{`r`n  `"b`": `"x`",`r`n  `"a`": [`"q`", `"p`"],`r`n  `"n`": 3,`r`n  `"t`": true,`r`n  `"o`": {`r`n    `"z`": 1,`r`n    `"y`": []`r`n  },`r`n  `"arr`": [`r`n    {`r`n      `"k`": `"v`"`r`n    }`r`n  ]`r`n}`r`n"
$got = ConvertTo-CanonicalJson -Value $sample
Check 'canonical JSON bytes are exact (order kept, CRLF, inline scalar arrays)' ($got -ceq $expected) $(if ($got -cne $expected) { "got: " + ($got -replace "`r`n", '|') } else { '' })
$threw = $false
try { ConvertTo-CanonicalJson -Value ([ordered]@{ s = ('caf' + [char]0xE9) }) | Out-Null } catch { $threw = $true }
Check 'serialiser refuses a non-ASCII character' $threw

# --- a valid entry ----------------------------------------------------------
$valid = [ordered]@{
  id = 'zz-sample-feature'; title = 'Sample feature'; group = 'maintenance'; owner = 'ENGINE'
  status = 'shipped'; since = '1.21.1-alpha'
  summary = 'A sample entry used only by the canonical-form guard'
  intro = 'It exists to prove the validator. It is never registered.'
  wikiPage = 'Maintenance'
  surfaces = @([ordered]@{ type = 'cli'; verb = 'info' }, [ordered]@{ type = 'ide-menu'; path = 'drag-lint > About > Diagnose Current State' })
  audience = 'both'
  aliases = @('zeta', 'alpha'); related = @()
  lastVerified = [ordered]@{ date = '2026-10-05'; by = 'guard'; build = '1.21.1-alpha' }
}
$probs = @(Test-FeatureEntry -Entry $valid -Context $ctx -Stem 'zz-sample-feature')
Check 'a valid entry has no problems' ($probs.Count -eq 0) ($probs -join '; ')

function Expect-Problem([string]$Name, [System.Collections.Specialized.OrderedDictionary]$E, [string]$Stem, [string]$Needle) {
  $pr = @(Test-FeatureEntry -Entry $E -Context $ctx -Stem $Stem)
  $hit = @($pr | Where-Object { $_ -like "*$Needle*" })
  Check $Name ($hit.Count -gt 0) $(if ($hit.Count -eq 0) { "no problem matched '$Needle'; got: " + ($pr -join ' | ') } else { $hit[0] })
}
function Clone([System.Collections.Specialized.OrderedDictionary]$E) { return (ConvertTo-OrderedObject -Value ($E | ConvertTo-Json -Depth 10 | ConvertFrom-Json)) }

$e = Clone $valid; $e.id = 'rule.zz-sample'
Expect-Problem 'REVIEW FOCUS 1: a hand id in a family namespace is refused' $e 'rule.zz-sample' 'importers own'
$e = Clone $valid
Expect-Problem 'id must equal the filename stem' $e 'other-stem' 'filename'
$e = Clone $valid; $e.group = 'no-such-group'
Expect-Problem 'unknown group is refused' $e 'zz-sample-feature' 'group'
$e = Clone $valid; $e.owner = 'NOBODY'
Expect-Problem 'unknown owner is refused' $e 'zz-sample-feature' 'teams.json'
$e = Clone $valid; $e.wikiPage = 'Rules'
Expect-Problem 'REVIEW FOCUS 2: a wikiPage in the wrong case is refused' $e 'zz-sample-feature' 'did you mean: rules'
$e = Clone $valid; $e.since = '9.9.9-alpha'
Expect-Problem 'since must be a CHANGELOG heading' $e 'zz-sample-feature' 'CHANGELOG'
$e = Clone $valid; $e.lastVerified.date = '2999-01-01'
Expect-Problem 'lastVerified.date in the future is refused' $e 'zz-sample-feature' 'future'
$e = Clone $valid; $e.surfaces = @()
Expect-Problem 'a shipped entry needs a surface' $e 'zz-sample-feature' 'surfaces'
$e = Clone $valid; $e.related = @('no-such-entry')
Expect-Problem 'related must resolve' $e 'zz-sample-feature' 'no-such-entry'
$e = Clone $valid; $e.supersededBy = 'zz-other'
Expect-Problem 'supersededBy only with deprecated' $e 'zz-sample-feature' 'deprecated'
$e = Clone $valid; $e.summary = 'Ends with a period which the spec forbids.'
Expect-Problem 'summary must not end with a period' $e 'zz-sample-feature' 'period'
$e = Clone $valid; $e.surfaces = @([ordered]@{ type = 'ide-context'; caption = 'Fix it' })
Expect-Problem 'a surface missing a required key is refused' $e 'zz-sample-feature' 'host'
$e = Clone $valid; $e.surfaces = @([ordered]@{ type = 'script'; path = 'charts\src\No-Such.ps1' })
Expect-Problem 'a script surface must exist on disk' $e 'zz-sample-feature' 'No-Such.ps1'
$e = Clone $valid; $e.extraKey = 1
Expect-Problem 'an unknown key is refused' $e 'zz-sample-feature' 'extraKey'
$e = Clone $valid; $e.Remove('intro')
Expect-Problem 'shipped without intro is refused outside the seed backlog' $e 'zz-sample-feature' 'intro'
$bl = New-Object 'System.Collections.Generic.HashSet[string]'; [void]$bl.Add('zz-sample-feature')
$ctxBl = Get-RegistryContext -Paths $p -SeedBacklog $bl
$e = Clone $valid; $e.Remove('intro'); $e.Remove('lastVerified')
Check 'the seed backlog exempts intro and lastVerified' (@(Test-FeatureEntry -Entry $e -Context $ctxBl -Stem 'zz-sample-feature').Count -eq 0)
$ctxKids = Get-RegistryContext -Paths $p -ExtraIds @('chart.who-calls')
$e = Clone $valid; $e.related = @('chart.who-calls')
Check 'related resolves a family child id when supplied' (@(Test-FeatureEntry -Entry $e -Context $ctxKids -Stem 'zz-sample-feature').Count -eq 0)

# --- write / read round trip, REVIEW FOCUS 3 --------------------------------
$f = Join-Path $WorkDir 'zz-sample-feature.json'
$changed1 = Write-FeatureEntry -Entry $valid -Path $f -KeyOrder $keys
$changed2 = Write-FeatureEntry -Entry $valid -Path $f -KeyOrder $keys
Check 'first write reports a change, second write is a no-op' ($changed1 -and -not $changed2)
$r = Read-FeatureEntry -Path $f
Check 'aliases were sorted by the normaliser' (($r.Entry.aliases -join ',') -eq 'alpha,zeta')
Check 'empty related was omitted' (-not $r.Entry.Contains('related'))
Check 'written file is canonical' ((Test-EntryCanonicalBytes -Read $r -KeyOrder $keys) -eq '')
$bytes = [IO.File]::ReadAllBytes($f)
Check 'written file has CRLF and no BOM' (($bytes[0] -eq 0x7B) -and ([Text.Encoding]::ASCII.GetString($bytes) -match "`r`n") -and (-not ([Text.Encoding]::ASCII.GetString($bytes) -match "[^`r]`n")))
$lf = ([IO.File]::ReadAllText($f)) -replace "`r`n", "`n"
[IO.File]::WriteAllText($f, $lf, [Text.Encoding]::ASCII)
$r2 = Read-FeatureEntry -Path $f
$msg = Test-EntryCanonicalBytes -Read $r2 -KeyOrder $keys
Check 'REVIEW FOCUS 3: an LF rewrite is reported as not canonical, naming the file' (($msg -like '*zz-sample-feature.json*') -and ($msg -like '*not canonical*')) $msg
$fixed = Write-FeatureEntry -Entry $r2.Entry -Path $f -KeyOrder $keys
Check 'normalising rewrites it' $fixed
Check 'and it is canonical again' ((Test-EntryCanonicalBytes -Read (Read-FeatureEntry -Path $f) -KeyOrder $keys) -eq '')
$bad = Join-Path $WorkDir 'bad.json'
[IO.File]::WriteAllBytes($bad, [byte[]](0x7B, 0x22, 0x61, 0x22, 0x3A, 0x22, 0xE9, 0x22, 0x7D))
$threw = $false; try { Read-FeatureEntry -Path $bad | Out-Null } catch { $threw = ($_.Exception.Message -like '*byte 6*') }
Check 'a non-ASCII byte is refused on read with its offset' $threw
$asc = Test-AsciiCrlfFile -Path $bad
Check 'Test-AsciiCrlfFile names the non-ASCII line' ($asc -like '*bad.json:1*')
$tmpl = Join-Path $p.Features 'related-projects.json'
Check 'related-projects.json is ASCII+CRLF' ((Test-AsciiCrlfFile -Path $tmpl) -eq '')

Write-Host ''
if ($script:Failed) { Write-Host 'FEATURE REGISTRY CANONICAL: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'FEATURE REGISTRY CANONICAL: PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d in @("$env:TEMP\drag-lint-feature-registry-canonical-$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
