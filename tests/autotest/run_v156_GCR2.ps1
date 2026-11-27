#Requires -Version 7.3
<#
  run_v156_GCR2.ps1 -- lane GCR-2 (1.56): `repo read-dfm` finds a module in ANOTHER folder, reads the datasets of an
  inherited module through its ancestor DFM, and shares its dataset -> table resolver with the index (one resolver, two
  callers); the planner has the extension point lane LIN-2 registers into.

  PART 1  builds and runs tests\fieldrepo\DfmReadGcr2Tests.dpr: the exports (IsDatasetClass, IsPersistentFieldClass,
          DfmFieldKind, SourceOf, FieldSource), the module finder (NewDfmrModuleFinder) and the planner extension
          (RegisterDfmrPlanExtension: called once, adds a change, the change is applied; nil = not called).
  PART 2  the built engine on tests\fixtures\v156\GCR2:
    X1  a memory table copied from a module of a SUBFOLDER gets its table (uForm.dfm -> dm\uMod.dfm)
    X2  a lookup into that module gets its table
    X3  a form one folder BELOW the project file finds the module in a sibling folder (sub\uSub.dfm -> dm\uMod.dfm)
    X4  controls, nothing picked: two DFMs of the used unit (warning), a module whose unit the form does not use, a used
        unit without a DFM; a folder whose name starts with `__` is not searched; without a project file above it a
        form does not look into a sibling folder
    I1  an `inherited` dataset of an inherited module has the ancestor's table and fields (RED: "inherited: its own
        properties are in the ancestor's DFM")
    I2  the SQL the descendant states wins; I3 the calc body comes from the ANCESTOR's unit; I4 the events of an
        ancestor's field from the ancestor's unit, of an own field from the own unit
    I5  controls: an own dataset is read as before; an inherited module without an ancestor stays unresolved
    D1  a dry run writes no byte
  PART 3  one resolver, two callers: DRagLint.Index.RepoCopy.pas has no copy of the dataset class list and calls
          SourceOf / FieldSource; tests\autotest\run_v156_CONI.ps1 (I7 included) passes on the same engine.
  Positive control: X1 / I1 on an engine built from the base (730f15b0a + ANCDFM + CON-Q) are RED.
  Run: pwsh -File tests\autotest\run_v156_GCR2.ps1 [-Exe <drag-lint.exe>] [-SkipUnit] [-SkipConi]
