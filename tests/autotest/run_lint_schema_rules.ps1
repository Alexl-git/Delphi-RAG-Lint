<#
  1.53 lane FR-LINT: schema-maxlen-drift (rule 1) and schema-length-bound (rule 2) read the char
  lengths from the FIELD REPOSITORY (owner ruling FR-3), never from the index. Fixture
  tests\lint\schema (repo.txt = the #DLREPO 2 text backup with the schema facts + one DL_EXCEPTIONS row).

  T1 constants   MSCLIST_DIMABBR_MAXLEN (35 vs domain fallback 10) fires; MSCLIST_DIMNAME_MAXLEN (35 = 35)
                 silent; MSCLIST_NOPE_MAXLEN silent; lower-case orders_note_maxlen fires; CFG_ITEM_CODE_MAXLEN
                 resolves table CFG$ITEM and fires; CFG_ITEM_CODE_WIDTH silent.
  T2 literal     ORM-linked NOTE := '<21 chars>' fires; 20 chars silent.
  T3 rule 2      Copy(s, 1, MSCLIST_DIMNAME_MAXLEN) into the linked DIMABBR property fires, Copy(s, 1, 10)
                 silent; FieldByName('NOTE').Size := 30 fires, 20 silent; qryOrdersNOTE.AsString :=
                 Copy(..., 25) fires; DFM qryOrdersNOTE Size = 25 fires, tblOrdersNOTE (default 20) silent,
                 qryListDIMNAME (default 20 vs 35) fires, qryFree (no table) silent; the tDIMABBR local is
                 silent (FR-6).
  T4 silence     no fieldRepository -> 0 schema findings, no banner; a repository without schema facts ->
                 same; with facts the banner `schema facts <utc> (<source>) from <file>` appears once.
  T5 exceptions  the DL_EXCEPTIONS row (schema-length-bound, '', ORDERS, NOTE, '') removes the NOTE
                 schema-length-bound findings only; DIMABBR / DIMNAME ones stay (positive control).
  T6 lint <file> per-file lint reports the same uBounds findings as lint-all.

  RED on the 1.52.3 lane engine: 0 schema findings (the rules do not exist). -RepoExe restores the
  repository (a #DLREPO 2 backup needs a 1.53 engine); it defaults to -Exe.
  Usage: pwsh -File tests/autotest/run_lint_schema_rules.ps1 [-Exe <drag-lint.exe>] [-RepoExe <exe>]
#>
[CmdletBinding()]
param(
  [string] $Exe     = '',
  [string] $RepoExe = '',
  [string] $WorkDir = "$env:TEMP\drag-lint-schemalint-$PID"
)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
if (-not $RepoExe) { $RepoExe = $Exe }
$ErrorActionPreference = 'Stop'
$script:Failed = 0
$script:Passed = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Passed++; Write-Host "  [PASS] $Name" -ForegroundColor Green }
  else     { $script:Failed++; Write-Host "  [FAIL] $Name $Detail" -ForegroundColor Red }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$RepoExe = (Resolve-Path $RepoExe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$fix = (Resolve-Path "$PSScriptRoot\..\lint\schema").Path
$repoText = [IO.File]::ReadAllText((Join-Path $fix 'repo.txt'))

function Invoke-Engine([string[]]$EngineArgs, [string]$Engine = $Exe) {
  $out = & { $ErrorActionPreference = 'Continue'; & $Engine @EngineArgs 2>&1 | ForEach-Object { "$_" } }
  return ,@($out)
}

# Runs the engine with stdout and stderr captured SEPARATELY (Invoke-Engine merges them).
function Invoke-EngineSplit([string[]]$EngineArgs) {
  $psi = New-Object Diagnostics.ProcessStartInfo
  $psi.FileName = $Exe
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  foreach ($a in $EngineArgs) { $psi.ArgumentList.Add($a) }
  $pr = [Diagnostics.Process]::Start($psi)
  $so = $pr.StandardOutput.ReadToEndAsync()
  $se = $pr.StandardError.ReadToEndAsync()
  $pr.WaitForExit()
  return [pscustomobject]@{ Out = $so.Result; Err = $se.Result }
}
# One fixture copy per scenario: the repository file name is fixed by _D-RAG\drag-lint-project.json.
function New-Scenario([string]$Name, [AllowNull()][object]$RepoBackup) {
  $dir = Join-Path $WorkDir $Name
  Copy-Item -Recurse $fix $dir
  $cfg = Join-Path $dir '_D-RAG\drag-lint-project.json'
  if ($null -eq $RepoBackup) {
    [IO.File]::Delete($cfg)
  } else {
    $bk = Join-Path $WorkDir "$Name.txt"
    [IO.File]::WriteAllText($bk, $RepoBackup, [Text.Encoding]::ASCII)
    $r = Invoke-Engine @('repo', 'restore', '--in', $bk, '--repo', (Join-Path $dir 'schema.dlrepo')) $RepoExe
    if ($LASTEXITCODE -ne 0) { Write-Host ($r -join "`n") }
  }
  $proj = Join-Path $dir 'SchemaLintFixture.dproj'
  $db = Join-Path $dir '_D-RAG\SchemaLintFixture.sqlite'
  $sqlDb = Join-Path $WorkDir "$Name-sql.sqlite"
  Invoke-Engine @('index', '--project', $proj, '--db', $db) | Out-Null
  Invoke-Engine @('index', (Join-Path $dir 'schema.sql'), '--db', $sqlDb) | Out-Null
  Invoke-Engine @('link-orm', '--db', $sqlDb, '--db', $db) | Out-Null   # rows land in the LAST --db
  return [pscustomobject]@{ Dir = $dir; Proj = $proj; Db = $db }
}

# lint-all as JSON: the schema findings, the raw output lines and the total finding count.
function Get-SchemaFindings($Sc, [string[]]$Extra = @()) {
  $jsonFile = Join-Path $Sc.Dir 'lint.json'
  $lines = Invoke-Engine (@('lint-all', '--db', $Sc.Db, '--project', $Sc.Proj, '--json', '--output', $jsonFile) + $Extra)
  $all = @()
  if (Test-Path $jsonFile) {
    $raw = [IO.File]::ReadAllText($jsonFile)
    if ($raw.Trim() -ne '') { $all = @(($raw | ConvertFrom-Json) | ForEach-Object { $_ }) }
  }
  $schema = @($all | Where-Object { $_.rule -like 'schema-*' })
  return [pscustomobject]@{ Findings = $schema; Lines = $lines; All = $all.Count }
}
function Has($F, [string]$Rule, [string]$File, [int]$Line) {
  return @($F | Where-Object { $_.rule -eq $Rule -and (Split-Path $_.file_path -Leaf) -eq $File -and $_.start_line -eq $Line }).Count -eq 1
}
function LineOf([string]$File, [string]$Needle) {
  $i = 0
  foreach ($l in [IO.File]::ReadAllLines((Join-Path $fix $File))) { $i++; if ($l.Contains($Needle)) { return $i } }
  return -1
}

try {
  $noExc = [regex]::Replace($repoText, '(?s)\[DL_EXCEPTIONS [^\r\n]*\r\nREASON=[^\r\n]*\r\n\r\n#end DL_EXCEPTIONS 1', '#end DL_EXCEPTIONS 0')
  $noFacts = [regex]::Replace($noExc, '(?s)\[DL_META schema_database\].*?(\[DL_META schema_version\])', '$1').Replace('#end DL_META 4', '#end DL_META 1')
  Check 'K0 fixture variants differ from the backup' (($noExc -ne $repoText) -and ($noFacts -ne $noExc) -and $noFacts.Contains('#end DL_META 1'))

  $base = New-Scenario 'facts' $noExc
  Check 'K1 repository restored' (Test-Path (Join-Path $base.Dir 'schema.dlrepo'))
  $links = Invoke-Engine @('sql', '--db', $base.Db, '--query', "SELECT count(*) FROM orm_links WHERE link_kind = 'field_to_column'", '--json')
  Check 'K2 link-orm linked the ORM fields' ((($links -join '') -match '"rows"\s*:\s*\[\s*\[\s*3\s*\]'))  "$($links -join ' ')"

  $r = Get-SchemaFindings $base
  $f = $r.Findings
  Write-Host "  (schema findings: $($f.Count); all findings: $($r.All))"
  foreach ($x in $f) { Write-Host ("    {0} {1}:{2} {3}" -f $x.rule, (Split-Path $x.file_path -Leaf), $x.start_line, $x.message) }

  # T1 constants
  # positive-control: schema-maxlen-drift
  Check 'T1a DIMABBR_MAXLEN 35 vs domain 10 fires'  (Has $f 'schema-maxlen-drift' 'uMaxLen.pas' (LineOf 'uMaxLen.pas' 'MSCLIST_DIMABBR_MAXLEN = 35'))
  Check 'T1b DIMNAME_MAXLEN 35 = 35 silent'         (-not (Has $f 'schema-maxlen-drift' 'uMaxLen.pas' (LineOf 'uMaxLen.pas' 'MSCLIST_DIMNAME_MAXLEN = 35')))
  Check 'T1c NOPE_MAXLEN silent'                    (-not (Has $f 'schema-maxlen-drift' 'uMaxLen.pas' (LineOf 'uMaxLen.pas' 'MSCLIST_NOPE_MAXLEN')))
  Check 'T1d lower-case orders_note_maxlen fires'   (Has $f 'schema-maxlen-drift' 'uMaxLen.pas' (LineOf 'uMaxLen.pas' 'orders_note_maxlen'))
  Check 'T1e CFG_ITEM_CODE_MAXLEN -> CFG$ITEM fires' (Has $f 'schema-maxlen-drift' 'uMaxLen.pas' (LineOf 'uMaxLen.pas' 'CFG_ITEM_CODE_MAXLEN'))
  Check 'T1f non-MAXLEN constant silent'            (-not (Has $f 'schema-maxlen-drift' 'uMaxLen.pas' (LineOf 'uMaxLen.pas' 'CFG_ITEM_CODE_WIDTH')))
  # T2 literal
  Check 'T2a 21-char literal into NOTE fires'       (Has $f 'schema-maxlen-drift' 'uBounds.pas' (LineOf 'uBounds.pas' "'123456789012345678901'"))
  Check 'T2b 20-char literal silent'                (-not (Has $f 'schema-maxlen-drift' 'uBounds.pas' (LineOf 'uBounds.pas' "'12345678901234567890';")))
  # T3 rule 2
  # positive-control: schema-length-bound
  Check 'T3a Copy(.., DIMNAME_MAXLEN) into DIMABBR fires' (Has $f 'schema-length-bound' 'uBounds.pas' (LineOf 'uBounds.pas' 'pList.DIMABBR := Copy(pText, 1, MSCLIST_DIMNAME_MAXLEN)'))
  Check 'T3b Copy(.., 10) into DIMABBR silent'      (-not (Has $f 'schema-length-bound' 'uBounds.pas' (LineOf 'uBounds.pas' 'pList.DIMABBR := Copy(pText, 1, 10)')))
  Check 'T3c Copy(.., 35) into DIMNAME silent'      (-not (Has $f 'schema-length-bound' 'uBounds.pas' (LineOf 'uBounds.pas' 'pList.DIMNAME := Copy(pText, 1, MSCLIST_DIMNAME_MAXLEN)')))
  Check 'T3d tDIMABBR local silent (FR-6)'           (@($f | Where-Object { (Split-Path $_.file_path -Leaf) -eq 'uBounds.pas' -and $_.start_line -eq (LineOf 'uBounds.pas' 'tDIMABBR := Copy') }).Count -eq 0)
  Check 'T3e FieldByName(NOTE).Size := 30 fires'    (Has $f 'schema-length-bound' 'fMain.pas' (LineOf 'fMain.pas' ".Size := 30;"))
  Check 'T3f FieldByName(NOTE).Size := 20 silent'   (-not (Has $f 'schema-length-bound' 'fMain.pas' (LineOf 'fMain.pas' ".Size := 20;")))
  Check 'T3g qryOrdersNOTE.AsString := Copy(.., 25) fires' (Has $f 'schema-length-bound' 'fMain.pas' (LineOf 'fMain.pas' 'qryOrdersNOTE.AsString'))
  Check 'T3h qryFree (no table) silent'             (-not (Has $f 'schema-length-bound' 'fMain.pas' (LineOf 'fMain.pas' 'qryFree.FieldByName')))
  Check 'T3i DFM qryOrdersNOTE Size = 25 fires'     (Has $f 'schema-length-bound' 'fMain.dfm' (LineOf 'fMain.dfm' 'Size = 25'))
  Check 'T3j DFM qryListDIMNAME default 20 vs 35 fires' (Has $f 'schema-length-bound' 'fMain.dfm' (LineOf 'fMain.dfm' 'object qryListDIMNAME'))
  Check 'T3k DFM tblOrdersNOTE default 20 silent'   (-not (Has $f 'schema-length-bound' 'fMain.dfm' (LineOf 'fMain.dfm' 'object tblOrdersNOTE')))
  Check 'T3l DFM qryFreeNOTE (no table) silent'     (-not (Has $f 'schema-length-bound' 'fMain.dfm' (LineOf 'fMain.dfm' 'Size = 99')))
  Check 'T3m exactly 10 schema findings'            ($f.Count -eq 10) "count=$($f.Count)"
  # T7 binding, not bare names (a default-on rule must not flood)
  Check 'T7a local dataset of a known name silent'  (-not (Has $f 'schema-length-bound' 'uShadow.pas' (LineOf 'uShadow.pas' '.Size := 77')))
  Check 'T7b parameter named like a const silent'   (-not (Has $f 'schema-length-bound' 'uShadow.pas' (LineOf 'uShadow.pas' 'Copy(pText, 1, NOTE_LIMIT)')))
  Check 'T7c property with a setter silent'         (-not (Has $f 'schema-maxlen-drift' 'uShadow.pas' (LineOf 'uShadow.pas' 'pOrder.NOTETRIM :=')))
  Check 'T7d form dataset from another unit fires'  (Has $f 'schema-length-bound' 'uShadow.pas' (LineOf 'uShadow.pas' '.Size := 88'))
  # T4 banner
  $banner = @($r.Lines | Where-Object { $_ -match 'schema facts 2026-11-22T12:00:00Z \(ddl\) from schema\.dlrepo' })
  Check 'T4a banner printed exactly once'           ($banner.Count -eq 1) "count=$($banner.Count)"

  $none = New-Scenario 'norepo' $null
  $rn = Get-SchemaFindings $none
  Check 'T4b no fieldRepository -> 0 schema findings' ($rn.Findings.Count -eq 0) "count=$($rn.Findings.Count)"
  Check 'T4c no fieldRepository -> no banner'       (@($rn.Lines | Where-Object { $_ -match 'schema facts' }).Count -eq 0)
  Check 'T4d no fieldRepository -> lint-all still ran' ($rn.All -gt 0) "all=$($rn.All)"

  $nf = New-Scenario 'nofacts' $noFacts
  $rf = Get-SchemaFindings $nf
  Check 'T4e repository without schema facts -> 0 schema findings' ($rf.Findings.Count -eq 0) "count=$($rf.Findings.Count)"
  Check 'T4f repository without schema facts -> no banner' (@($rf.Lines | Where-Object { $_ -match 'schema facts' }).Count -eq 0)

  # T5 exceptions
  $ex = New-Scenario 'except' $repoText
  $re = Get-SchemaFindings $ex
  $noteBound = @($re.Findings | Where-Object { $_.rule -eq 'schema-length-bound' -and $_.message -match 'ORDERS\.NOTE' })
  Check 'T5a exception removes the ORDERS.NOTE length-bound findings' ($noteBound.Count -eq 0) "count=$($noteBound.Count)"
  Check 'T5b DIMABBR / DIMNAME length-bound findings stay' (@($re.Findings | Where-Object { $_.rule -eq 'schema-length-bound' -and $_.message -match 'MSCLIST\.' }).Count -eq 2)
  Check 'T5c NOTE maxlen-drift findings stay (other rule)' (@($re.Findings | Where-Object { $_.rule -eq 'schema-maxlen-drift' -and $_.message -match 'ORDERS\.NOTE' }).Count -eq 2)

  # T8 a configured repository that is missing is SAID once, never silent; T9 stale positions
  $miss = New-Scenario 'missing' $noExc
  [IO.File]::Delete((Join-Path $miss.Dir 'schema.dlrepo'))
  $rm = Get-SchemaFindings $miss
  Check 'T8 configured but missing repository is named once' (($rm.Findings.Count -eq 0) -and (@($rm.Lines | Where-Object { $_ -match 'schema\.dlrepo not found' }).Count -eq 1)) "$(@($rm.Lines | Where-Object { $_ -match 'dlrepo' }) -join ' | ')"
  $stale = New-Scenario 'stale' $noExc
  $sf = Join-Path $stale.Dir 'uBounds.pas'
  [IO.File]::WriteAllText($sf, [IO.File]::ReadAllText($sf).Replace("pOrder.NOTE := '123456789012345678901'", "pOrder.FREE := '123456789012345678901'"), [Text.Encoding]::ASCII)
  $rs = Get-SchemaFindings $stale
  Check 'T9 a line edited since the index is not judged by its old position' ((@($rs.Findings | Where-Object { $_.message -match '21-character literal' }).Count -eq 0) -and ($rs.Findings.Count -gt 0)) "count=$($rs.Findings.Count)"

  # T6 lint <file>
  $one = Invoke-Engine @('lint', (Join-Path $base.Dir 'uBounds.pas'), '--db', $base.Db, '--project', $base.Proj, '--json')
  $oneJ = @((($one | Where-Object { $_ -notmatch '^drag-lint:' -and $_ -notmatch '^\(loaded' }) -join "`n") | ConvertFrom-Json | ForEach-Object { $_ })
  $oneS = @($oneJ | Where-Object { $_.rule -like 'schema-*' })
  Check 'T6a lint uBounds.pas reports its 2 schema findings' ($oneS.Count -eq 2) "count=$($oneS.Count)"
  Check 'T6b lint <file> prints the banner once' (@($one | Where-Object { $_ -match 'schema facts' }).Count -eq 1)
  # T10 notice channel: a configured-but-missing repository says ONE line on stderr, never on stdout (--json stays clean);
  # no fieldRepository configured stays fully silent (silent control).
  $sm = Invoke-EngineSplit @('lint', (Join-Path $miss.Dir 'uBounds.pas'), '--db', $miss.Db, '--project', $miss.Proj, '--json')
  $smErrLines = @(($sm.Err -split "`r?`n") | Where-Object { $_ -match 'dlrepo' })
  Check 'T10a missing repository: exactly one stderr line' ($smErrLines.Count -eq 1) "count=$($smErrLines.Count)"
  $smJsonOk = $true
  try { $null = $sm.Out | ConvertFrom-Json } catch { $smJsonOk = $false }
  Check 'T10b missing repository: stdout has no notice and parses as JSON' (($sm.Out -notmatch 'dlrepo') -and $smJsonOk) "out=$($sm.Out.Substring(0, [Math]::Min(80, $sm.Out.Length)))"
  $sa = Invoke-EngineSplit @('lint-all', '--db', $miss.Db, '--project', $miss.Proj, '--json')
  Check 'T10c lint-all missing repository: one stderr line, none on stdout' ((@(($sa.Err -split "`r?`n") | Where-Object { $_ -match 'dlrepo' }).Count -eq 1) -and ($sa.Out -notmatch 'dlrepo'))
  $sn = Invoke-EngineSplit @('lint', (Join-Path $none.Dir 'uBounds.pas'), '--db', $none.Db, '--project', $none.Proj, '--json')
  Check 'T10d no fieldRepository: no stderr notice at all (silent control)' ($sn.Err -notmatch 'dlrepo|schema facts|field repository') "err=$($sn.Err)"
  $snp = Invoke-EngineSplit @('lint', (Join-Path $base.Dir 'uBounds.pas'), '--db', $base.Db, '--project', $base.Proj, '--json')
  Check 'T10e positive control: present repository prints the banner on stderr only' (($snp.Err -match 'schema facts') -and ($snp.Out -notmatch 'schema facts'))
}
finally {
  if ($script:Failed -eq 0 -and (Test-Path $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}
Write-Host ""
Write-Host "run_lint_schema_rules: $script:Passed passed, $script:Failed failed" -ForegroundColor $(if ($script:Failed) { 'Red' } else { 'Green' })
exit $(if ($script:Failed) { 1 } else { 0 })
