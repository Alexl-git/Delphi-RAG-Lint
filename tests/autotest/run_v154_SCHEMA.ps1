<#
  run_v154_SCHEMA.ps1 -- 1.54 lane SCHEMA: schema-unknown-column, schema-type-mismatch, schema-required-not-set and the
  option schema_rules.local_naming_match, on tests\fixtures\v154\SCHEMA with a field repository restored from repo.txt.
  A .pas line that must report carries "// FIRE <rule>"; every other line must stay silent, so each rule has firing and
  silent controls in the same run. The expected .dfm findings are listed below by the text of their line.
  Also: the exception row, no repository, a repository without facts, a missing one, --project on a database copy, lint <file>.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-v154-schema-$PID"
)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
try {
$ErrorActionPreference = 'Stop'
$script:Failed = 0
$script:Passed = 0
function Check($n, $ok, $d = '') {
  if ($ok) { $script:Passed++ } else { $script:Failed++ }
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $(if ($ok) { '' } else { $d })) -ForegroundColor $c
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Fix = (Resolve-Path "$PSScriptRoot\..\fixtures\v154\SCHEMA").Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$OffCfg = Join-Path $WorkDir 'off.json'
$OnCfg  = Join-Path $WorkDir 'on.json'
[IO.File]::WriteAllText($OffCfg, '{}', [Text.Encoding]::ASCII)
[IO.File]::WriteAllText($OnCfg, '{"schema_rules":{"local_naming_match":true}}', [Text.Encoding]::ASCII)

function Invoke-Engine([string[]]$Argv) {
  $out = & { $ErrorActionPreference = 'Continue'; & $Exe @Argv 2>&1 | ForEach-Object { "$_" } }
  return ,@($out)
}
# One copy of the fixture project per scenario. $Backup: the repository text, $null = no repository configured.
function New-Project([string]$Name, [AllowNull()][object]$Backup) {
  $dir = Join-Path $WorkDir $Name
  $home_ = Join-Path $dir '_D-RAG'
  New-Item -ItemType Directory $home_ | Out-Null
  Copy-Item "$Fix\*" $dir
  if ($null -ne $Backup) {
    [IO.File]::WriteAllText((Join-Path $home_ 'drag-lint-project.json'), '{ "fieldRepository": "schema.dlrepo" }', [Text.Encoding]::ASCII)
    $bk = Join-Path $WorkDir "$Name.txt"
    [IO.File]::WriteAllText($bk, $Backup, [Text.Encoding]::ASCII)
    $r = Invoke-Engine @('repo', 'restore', '--in', $bk, '--repo', (Join-Path $dir 'schema.dlrepo'))
    if ($LASTEXITCODE -ne 0) { Write-Host ($r -join "`n") }
  }
  $p = [pscustomobject]@{ Dir = $dir; Proj = (Join-Path $dir 'SchemaFixture.dproj'); Db = (Join-Path $home_ 'SchemaFixture.sqlite') }
  Invoke-Engine @('index', '--project', $p.Proj, '--db', $p.Db) | Out-Null
  return $p
}
# "file:line rule" of every finding
function Get-Found([string[]]$Argv) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $Exe @Argv --json 2>$null }
  $txt = ($raw | Where-Object { $_ -is [string] }) -join "`n"
  $i = $txt.IndexOf('['); if ($i -lt 0) { return @() }
  return ,@($txt.Substring($i) | ConvertFrom-Json | ForEach-Object { $_ } | ForEach-Object {
    $p = if ($_.file_path) { $_.file_path } elseif ($_.path) { $_.path } else { $_.file }
    $r = if ($_.rule_id) { $_.rule_id } else { $_.rule }
    "{0}:{1} {2}" -f (Split-Path $p -Leaf), $_.start_line, $r })
}
function Get-All([string]$Rule, $P, [string]$Cfg = $OffCfg) {
  $r = Get-Found @('lint-all', '--db', $P.Db, '--config', $Cfg, '--rule', $Rule)
  return ,@($r)
}
function Get-Wanted([string]$Rule) {
  return ,@(Get-ChildItem $Fix -Filter *.pas | ForEach-Object { $f = $_; $n = 0
    Get-Content $f.FullName | ForEach-Object { $n++; if ($_ -match "// FIRE $Rule\b") { "{0}:{1} {2}" -f $f.Name, $n, $Rule } } })
}
# The .dfm line that starts the object $Object, plus $Skip lines.
function Get-DfmLine([string]$Object, [int]$Skip = 0) {
  $n = 0
  foreach ($l in [IO.File]::ReadAllLines((Join-Path $Fix 'DataMod.dfm'))) { $n++; if ($l -match "object $Object\b") { return $n + $Skip } }
  return -1
}
$Dfm = @{
  'schema-unknown-column'   = @(('DataMod.dfm:{0}' -f (Get-DfmLine 'qryOrdersGONE' 1)), ('DataMod.dfm:{0}' -f (Get-DfmLine 'tblOrdersLOST' 1)), ('DataMod.dfm:{0}' -f (Get-DfmLine 'qryBad' 1)))
  'schema-type-mismatch'    = @(('DataMod.dfm:{0}' -f (Get-DfmLine 'qryOrdersCREATED')), ('DataMod.dfm:{0}' -f (Get-DfmLine 'tblOrdersQTY')))
  'schema-required-not-set' = @(,('DataMod.dfm:{0}' -f (Get-DfmLine 'qryIns' 1)))
}
function Compare-Rule([string]$Rule, $P) {
  $pas = Get-Wanted $Rule
  $want = @($pas) + @($Dfm[$Rule] | ForEach-Object { "$_ $Rule" })
  $got  = Get-All $Rule $P
  Check "$Rule has firing controls in .pas and .dfm" (($pas.Count -gt 0) -and ($want.Count -gt $pas.Count))
  foreach ($w in $want) { Check "fires $w" ($got -contains $w) }
  $extra = @($got | Where-Object { $want -notcontains $_ })
  Check "$Rule is silent elsewhere" ($extra.Count -eq 0) ($extra -join ', ')
}
$RULES = @('schema-unknown-column', 'schema-type-mismatch', 'schema-required-not-set')
$repoText = [IO.File]::ReadAllText((Join-Path $Fix 'repo.txt'))
$noExc = [regex]::Replace($repoText, '(?s)\[DL_EXCEPTIONS [^\r\n]*\r\nREASON=[^\r\n]*\r\n\r\n#end DL_EXCEPTIONS 1', '#end DL_EXCEPTIONS 0')
$noFacts = [regex]::Replace($noExc, '(?s)\[DL_META schema_database\].*?(\[DL_META schema_version\])', '$1').Replace('#end DL_META 4', '#end DL_META 1')
Check 'the repository variants differ' (($noExc -ne $repoText) -and ($noFacts -ne $noExc))

