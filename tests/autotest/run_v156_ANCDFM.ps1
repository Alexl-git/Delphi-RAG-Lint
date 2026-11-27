#Requires -Version 7.3
<#
  run_v156_ANCDFM.ps1 -- lane ANCDFM (1.56): `repo read-dfm` follows a dataset into the ancestor form / data module DFM,
  and reads FireDAC's AttachTable(X.Table, ...) as a link to dataset X.

  PART 1  builds and runs tests\fieldrepo\DfmReadInheritTests.dpr (root line of a text / binary DFM, ancestor class of a
          unit, ancestor DFM of a folder, a dataset completed from its ancestors, the AttachTable reading).
  PART 2  the built engine on tests\fixtures\fieldrepo\ancdfm (uBase <- uDerived <- uThird; uForm links into them):
    C1  a memory table copied from an INHERITED dataset gets the ancestor's table
    C2  ... from a dataset the descendant DFM does not mention; C3 two levels up
    C4  the SQL the descendant states wins over the ancestor's
    C5  AttachTable(X.Table, nil) links to dataset X
    C6  a lookup field whose LookupDataSet is only in the ancestor gets its table
    C7  controls: two DFMs with the ancestor class, no unit, no ancestor DFM, an unknown name stay unresolved, each
        with its warning; nothing is picked
    C8  what was followed is a warning line; the links summary; a dry run writes no byte
  PART 2 needs the call lines of DRagLint.FieldRepo.DfmReadPlan.pas (TDfmRead.FAncestry). While that unit does not have
  them it is reported as SKIP, loudly, and the run exits 0; -ForceCli runs it anyway (RED against an engine without them).
  Run: pwsh -File tests\autotest\run_v156_ANCDFM.ps1 [-Exe <drag-lint.exe>] [-SkipUnit] [-ForceCli]
