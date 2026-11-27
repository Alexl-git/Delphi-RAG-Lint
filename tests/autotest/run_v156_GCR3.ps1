#Requires -Version 7.3
<#
  run_v156_GCR3.ps1 -- lane GCR-3 (1.56): `repo read-dfm` finds modules and ancestors through the project's search path and
  reads an inherited component's code from the ancestor's unit.

    S1  a module whose DFM lies in a DCC_UnitSearchPath folder OUTSIDE the project tree gives a memory table its table
    S2  a lookup into that module gets its table
    S3  two candidates (project tree + search path) = a warning, nothing picked
    S4  control: an entry with a $(Macro) is skipped (its module stays unresolved)
    A1  an `inherited` module whose ancestor DFM is in another folder is read through the ancestor (table + fields)
    A2  the calc body and the event handlers come from the ancestor's unit
    L1  a link statement (CopyDataSet) in the ANCESTOR's unit gives the inherited memory table its table
    D1  a dry run writes no byte
  Positive control: S1 / A1 / L1 on an engine built from the base (e3b88617a) are RED.
  Run: pwsh -File tests\autotest\run_v156_GCR3.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param([string]$Exe = '')
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$ErrorActionPreference = 'Continue'
$script:Failed = $false
$script:Pass = 0
$script:Fail = 0
function Check($n, $ok, $d = '') {
  Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $(if ($ok) { '' } else { $d })) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if ($ok) { $script:Pass++ } else { $script:Fail++; $script:Failed = $true }
}
function CopyTree($from, $to) {
  [IO.Directory]::CreateDirectory($to) | Out-Null
  Get-ChildItem -LiteralPath $from -File | ForEach-Object { [IO.File]::Copy($_.FullName, (Join-Path $to $_.Name), $true) }
  Get-ChildItem -LiteralPath $from -Directory | ForEach-Object { CopyTree $_.FullName (Join-Path $to $_.Name) }
}
Write-Host '== v156 GCR-3: search path, ancestor in another folder, inherited code ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('dl-gcr3-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
try {
  $fx = Join-Path $work 'fx'
  CopyTree (Join-Path $Repo 'tests\fixtures\v156\GCR3') $fx
  $common = Join-Path $fx 'common'
  # the project file is written here: its search path needs an absolute folder outside the project tree
  $dproj = '<Project><PropertyGroup Condition="''$(Base)''!=''''"><DCC_UnitSearchPath>' + $common + ';$(DCC_UnitSearchPath);$(MacroRoot)\macrodir</DCC_UnitSearchPath></PropertyGroup></Project>'
  [IO.File]::WriteAllText((Join-Path $fx 'app\App.dproj'), $dproj)
  $x = Join-Path $work 'x.dlrepo'
  $null = & { $ErrorActionPreference = 'Continue'; & $Exe repo init --repo $x 2>&1 }
  $h0 = (Get-FileHash -LiteralPath $x).Hash
  function ReadDfm($file) {
    $script:o = (& { $ErrorActionPreference = 'Continue'; & $Exe repo read-dfm --repo $x --dfm $file --direction dfm-to-repo 2>&1 | ForEach-Object { "$_" } }) -join "`n"
    $script:code = $LASTEXITCODE
  }
  function Ch($pattern) { [regex]::IsMatch($script:o, $pattern) }

  ReadDfm (Join-Path $fx 'app\uForm.dfm')
  Check 'S0 the read runs' ($code -eq 0) "exit=$code`n$o"
  Check 'S1 a memory table copied from a module of a search-path folder gets its table' (Ch 'dataset uForm\.dfm memOrders \(TFDMemTable\) -> ORDERS \(via CopyDataSet dmMod\.tblOrders\): 2 data') $o
  Check 'S2 a lookup into that module gets its table' ((Ch 'LOCALS\|CUST[^\n]*DESTTABLE=CUSTOMERS') -and -not (Ch 'unresolved lookup dataset dmMod\.tblCust')) $o
  Check 'S3 two candidates: unresolved, warned, not picked' ((Ch 'memTwo \(TFDMemTable\) -> UNRESOLVED') -and (Ch 'warning: uForm\.dfm: 2 DFMs of the used unit uTwo have the root dmTwo \(dm\\uTwo\.dfm, \.\.\\common\\uTwo\.dfm\): module not read')) $o
  Check 'S4 an entry with a macro is skipped' (Ch 'memMacro \(TFDMemTable\) -> UNRESOLVED') $o

  ReadDfm (Join-Path $fx 'app\inh\uDerived.dfm')
  Check 'A0 the read runs' ($code -eq 0) "exit=$code`n$o"
  Check 'A1 an inherited module whose ancestor is in another folder has the ancestor''s table and fields' (Ch 'dataset uDerived\.dfm tblOrders \(TFDTable\) -> ORDERS: 4 data, 1 calc') $o
  Check 'A2 the calc body comes from the ancestor''s unit' ((Ch '(?m)^calc bodies: 1 read, 0 blocked, 0 none') -and (Ch 'ORDERS\|TOTAL[^\n]*\{\{QTY\}\}\.AsInteger \* \{\{PRICE\}\}\.AsFloat') -and (Ch 'ORDERS\|QTY[^\n]*pcs')) $o
  Check 'L1 a link in the ancestor''s unit gives the inherited memory table its table' (Ch 'dataset uDerived\.dfm memCopy \(TFDMemTable\) -> CUSTOMERS \(via CopyDataSet tblCust\): 1 data') $o
  Check 'D1 a dry run writes no byte' ((Ch 'dry run: nothing written') -and ($h0 -eq (Get-FileHash -LiteralPath $x).Hash)) $o
  # ---- item 4: write-dfm leaves a derived field alone ----
  $fixLin = Join-Path $Repo 'tests\fixtures\v156\LIN2'
  $dx = Join-Path $work 'der'
  [IO.Directory]::CreateDirectory($dx) | Out-Null
  foreach ($n in 'uLin2.pas', 'uLin2.dfm', 'lin2_schema.sql') { [IO.File]::Copy((Join-Path $fixLin $n), (Join-Path $dx $n), $true) }
  foreach ($n in 'uDer.pas', 'uDer.dfm') { [IO.File]::Copy((Join-Path $Repo "tests\fixtures\v156\GCR3\der\$n"), (Join-Path $dx $n), $true) }
  $idx = Join-Path $work 'der.sqlite'
  $dr = Join-Path $work 'der.dlrepo'
  function Dl([string[]]$a) { (& { $ErrorActionPreference = 'Continue'; & $Exe @a 2>&1 | ForEach-Object { "$_" } }) -join "`n" }
  $null = Dl @('index', $dx, '--db', $idx)
  $null = Dl @('repo', 'init', '--repo', $dr)
  $null = Dl @('repo', 'seed-fb', '--ddl', (Join-Path $dx 'lin2_schema.sql'), '--repo', $dr, '--apply')
  $lin = Dl @('repo', 'read-dfm', '--repo', $dr, '--dfm', (Join-Path $dx 'uLin2.dfm'), '--direction', 'dfm-to-repo', '--db', $idx)
  $tid = @([regex]::Matches($lin, '(?m)^\[(\d+)\] insert DL_FIELDS_INFO ORDERS\|TOTAL:') | ForEach-Object { $_.Groups[1].Value })
  $selF = Join-Path $work 'der-sel.txt'
  [IO.File]::WriteAllLines($selF, [string[]]$tid)
  $st = Dl @('repo', 'read-dfm', '--repo', $dr, '--dfm', (Join-Path $dx 'uLin2.dfm'), '--direction', 'dfm-to-repo', '--db', $idx, '--select', $selF)
  Check 'W0 the derived row ORDERS|TOTAL is stored (setup)' (($tid.Count -eq 1) -and ($st -match 'applied: 1 changes')) $st
  $wr = Dl @('repo', 'write-dfm', '--repo', $dr, '--dfm', (Join-Path $dx 'uDer.dfm'), '--direction', 'repo-to-dfm', '--dataset', 'tblOrders', '--names', 'QTY')
  Check 'W1 control: a plain field the selection leaves out is proposed for removal (PRICE)' ($wr -match '(?m)^\[\d+\] delete uDer\.dfm tblOrdersPRICE') $wr
  Check 'W2 a derived field the selection leaves out is NOT proposed for removal (TOTAL)' ($wr -notmatch 'delete uDer\.dfm tblOrdersTOTAL') $wr
} finally {
  try { [IO.Directory]::Delete($work, $true) } catch { }
}
Write-Host ("Summary: pass={0} fail={1}" -f $script:Pass, $script:Fail)
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0