Write-Host 'WITH THE REPOSITORY' -ForegroundColor Cyan
$base = New-Project 'base' $noExc
Check 'the repository is restored' (Test-Path (Join-Path $base.Dir 'schema.dlrepo'))
# positive-control: schema-unknown-column
Compare-Rule 'schema-unknown-column' $base
# positive-control: schema-type-mismatch
Compare-Rule 'schema-type-mismatch' $base
# positive-control: schema-required-not-set
Compare-Rule 'schema-required-not-set' $base

Write-Host 'THE DEFAULTS AND THE MESSAGES' -ForegroundColor Cyan
$full = Get-Found @('lint-all', '--db', $base.Db, '--config', $OffCfg)
Check 'a run without --rule reports the same schema-unknown-column findings once' (@($full | Where-Object { $_ -like '* schema-unknown-column' }).Count -eq (Get-All 'schema-unknown-column' $base).Count)
Check 'schema-required-not-set is off by default' (@($full | Where-Object { $_ -like '* schema-required-not-set' }).Count -eq 0)
$text = (Invoke-Engine @('lint-all', '--db', $base.Db, '--config', $OffCfg, '--rule', 'schema-type-mismatch')) -join "`n"
Check 'the message names column, type and accessor' ($text -match 'ORDERS\.NOTE is VARCHAR\(20\).*AsInteger') ''
Check 'a narrowed run names the repository once' ([regex]::Matches($text, 'schema facts 2026-11-24').Count -eq 1)