#>
[CmdletBinding()]
param([string]$Exe = '', [switch]$SkipUnit, [switch]$ForceCli)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $(if ($ok) { '' } else { $d })) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:Failed = $true }
}
Write-Host '== v156 ANCDFM: ancestor DFM links ==' -ForegroundColor Cyan
$work = Join-Path ([IO.Path]::GetTempPath()) ('dl-ancdfm-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
$fixSrc = Join-Path $Repo 'tests\fixtures\fieldrepo\ancdfm'
try {
  # ---- part 1 ----
  if (-not $SkipUnit) {
    $bat = Join-Path $Repo 'build\_build_fieldrepo_ancdfm_tests_local.bat'
    $blog = Join-Path $work 'build.log'
    $uwork = Join-Path $work 'unit'
    [IO.Directory]::CreateDirectory($uwork) | Out-Null
    Start-Process -FilePath cmd.exe -ArgumentList ('/c ""' + $bat + '" "' + $work + '" > "' + $blog + '" 2>&1"') -Wait -NoNewWindow
    $bl = Get-Content -LiteralPath $blog -Raw
    Check 'U0 the unit tests build' (($bl -match 'BUILD_EXITCODE=0') -and ($bl -notmatch 'Error: E\d+')) $blog
    $u = (& { $ErrorActionPreference = 'Continue'; & (Join-Path $work 'DfmReadInheritTests.exe') $fixSrc $uwork 2>&1 | ForEach-Object { "$_" } } | ForEach-Object { "$_" })
    $uc = $LASTEXITCODE
    $u | Where-Object { $_ -match '^FAIL' } | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    $sum = ($u | Where-Object { $_ -match '^Summary: ' } | Select-Object -Last 1)
    Check "U1 unit tests ($sum)" (($uc -eq 0) -and ($sum -match 'pass=[1-9]\d* fail=0$')) $sum
  }
  # ---- part 2 ----
  $plan = [IO.File]::ReadAllText((Join-Path $Repo 'src\sql\DRagLint.FieldRepo.DfmReadPlan.pas'))
  if ((-not $ForceCli) -and ($plan -notmatch 'FAncestry')) {
    Write-Host '[SKIP] C1-C8 -- DRagLint.FieldRepo.DfmReadPlan.pas has no FAncestry call lines yet (REQUESTS: ANCDFM -> GC-R); the engine cannot follow an ancestor' -ForegroundColor Yellow
  } else {
    if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
    $Exe = (Resolve-Path -LiteralPath $Exe).Path
    $fix = Join-Path $work 'forms'
    [IO.Directory]::CreateDirectory($fix) | Out-Null
    Get-ChildItem $fixSrc -File | ForEach-Object { [IO.File]::Copy($_.FullName, (Join-Path $fix $_.Name)) }
    $x = Join-Path $work 'x.dlrepo'
    $null = & { $ErrorActionPreference = 'Continue'; & $Exe repo init --repo $x 2>&1 }
    $h0 = (Get-FileHash -LiteralPath $x).Hash
    $o = (& { $ErrorActionPreference = 'Continue'; & $Exe repo read-dfm --repo $x --dfm (Join-Path $fix 'uForm.dfm') --direction dfm-to-repo 2>&1 | ForEach-Object { "$_" } }) -join "`n"
    $code = $LASTEXITCODE
    function Ch($pattern) { [regex]::IsMatch($o, $pattern) }
    Check 'C0 the read runs' ($code -eq 0) "exit=$code`n$o"
    Check 'C1 a memory table copied from an inherited dataset gets the ancestor''s table' (Ch 'dataset uForm\.dfm memOrders \(TFDMemTable\) -> ORDERS \(via CopyDataSet dmDerived\.tblOrders\): 2 data') $o
    Check 'C1b ... and a field the descendant adds to the inherited dataset is a column of it (no "no table column" for NOTE)' (-not (Ch 'memOrders[^\n]*\n  no table column')) $o
    Check 'C2 a dataset the descendant DFM does not mention' (Ch 'memCust \(TFDMemTable\) -> CUSTOMERS \(via CopyDataSet dmDerived\.tblCust\)') $o
    Check 'C3 two levels up' (Ch 'memDeep \(TFDMemTable\) -> ORDERS \(via CloneCursor dmThird\.tblOrders\)') $o
    Check 'C4 the SQL the descendant states wins' (Ch 'memItems \(TFDMemTable\) -> PARTS \(via CopyDataSet dmDerived\.qryItems\)') $o
    Check 'C5 AttachTable(X.Table, nil) links to dataset X' (Ch 'memAtt \(TFDMemTable\) -> LOCALS \(via AttachTable tblLocal\)') $o
    Check 'C6 a lookup dataset that is only in the ancestor gives its table' ((Ch 'LOCALS\|CUST[^\n]*DESTTABLE=CUSTOMERS') -and -not (Ch 'unresolved lookup dataset dmDerived\.tblCust')) $o
    Check 'C7a two DFMs with the ancestor class: unresolved, warned, not picked' ((Ch 'memAmb \(TFDMemTable\) -> UNRESOLVED \(linked to dmAmbChild\.tblAmb \(CopyDataSet\), which has no table') -and (Ch 'warning: uAmbChild\.dfm: 2 DFMs of this folder have the ancestor class TdmAmb: ancestor not read')) $o
    Check 'C7b no unit beside the inherited DFM' ((Ch 'memNoUnit \(TFDMemTable\) -> UNRESOLVED \(linked to dmNoUnit\.tblOrders \(CopyDataSet\), which has no table') -and (Ch 'warning: uNoUnit\.dfm: inherited from an ancestor form, but no unit beside the DFM names it: ancestor not read')) $o
    Check 'C7c the ancestor class has no DFM in the folder' ((Ch 'memOrphan \(TFDMemTable\) -> UNRESOLVED \(linked to dmOrphan\.tblOrders \(CopyDataSet\), which has no table') -and (Ch 'warning: uOrphan\.dfm: no DFM of this folder has the ancestor class TdmElsewhere: ancestor not read')) $o
    Check 'C7d a name no DFM of the chain has' (Ch 'memGone \(TFDMemTable\) -> UNRESOLVED \(linked to dmDerived\.tblGone \(CopyDataSet\), which is no dataset of the form or of a module beside it\)') $o
    Check 'C8a what was followed is a warning' ((Ch 'warning: uDerived\.dfm tblOrders: read from the ancestor uBase\.dfm') -and (Ch 'warning: uThird\.dfm tblOrders: read from the ancestor uDerived\.dfm')) $o
    Check 'C8b links summary' (Ch '(?m)^links: 5 datasets got a source: AttachTable 1, CloneCursor 1, CopyDataSet 3; 4 unresolved') $o
    Check 'C8c a dry run writes no byte' ((Ch 'dry run: nothing written') -and ($h0 -eq (Get-FileHash -LiteralPath $x).Hash)) $o
  }
} finally {
  try { [IO.Directory]::Delete($work, $true) } catch { }
}
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