#>
[CmdletBinding()]
param([string]$Exe = '', [switch]$SkipUnit, [switch]$SkipConi)
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
Write-Host '== v156 GCR-2: module in another folder, inherited module datasets, one resolver ==' -ForegroundColor Cyan
$work = Join-Path ([IO.Path]::GetTempPath()) ('dl-gcr2-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
$fixSrc = Join-Path $Repo 'tests\fixtures\v156\GCR2'
try {
  # ---- part 1 ----
  if (-not $SkipUnit) {
    $bat = Join-Path $Repo 'build\_build_fieldrepo_gcr2_tests_local.bat'
    $blog = Join-Path $work 'build.log'
    $uwork = Join-Path $work 'unit'
    [IO.Directory]::CreateDirectory($uwork) | Out-Null
    Start-Process -FilePath cmd.exe -ArgumentList ('/c ""' + $bat + '" "' + $work + '" > "' + $blog + '" 2>&1"') -Wait -NoNewWindow
    $bl = Get-Content -LiteralPath $blog -Raw
    Check 'U0 the unit tests build' (($bl -match 'BUILD_EXITCODE=0') -and ($bl -notmatch 'Error: E\d+')) (($bl -split "`n" | Where-Object { $_ -match 'Error|Fatal' } | Select-Object -First 5) -join ' | ')
    $utest = Join-Path $work 'DfmReadGcr2Tests.exe'
    if (Test-Path -LiteralPath $utest) {
      $u = (& { $ErrorActionPreference = 'Continue'; & $utest $fixSrc $uwork 2>&1 | ForEach-Object { "$_" } } | ForEach-Object { "$_" })
      $uc = $LASTEXITCODE
      $u | Where-Object { $_ -match '^FAIL' } | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
      $sum = ($u | Where-Object { $_ -match '^Summary: ' } | Select-Object -Last 1)
      Check "U1 unit tests ($sum)" (($uc -eq 0) -and ($sum -match 'pass=[1-9]\d* fail=0$')) $sum
    } else {
      Check 'U1 unit tests' $false 'no test exe'
    }
  }
  # ---- part 2 ----
  if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
  $Exe = (Resolve-Path -LiteralPath $Exe).Path
  $fix = Join-Path $work 'app'
  CopyTree $fixSrc $fix
  $x = Join-Path $work 'x.dlrepo'
  $null = & { $ErrorActionPreference = 'Continue'; & $Exe repo init --repo $x 2>&1 }
  $h0 = (Get-FileHash -LiteralPath $x).Hash
  function ReadDfm($file) {
    $script:o = (& { $ErrorActionPreference = 'Continue'; & $Exe repo read-dfm --repo $x --dfm $file --direction dfm-to-repo 2>&1 | ForEach-Object { "$_" } }) -join "`n"
    $script:code = $LASTEXITCODE
  }
  function Ch($pattern) { [regex]::IsMatch($script:o, $pattern) }

  ReadDfm (Join-Path $fix 'uForm.dfm')
  Check 'X0 the read runs' ($code -eq 0) "exit=$code`n$o"
  Check 'X1 a memory table copied from a module of a subfolder gets its table' (Ch 'dataset uForm\.dfm memOrders \(TFDMemTable\) -> ORDERS \(via CopyDataSet dmMod\.tblOrders\): 2 data') $o
  Check 'X2 a lookup into the module of the subfolder gets its table' ((Ch 'LOCALS\|CUST[^\n]*DESTTABLE=CUSTOMERS') -and -not (Ch 'unresolved lookup dataset dmMod\.tblCust')) $o
  Check 'X4a two DFMs of the used unit: unresolved, warned, not picked' ((Ch 'memTwin \(TFDMemTable\) -> UNRESOLVED \(linked to dmTwin\.tblTwin \(CopyDataSet\), which is no dataset of the form or of a module beside it\)') -and (Ch 'warning: uForm\.dfm: 2 DFMs of the used unit uTwin have the root dmTwin \(dm\\uTwin\.dfm, dm2\\uTwin\.dfm\): module not read')) $o
  Check 'X4b a module whose unit the form does not use is not looked for' (Ch 'memGhost \(TFDMemTable\) -> UNRESOLVED \(linked to dmGhost\.tblGhost \(CopyDataSet\), which is no dataset of the form or of a module beside it\)') $o
  Check 'X4c a used unit without a DFM' (Ch 'memGone \(TFDMemTable\) -> UNRESOLVED \(linked to dmGone\.tblGone \(CopyDataSet\), which is no dataset of the form or of a module beside it\)') $o
  Check 'X4d a folder whose name starts with __ is not searched (no second dmMod)' (-not (Ch '__backup')) $o
  Check 'X5 links summary' (Ch '(?m)^links: 1 datasets got a source: CopyDataSet 1; 3 unresolved') $o

  ReadDfm (Join-Path $fix 'sub\uSub.dfm')
  Check 'X3 a form below the project file finds the module in a sibling folder' (Ch 'dataset uSub\.dfm memCust \(TFDMemTable\) -> CUSTOMERS \(via CopyDataSet dmMod\.tblCust\): 1 data') $o

  $bare = Join-Path $work 'bare'
  CopyTree $fixSrc $bare
  [IO.File]::Delete((Join-Path $bare 'App.dpr'))
  ReadDfm (Join-Path $bare 'sub\uSub.dfm')
  Check 'X4e without a project file above it a form does not look into a sibling folder' (Ch 'memCust \(TFDMemTable\) -> UNRESOLVED \(linked to dmMod\.tblCust \(CopyDataSet\), which is no dataset of the form or of a module beside it\)') $o
  ReadDfm (Join-Path $bare 'uForm.dfm')
  Check 'X4f ... but it does look into its own subfolders' (Ch 'memOrders \(TFDMemTable\) -> ORDERS \(via CopyDataSet dmMod\.tblOrders\)') $o

  ReadDfm (Join-Path $fix 'inh\uDerived.dfm')
  Check 'I0 the read runs' ($code -eq 0) "exit=$code`n$o"
  Check 'I1 an inherited dataset has the ancestor''s table and fields' (Ch 'dataset uDerived\.dfm tblOrders \(TFDTable\) -> ORDERS: 4 data, 1 calc') $o
  Check 'I1b ... and no "its own properties are in the ancestor''s DFM" for it' (-not (Ch 'tblOrders[^\n]*its own properties are in the ancestor')) $o
  Check 'I2 the SQL the descendant states wins' (Ch 'dataset uDerived\.dfm qryItems \(TFDQuery\) -> PARTS: 2 data') $o
  Check 'I3 the calc body comes from the ancestor''s unit' ((Ch '(?m)^calc bodies: 1 read, 0 blocked, 0 none') -and (Ch 'ORDERS\|TOTAL[^\n]*\{\{QTY\}\}\.AsInteger \* \{\{PRICE\}\}\.AsFloat')) $o
  Check 'I4a the event of an ancestor''s field is read from the ancestor''s unit' (Ch 'ORDERS\|QTY[^\n]*pcs') $o
  Check 'I4b the event of an own field is read from the own unit' (Ch 'ORDERS\|NOTE[^\n]*UpperCase') $o
  Check 'I4c no handler is reported missing' (-not (Ch 'does not assign it|not read: ')) $o
  Check 'I5a an own dataset of the inherited module is read as before' (Ch 'dataset uDerived\.dfm tblOwn \(TFDTable\) -> OWNED: 1 data') $o
  Check 'I6 what was followed is a warning' (Ch 'warning: uDerived\.dfm tblOrders: read from the ancestor uBase\.dfm') $o

  ReadDfm (Join-Path $fix 'orph\uOrphan.dfm')
  Check 'I5b an inherited module without an ancestor stays unresolved, with the reason' (Ch 'dataset uOrphan\.dfm tblOrders \(TFDTable\) -> UNRESOLVED \(no TableName and no SQL in the DFM \(inherited: its own properties are in the ancestor''s DFM\)\)') $o
  Check 'D1 a dry run writes no byte' ((Ch 'dry run: nothing written') -and ($h0 -eq (Get-FileHash -LiteralPath $x).Hash)) $o

  # ---- part 3 ----
  $copy = [IO.File]::ReadAllText((Join-Path $Repo 'src\index\DRagLint.Index.RepoCopy.pas'))
  Check 'S1 the index has no dataset class list of its own' ($copy -notmatch 'DATASET_CLASSES\s*:\s*array') ''
  Check 'S2 the index resolves through SourceOf and FieldSource of read-dfm' (($copy -match '\bSourceOf\(') -and ($copy -match '\bFieldSource\(') -and ($copy -notmatch 'SqlFieldColumn\(')) ''
  if (-not $SkipConi) {
    $c = (& { $ErrorActionPreference = 'Continue'; & pwsh -NoProfile -File (Join-Path $Repo 'tests\autotest\run_v156_CONI.ps1') -Exe $Exe 2>&1 | ForEach-Object { "$_" } })
    $cc = $LASTEXITCODE
    $i7 = @($c | Where-Object { $_ -match '^\[PASS\] I7 ' }).Count
    $cf = @($c | Where-Object { $_ -match '^\[FAIL\]' })
    Check "S3 run_v156_CONI.ps1 passes, I7 included (exit=$cc, fails=$($cf.Count))" (($cc -eq 0) -and ($i7 -eq 1) -and ($cf.Count -eq 0)) (($cf | Select-Object -First 3) -join ' | ')
  }
} finally {
  try { [IO.Directory]::Delete($work, $true) } catch { }
}
Write-Host ("Summary: pass={0} fail={1}" -f $script:Pass, $script:Fail)
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