Write-Host 'LOCAL NAMES (G-72)' -ForegroundColor Cyan
foreach ($rule in 'schema-length-bound', 'schema-maxlen-drift') {
  $off = @((Get-All $rule $base) | Where-Object { $_ -like 'LocalNames*' })
  Check "$rule ignores local names by default" ($off.Count -eq 0) ($off -join ', ')
  $on = @((Get-All $rule $base $OnCfg) | Where-Object { $_ -like 'LocalNames*' })
  $want = Get-Wanted $rule
  Check "$rule with the option reports the marked locals" (($want.Count -gt 0) -and (($on | Sort-Object) -join ',') -eq (($want | Sort-Object) -join ',')) "got $($on -join ', ') want $($want -join ', ')"
}

Write-Host 'EXCEPTIONS' -ForegroundColor Cyan
$exc = New-Project 'exc' $repoText
$a = Get-All 'schema-unknown-column' $base
$b = Get-All 'schema-unknown-column' $exc
Check 'the DL_EXCEPTIONS row removes the one finding' (($a.Count - $b.Count) -eq 1) "$($a.Count) -> $($b.Count)"

Write-Host 'SILENCE' -ForegroundColor Cyan
$none = New-Project 'none' $null
$nf   = New-Project 'nofacts' $noFacts
foreach ($rule in $RULES) {
  Check "$rule is silent without a repository" ((Get-All $rule $none).Count -eq 0)
  Check "$rule is silent on a repository without schema facts" ((Get-All $rule $nf).Count -eq 0)
}
$gone = New-Project 'gone' $noExc
[IO.File]::Delete((Join-Path $gone.Dir 'schema.dlrepo'))
$o = Invoke-Engine @('lint-all', '--db', $gone.Db, '--config', $OffCfg, '--rule', 'schema-unknown-column')
Check 'a missing repository is named once, not silently ignored' (@($o | Where-Object { $_ -match 'schema\.dlrepo not found' }).Count -eq 1) ($o -join ' | ')

Write-Host 'OTHER WAYS IN' -ForegroundColor Cyan
$copy = Join-Path $WorkDir 'copy.sqlite'
Copy-Item $base.Db $copy
$c = Get-Found @('lint-all', '--db', $copy, '--project', $base.Proj, '--config', $OffCfg, '--rule', 'schema-unknown-column')
Check 'a database copy with --project finds the same' ($c.Count -eq $a.Count) "$($c.Count) vs $($a.Count)"
$f = Get-Found @('lint', (Join-Path $base.Dir 'DataMod.pas'), '--db', $base.Db, '--config', $OffCfg, '--rule', 'schema-unknown-column')
$w = @($a | Where-Object { $_ -like 'DataMod.*' })
Check 'lint <file> reports the unit and its form' (($w.Count -gt 3) -and ($f.Count -eq $w.Count)) "$($f.Count) vs $($w.Count)"
$u = Get-Found @('lint', (Join-Path $base.Dir 'UnknownCols.pas'), '--db', $base.Db, '--config', $OffCfg)
Check 'lint <file> without --rule reports it too' (@($u | Where-Object { $_ -like '* schema-unknown-column' }).Count -eq @($a | Where-Object { $_ -like 'UnknownCols*' }).Count)

Write-Host ("run_v154_SCHEMA: {0} passed, {1} failed" -f $script:Passed, $script:Failed)
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  if (($WorkDir -like "$env:TEMP\drag-lint-v154-schema-*") -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}