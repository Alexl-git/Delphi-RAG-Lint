#Requires -Version 7.3
<#
  run_v156_FIX2B.ps1 -- 1.56 lane FIX2-B: four review findings of REV-2 (F3, F4, F5, F7) and one nit.
    F3 `repo read-dfm --db` on a schema-4 repository: no "no such column DERIVED_KIND"; one stated skip line
    F4 `repo gen-wiki` never overwrites a page it did not generate (first-line marker): the page is REFUSED by name
       (chosen over a .generated.md sidecar: a second file beside a hand-written one is clutter nobody reads)
    F5 `ask risk` with no imported coverage says so in the meta (Note) and the chart, not 0 % for everything
    F7 every github/bitbucket purl of rules\sbom-libraries.json is lowercase (purl spec)
    N  tests\fixtures\sbom\schema\README.txt line 1 names run_v156_SBOM1.ps1 (eaten backslashes)
  Positive controls: F3 beside the schema-5 read (the derived row is still proposed); F4 second run over its own
  generated pages (written 0, refused none); F5 after import-coverage (Note empty, real %); F7 negative
  control (an upper-case purl is flagged by the same predicate). A MISSING engine is a FAIL.
  Run: pwsh -File tests\autotest\run_v156_FIX2B.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param([string]$Exe = '')
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$ErrorActionPreference = 'Continue'
$script:Pass = 0
$script:Fail = 0
function Check($n, $ok, $d = '') {
  Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $(if ($ok) { '' } else { $d })) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if ($ok) { $script:Pass++ } else { $script:Fail++ }
}
Write-Host '== v156 FIX2-B: schema-4 lineage, wiki overwrite, risk without coverage, purls ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "V156 FIX2B: FAIL -- no engine at $Exe" -ForegroundColor Red; exit 1 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('dl-v156-fix2b-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($work) | Out-Null
function Run([string[]]$a) {
  $out = (& { $ErrorActionPreference = 'Continue'; & $Exe @a 2>&1 | ForEach-Object { "$_" } }) -join "`n"
  [pscustomobject]@{ Out = $out; Code = $LASTEXITCODE }
}
function JsonOf($text) { try { $text.Substring($text.IndexOf('{')) | ConvertFrom-Json | ForEach-Object { $_ } } catch { $null } }
try {
  # ---- F3 / F4 share the LIN-2 fixture ----
  $fx = Join-Path $work 'fx'
  [IO.Directory]::CreateDirectory($fx) | Out-Null
  foreach ($n in 'uLin2.pas', 'uLin2.dfm', 'lin2_schema.sql') { [IO.File]::Copy((Join-Path $Repo "tests\fixtures\v156\LIN2\$n"), (Join-Path $fx $n), $true) }
  $db = Join-Path $work 'idx.sqlite'
  $ix = Run @('index', $fx, '--db', $db)
  Check 'S0 the fixture copy indexes' (($ix.Code -eq 0) -and (Test-Path -LiteralPath $db)) $ix.Out
  $dfm = Join-Path $fx 'uLin2.dfm'
  $x5 = Join-Path $work 'v5.dlrepo'
  $null = Run @('repo', 'init', '--repo', $x5)
  $sd = Run @('repo', 'seed-fb', '--ddl', (Join-Path $fx 'lin2_schema.sql'), '--repo', $x5, '--apply')
  Check 'S1 the schema-5 repository seeds' ($sd.Code -eq 0) $sd.Out

  # F3: a schema-4 repository (restore of the XTABLE v4 backup) with the same index
  # the backup gets one PLAIN row ORDERS|TOTAL: the lineage reads DERIVED_KIND of an existing row, a column schema 4 lacks
  $b4 = [IO.File]::ReadAllText((Join-Path $Repo 'tests\fixtures\fieldrepo\xtable\xtable_v4.txt'))
  $row = "[DL_FIELDS_INFO ORDERS|TOTAL]`r`nVISIBLE=true`r`nTRIGGERED=false`r`nDISPLAY_WIDTH=0`r`nBG_COLOR=false`r`nFG_COLOR=false`r`nUNIQUE_FLAG=false`r`nFIELD_KIND=1`r`nPRIMARY_KEY=false`r`nCUSTOM_TYPE=false`r`nISCALCULATED=false`r`nISLOOKUP=false`r`nISENUM=false`r`nUI_TAG=0`r`n`r`n#end DL_FIELDS_INFO 9"
  $b4 = $b4.Replace('#end DL_FIELDS_INFO 8', $row)
  $b4File = Join-Path $work 'v4.txt'
  [IO.File]::WriteAllText($b4File, $b4, [Text.Encoding]::ASCII)
  $x4 = Join-Path $work 'v4.dlrepo'
  $rs = Run @('repo', 'restore', '--repo', $x4, '--in', $b4File)
  $r4 = Run @('repo', 'read-dfm', '--repo', $x4, '--dfm', $dfm, '--direction', 'dfm-to-repo', '--db', $db)
  Check 'F3a schema 4: restore ok, read-dfm exits 0, no "no such column", and no change reads the missing column (SQLite answers a double-quoted unknown column with its own name: old value "DERIVED_KIND")' (($rs.Code -eq 0) -and ($r4.Code -eq 0) -and ($r4.Out -cnotmatch 'no such column') -and ($r4.Out -cnotmatch 'DERIVED_KIND("|:)? -> ')) "$($rs.Out)`n$($r4.Out)"
  Check 'F3b schema 4: one stated skip line naming the schema and the way out, no derived row' (($r4.Out -match '(?m)^warning: lineage: skipped \(the repository is schema 4: derived fields need schema 5; run repo migrate --apply\)\r?$') -and ($r4.Out -cnotmatch 'derived\(')) $r4.Out
  $r5 = Run @('repo', 'read-dfm', '--repo', $x5, '--dfm', $dfm, '--direction', 'dfm-to-repo', '--db', $db)
  Check 'F3c control: schema 5, same index and DFM: the derived row is still proposed, no skip line' (($r5.Code -eq 0) -and ($r5.Out -match 'derived\(direct\)') -and ($r5.Out -cnotmatch 'the repository is schema')) $r5.Out

  # F4: gen-wiki
  $wiki = Join-Path $work 'wiki'
  $g1 = Run @('repo', 'gen-wiki', '--repo', $x5, '--out', $wiki, '--json')
  $j1 = JsonOf $g1.Out
  Check 'F4a first run writes pages, refuses none' (($g1.Code -eq 0) -and $j1 -and ($j1.written -gt 0) -and (-not $j1.refused)) $g1.Out
  $g2 = Run @('repo', 'gen-wiki', '--repo', $x5, '--out', $wiki, '--json')
  $j2 = JsonOf $g2.Out
  Check 'F4b control: a second run over its own pages rewrites nothing and refuses nothing' (($g2.Code -eq 0) -and $j2 -and ($j2.written -eq 0) -and (-not $j2.refused)) $g2.Out
  $victim = [string]@($j1.pages)[0]
  $vp = Join-Path $wiki $victim
  $hand = "My own notes about this table.`r`nDo not lose them.`r`n"
  [IO.File]::WriteAllText($vp, $hand, [Text.Encoding]::ASCII)
  $g3 = Run @('repo', 'gen-wiki', '--repo', $x5, '--out', $wiki, '--json')
  $j3 = JsonOf $g3.Out
  Check 'F4c a hand-written page of a generated name survives byte for byte' ([IO.File]::ReadAllText($vp) -ceq $hand) $g3.Out
  Check 'F4d the run names it as refused' (($g3.Code -eq 0) -and $j3 -and (@($j3.refused) -contains $victim)) $g3.Out
  $g4 = Run @('repo', 'gen-wiki', '--repo', $x5, '--out', $wiki)
  Check 'F4e text output says "refused page: <name>" and why' ($g4.Out -match ('(?m)^refused page: ' + [regex]::Escape($victim) + ' \(not written: ')) $g4.Out

  # F5: ask risk, no coverage, then with coverage
  $g51 = Join-Path $Repo 'tests\fixtures\g51'
  $rdb = Join-Path $work 'g51.sqlite'
  $rx = Run @('index', $g51, '--db', $rdb)
  $o1 = Join-Path $work 'risk1'
  $a1 = Run @('ask', 'risk', '--target', 'project', '--db', $rdb, '--plain', '--out-root', $o1)
  $m1 = Get-ChildItem $o1 -Recurse -Filter meta.json -ErrorAction SilentlyContinue | Select-Object -First 1
  $e1 = if ($m1) { (Get-Content -Raw $m1.FullName | ConvertFrom-Json | ForEach-Object { $_ }).emitter } else { $null }
  Check 'F5a no coverage: the meta says "no coverage imported -- complexity only"' (($rx.Code -eq 0) -and ($a1.Code -eq 0) -and $e1 -and ($e1.CoverageImported -eq $false) -and ($e1.Note -ceq 'no coverage imported -- complexity only')) "$($a1.Out)`n$($e1 | ConvertTo-Json -Compress)"
  $dot = Get-ChildItem $o1 -Recurse -Filter 'graph.dot' -ErrorAction SilentlyContinue | Select-Object -First 1
  $dt = if ($dot) { Get-Content -Raw $dot.FullName } else { '' }
  Check 'F5b no coverage: the chart carries the note and no node claims "coverage 0.0%"' (($dt -match 'no coverage imported -- complexity only') -and ($dt -cnotmatch 'coverage 0\.0%')) $dt
  $imp = Run @('import-coverage', '--file', (Join-Path $g51 'coverage.xml'), '--db', $rdb)
  $o2 = Join-Path $work 'risk2'
  $a2 = Run @('ask', 'risk', '--target', 'project', '--db', $rdb, '--plain', '--out-root', $o2)
  $m2 = Get-ChildItem $o2 -Recurse -Filter meta.json -ErrorAction SilentlyContinue | Select-Object -First 1
  $e2 = if ($m2) { (Get-Content -Raw $m2.FullName | ConvertFrom-Json | ForEach-Object { $_ }).emitter } else { $null }
  $dot2 = Get-ChildItem $o2 -Recurse -Filter 'graph.dot' -ErrorAction SilentlyContinue | Select-Object -First 1
  $dt2 = if ($dot2) { Get-Content -Raw $dot2.FullName } else { '' }
  Check 'F5c control: with coverage imported there is no note and real percentages are drawn' (($imp.Code -eq 0) -and $e2 -and ($e2.CoverageImported -eq $true) -and ([string]$e2.Note -ceq '') -and ($dt2 -cnotmatch 'no coverage imported') -and ($dt2 -match 'coverage \d')) "$($imp.Out)`n$dt2"

  # F7: purls
  $cat = Get-Content -Raw -LiteralPath (Join-Path $Repo 'rules\sbom-libraries.json') | ConvertFrom-Json | ForEach-Object { $_ }
  $purls = @($cat.PSObject.Properties.Value | ForEach-Object { $_ } | ForEach-Object { $_.purl } | Where-Object { $_ })
  $bad = { param($p) $p -cmatch '^pkg:(github|bitbucket)/' -and $p -cne $p.ToLowerInvariant() }
  Check 'F7a every github/bitbucket purl is lowercase' (($purls.Count -gt 0) -and (@($purls | Where-Object { & $bad $_ }).Count -eq 0)) (($purls | Where-Object { & $bad $_ }) -join ' ')
  Check 'F7b control: the predicate flags an upper-case purl' (& $bad 'pkg:github/IndySockets/Indy')
  # nit
  $l1 = ([IO.File]::ReadAllText((Join-Path $Repo 'tests\fixtures\sbom\schema\README.txt')) -split "`n")[0].TrimEnd("`r")
  Check 'N1 README line 1 names tests\autotest\run_v156_SBOM1.ps1 and has no control character' ($l1 -ceq 'CycloneDX 1.6 JSON schema, vendored unchanged for tests\autotest\run_v156_SBOM1.ps1.') $l1
}
finally {
  try { [IO.Directory]::Delete($work, $true) } catch { }
}
Write-Host ("run_v156_FIX2B: {0} passed, {1} failed" -f $script:Pass, $script:Fail)
if ($script:Fail) { exit 1 } else { exit 0 }