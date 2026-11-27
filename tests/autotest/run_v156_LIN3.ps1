#Requires -Version 7.3
<#
  run_v156_LIN3.ps1 -- 1.56 lane LIN-3: the follow-ups of LIN-2.
    G  design 2.8 guard: a derived row (DERIVED_KIND set) is not plain table data: read-dfm --json tableFields does
       not list it; write-dfm refuses it on purpose (the reason says "derived"), not for a missing FIELD_TYPE
    R  the planner extension proposes the DL_RELATIONS row of a path (AddRelationChange): D1 now proposes the relation
       and the input UNCHECKED instead of a warning; the three rows apply together, repo check is clean
    Q  `lineage: skipped (no index)` only when a dataset has a field the lineage could mark (control: it still
       prints for the LIN-2 form); not in the --json warnings of a read with nothing to look at
    S  --dfm with forward slashes names the DFM by its file name only
  Positive controls: G1 beside G0 (QTY listed); R after the same read printed the warning; Q2 beside Q1; S control
  with backslashes. A MISSING engine is a FAIL. Run: pwsh -File tests\autotest\run_v156_LIN3.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param([string]$Exe = '', [switch]$KeepScratch)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$ErrorActionPreference = 'Continue'
$script:Pass = 0
$script:Fail = 0
function Check($n, $ok, $d = '') {
  Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $(if ($ok) { '' } else { $d })) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if ($ok) { $script:Pass++ } else { $script:Fail++ }
}
Write-Host '== v156 LIN-3: derived guard, planned relations, quiet lineage, slashes ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "V156 LIN3: FAIL -- no engine at $Exe" -ForegroundColor Red; exit 1 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('dl-v156-lin3-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($work) | Out-Null
function Run([string[]]$a) {
  $out = (& { $ErrorActionPreference = 'Continue'; & $Exe @a 2>&1 | ForEach-Object { "$_" } }) -join "`n"
  [pscustomobject]@{ Out = $out; Code = $LASTEXITCODE }
}
function NewRepo($path, $ddl) {
  $null = Run @('repo', 'init', '--repo', $path)
  Run @('repo', 'seed-fb', '--ddl', $ddl, '--repo', $path, '--apply')
}
function ReadDfm($repoFile, $dfm, [string[]]$more = @()) {
  Run (@('repo', 'read-dfm', '--repo', $repoFile, '--dfm', $dfm, '--direction', 'dfm-to-repo') + $more)
}
function Has($text, $pattern) { [regex]::IsMatch($text, $pattern) }
function FindProp($node, $name) {
  if ($null -eq $node) { return }
  if ($node -is [System.Array]) { foreach ($i in $node) { FindProp $i $name }; return }
  if ($node -is [pscustomobject]) {
    foreach ($p in $node.PSObject.Properties) {
      if ($p.Name -eq $name) { $p.Value } else { FindProp $p.Value $name }
    }
  }
}
function Ids($text, $pattern) { @([regex]::Matches($text, $pattern) | ForEach-Object { $_.Groups[1].Value }) }
try {
  $fixSrc = Join-Path $Repo 'tests\fixtures\v156\LIN2'
  $fx3 = Join-Path $Repo 'tests\fixtures\v156\LIN3'
  $fx = Join-Path $work 'fx'
  [IO.Directory]::CreateDirectory($fx) | Out-Null
  foreach ($n in 'uLin2.pas', 'uLin2.dfm', 'uLin2b.pas', 'uLin2b.dfm', 'lin2_schema.sql') { [IO.File]::Copy((Join-Path $fixSrc $n), (Join-Path $fx $n), $true) }
  [IO.File]::Copy((Join-Path $fx3 'uPlain.dfm'), (Join-Path $fx 'uPlain.dfm'), $true)
  $ddl = Join-Path $fx 'lin2_schema.sql'
  $db = Join-Path $work 'idx.sqlite'
  $ix = Run @('index', $fx, '--db', $db)
  Check 'S0 the fixture copy indexes' (($ix.Code -eq 0) -and (Test-Path -LiteralPath $db)) $ix.Out
  $dfm = Join-Path $fx 'uLin2.dfm'
  $dfmB = Join-Path $fx 'uLin2b.dfm'
  $plain = Join-Path $fx 'uPlain.dfm'
  $withDb = @('--db', $db)

  # ---- G: the guard ----
  $x = Join-Path $work 'x.dlrepo'
  $null = NewRepo $x $ddl
  $null = ReadDfm $x $dfm ($withDb + '--apply')
  $a = ReadDfm $x $dfm $withDb
  $ids = Ids $a.Out '(?m)^\[(\d+)\] insert (?:DL_FIELDS_INFO ORDERS\|(?:TOTAL|NET|SUMQ)|DL_FIELD_INPUTS ORDERS\|TOTAL\|\|CUSTOMERS):'
  $sel = Join-Path $work 'sel.txt'
  [IO.File]::WriteAllLines($sel, [string[]]$ids)
  $b = ReadDfm $x $dfm ($withDb + @('--select', $sel))
  Check 'G-S the derived rows are stored (setup)' (($ids.Count -eq 4) -and (Has $b.Out '(?m)^applied: 4 changes')) $b.Out
  $j = ReadDfm $x $dfm ($withDb + @('--json', '--dataset', 'tblOrders'))
  $jo = $null; try { $jo = $j.Out.Substring($j.Out.IndexOf('{')) | ConvertFrom-Json } catch { }
  $tf = @(FindProp $jo 'tableFields' | ForEach-Object { $_ } | ForEach-Object { $_.field })
  Check 'G0 control: tableFields lists the plain columns of ORDERS' (($tf -contains 'QTY') -and ($tf -contains 'PRICE')) ($tf -join ',')
  Check 'G1 tableFields does NOT list a derived row (TOTAL, NET, SUMQ)' (($tf.Count -gt 0) -and -not ($tf -contains 'TOTAL') -and -not ($tf -contains 'NET') -and -not ($tf -contains 'SUMQ')) ($tf -join ',')
  $w = Run @('repo', 'write-dfm', '--repo', $x, '--dfm', $dfmB, '--direction', 'repo-to-dfm', '--dataset', 'tblOrders', '--names', 'NET')
  Check 'G2 write-dfm refuses a derived row on purpose: the reason names it as derived' (($w.Code -eq 0) -and (Has $w.Out '(?m)^\[\d+\] insert uLin2b\.dfm tblOrdersNET:[^\n]*\r?\n  BLOCKED: [^\n]*derived')) $w.Out

  # ---- R: planned relations ----
  $z = Join-Path $work 'z.dlrepo'
  $null = NewRepo $z $ddl
  $d = ReadDfm $z $dfmB $withDb
  Check 'R1 relation neither stored nor planned: the extension proposes the DL_RELATIONS row, UNCHECKED' (Has $d.Out '(?m)^\[\d+\] insert DL_RELATIONS FK_ORDERS_CUST:[^\n]*ORDERS > CUSTOMERS[^\n]*\r?\n  \(unchecked\)') $d.Out
  Check 'R2 and the input row, UNCHECKED, with no "neither stored" warning' ((Has $d.Out '(?m)^\[\d+\] insert DL_FIELD_INPUTS ORDERS\|REBATE\|\|CUSTOMERS:[^\n]*PATH=FK_ORDERS_CUST[^\n]*\r?\n  \(unchecked\)') -and -not (Has $d.Out 'neither stored')) $d.Out
  $rids = Ids $d.Out '(?m)^\[(\d+)\] insert (?:DL_FIELDS_INFO ORDERS\|REBATE|DL_RELATIONS FK_ORDERS_CUST|DL_FIELD_INPUTS ORDERS\|REBATE\|\|CUSTOMERS):'
  $sel2 = Join-Path $work 'sel2.txt'
  [IO.File]::WriteAllLines($sel2, [string[]]$rids)
  $ap = ReadDfm $z $dfmB ($withDb + @('--select', $sel2))
  $c = Run @('repo', 'check', '--repo', $z)
  Check 'R3 --select of the field, the relation and the input applies; repo check is clean' (($rids.Count -eq 3) -and (Has $ap.Out '(?m)^applied: 3 changes') -and ($c.Code -eq 0) -and ($c.Out -match 'check: clean')) "$($ap.Out)`n$($c.Out)"
  $d3 = ReadDfm $z $dfmB $withDb
  Check 'R4 a second read plans nothing for REBATE (fixpoint)' (-not (Has $d3.Out 'ORDERS\|REBATE')) $d3.Out

  # ---- Q: the no-index line ----
  $q1 = ReadDfm $x $plain
  Check 'Q1 no --db and nothing the lineage could mark: no lineage line' (($q1.Code -eq 0) -and -not (Has $q1.Out 'lineage')) $q1.Out
  $q1j = ReadDfm $x $plain @('--json')
  Check 'Q1j the --json warnings carry no lineage line either' (($q1j.Code -eq 0) -and -not (Has $q1j.Out 'lineage')) $q1j.Out
  $q2 = ReadDfm $x $dfmB
  Check 'Q2 control: a form with a field the lineage could mark still gets the one line' (Has $q2.Out '(?m)^warning: lineage: skipped \(no index\)\r?$') $q2.Out

  # ---- S: forward slashes ----
  $fwd = $dfm.Replace('\', '/')
  $s1 = ReadDfm $x $fwd
  $s2 = ReadDfm $x $dfm
  Check 'S1 --dfm with forward slashes prints the DFM file name only, as with backslashes' ((-not (Has $s1.Out '/uLin2\.dfm')) -and (-not (Has $s2.Out '[\\/]uLin2\.dfm')) -and (Has $s1.Out 'dataset uLin2\.dfm tblOrders')) $s1.Out
}
catch {
  Check 'X0 the runner ran to its end' $false ("$_")
}
finally {
  if (-not $KeepScratch) { try { [IO.Directory]::Delete($work, $true) } catch { } }
}
Write-Host ("Summary: pass={0} fail={1}" -f $script:Pass, $script:Fail)
if (($script:Fail -gt 0) -or ($script:Pass -eq 0)) { Write-Host 'V156 LIN3: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'V156 LIN3: PASS' -ForegroundColor Green
exit 0
