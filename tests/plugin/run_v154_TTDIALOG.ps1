#Requires -Version 7.3
<#
  run_v154_TTDIALOG.ps1 -- TT-DIALOG (1.54): the field dialogs of the IDE plugin (read a form into the repository, select
  the fields of a dataset).

  M  builds and runs tests\plugin\fieldselect\FieldSelectTests.dpr: the VCL-free model (pinned case count)
  F  builds and runs FieldSelectForms.dpr: the forms, off screen and without the focus, at 100 % and 200 %
  E  the model on what the BUILT ENGINE prints (tests\fixtures\fieldrepo\dialog):
     E1 read-dfm --json --dataset holds the persistent fields and the repository's fields; without --dataset neither
     E2 the rows of the dialog; E3 clicks -> --names; E4 the --select file of a read is accepted, exactly its change is written
     E5 write-dfm: plan line and ids of the dialog are accepted, the form gets exactly the checked changes; E6 a stale file is refused
     (E5, E6 need `repo write-dfm`; an engine without it SKIPS them, -RequireWrite makes that a failure)
  R  registry entry and wiki page: the three FULL ide-menu paths
  S  source anchors of the IDE unit (not buildable without ToolsAPI): the dialogs are themed, a dirty form is not written

  Usage: pwsh -File tests\plugin\run_v154_TTDIALOG.ps1 [-Exe <drag-lint.exe>] [-RequireWrite] [-SkipForms]
#>
[CmdletBinding()]
param([string]$Exe = '', [switch]$RequireWrite, [switch]$SkipForms, [string]$WorkDir = "$env:TEMP\drag-lint-v154-ttdialog-$PID")
. (Join-Path $PSScriptRoot '..\autotest\lib\WorkDirCleanup.ps1')
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$ErrorActionPreference = 'Continue'
$script:Failed = $false
$script:Count = 0
function Check($n, $ok, $d = '') {
  $script:Count++
  Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $(if ($ok) { '' } else { $d })) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:Failed = $true }
}
Write-Host '== field dialogs ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$work = $WorkDir
[IO.Directory]::CreateDirectory($work) | Out-Null
function Run([string[]]$a) {
  $o = & $Exe @a 2>&1
  [pscustomobject]@{ Code = $LASTEXITCODE; Out = (($o | ForEach-Object { "$_" }) -join "`n") }
}
function Save($name, $r) { $f = Join-Path $work $name; [IO.File]::WriteAllText($f, $r.Out); $f }
function Model([string[]]$a) { (& (Join-Path $work 'FieldSelectTests.exe') @a 2>&1 | ForEach-Object { "$_" }) -join "`n" }
try {
  # ---- M, F ----
  $bat = Join-Path $Repo 'build\_build_plugin_fieldselect_tests_local.bat'
  $blog = Join-Path $work 'build.log'
  Start-Process -FilePath cmd.exe -ArgumentList ('/c ""' + $bat + '" "' + $work + '" > "' + $blog + '" 2>&1"') -Wait -NoNewWindow
  $bl = Get-Content -LiteralPath $blog -Raw
  Check 'M0 the model tests build' (($bl -match 'MODEL_EXITCODE=0') -and ($bl -notmatch 'Error: E\d+')) (($bl -split "`n" | Select-String 'Error' | Select-Object -First 3) -join ' / ')
  $u = @(& (Join-Path $work 'FieldSelectTests.exe') 2>&1 | ForEach-Object { "$_" }); $uc = $LASTEXITCODE
  $u | Where-Object { $_ -cmatch '^(FAIL|EXCEPTION)' } | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
  Check "M1 model tests ($($u | Select-Object -Last 1)), none skipped" (($uc -eq 0) -and (($u | Select-Object -Last 1) -eq 'Summary: pass=70 fail=0')) ($u | Select-Object -Last 1)
  if ($SkipForms) { Write-Host 'SKIP F0-F1 (-SkipForms)' }
  else {
    Check 'F0 the forms build without ToolsAPI' ($bl -match 'FORMS_EXITCODE=0') $blog
    $u = @(& (Join-Path $work 'FieldSelectForms.exe') 2>&1 | ForEach-Object { "$_" }); $uc = $LASTEXITCODE
    $u | Where-Object { $_ -cmatch '^(FAIL|EXCEPTION)' } | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    Check "F1 form tests ($($u | Select-Object -Last 1)), none skipped" (($uc -eq 0) -and (($u | Select-Object -Last 1) -eq 'Summary: pass=72 fail=0')) "exit $uc"
  }
  # ---- E ----
  $fix = Join-Path $work 'forms'
  [IO.Directory]::CreateDirectory($fix) | Out-Null
  Get-ChildItem (Join-Path $Repo 'tests\fixtures\fieldrepo\dialog') -File | ForEach-Object { [IO.File]::Copy($_.FullName, (Join-Path $fix $_.Name)) }
  $dfm = Join-Path $fix 'uDlg.dfm'
  $calc = Join-Path $fix 'uCalc.dfm'
  $x = Join-Path $work 'x.dlrepo'
  $null = Run @('repo', 'init', '--repo', $x)
  $null = Run @('repo', 'seed-fb', '--ddl', (Join-Path $fix 'schema.sql'), '--repo', $x, '--apply')
  $readAll = @('repo', 'read-dfm', '--repo', $x, '--dfm', $calc, '--direction', 'dfm-to-repo')
  $rs = Run ($readAll + '--json')
  Check 'E1a without --dataset: the datasets, no field lists' (($rs.Code -eq 0) -and $rs.Out.Contains('"dataset":"qryOrders"') -and -not $rs.Out.Contains('"persistent"') -and -not $rs.Out.Contains('"tableFields"')) $rs.Out
  $f = Save 'plan-read.json' $rs
  $sel = Join-Path $work 'sel.txt'
  $m = Model @('--plan', $f, $sel)
  Check 'E4a the change set of a read: one change, checked, no plan id' ($m -eq 'plan:  1 changes, 1 checked') $m
  Check 'E4b its --select file has no plan line' ([IO.File]::ReadAllText($sel) -eq "1`r`n") ([IO.File]::ReadAllText($sel))
  $r = Run ($readAll + @('--select', $sel))
  Check 'E4c the engine takes it and writes exactly that change' (($r.Code -eq 0) -and $r.Out.Contains('applied: 1 changes')) $r.Out
  $r = Run @('repo', 'read-dfm', '--repo', $x, '--dfm', $dfm, '--dataset', 'qryOrders', '--direction', 'dfm-to-repo', '--json')
  $j = $null; try { $j = $r.Out | ConvertFrom-Json } catch { $j = $null }
  Check 'E1b with --dataset: persistent fields with component, table, column' (($r.Code -eq 0) -and ($null -ne $j) -and (@($j.datasets).Count -eq 1) -and ((@($j.datasets[0].persistent | ForEach-Object { "$($_.component):$($_.kind):$($_.table).$($_.column)" }) -join ' ') -eq 'qryOrdersID:data:ORDERS.ID qryOrdersQTY:data:ORDERS.QTY qryOrdersOLD:data:ORDERS.OLD')) $r.Out
  Check 'E1c with --dataset: the repository''s fields with kind and body' (($null -ne $j) -and ((@($j.datasets[0].tableFields | ForEach-Object { "$($_.field):$($_.kind)" }) -join ' ') -eq 'ID:data NOTE:data PRICE:data QTY:data TOTAL:calc') -and (@($j.datasets[0].tableFields)[4].body -eq '{{TOTAL}}.Value := {{QTY}}.Value * {{PRICE}}.Value;')) $r.Out
  $f = Save 'read.json' $r
  $m = Model @('--rows', $f)
  Check 'E2 the rows of the dialog' ($m -eq "rows: ID+ NOTE- PRICE- QTY+ TOTAL- OLD+!`nrefusal: ") $m
  $m = Model @('--names', $f, '+TOTAL', '-ID', '-QTY')
  Check 'E3 clicks -> --names' ($m -eq "message: TOTAL needs PRICE: added`nmessage: QTY stays: TOTAL needs it`nnames: PRICE,QTY,TOTAL`nremoved: qryOrdersID`nrefusal: ") $m
  # ---- write-dfm ----
  $write = @('repo', 'write-dfm', '--repo', $x, '--dfm', $dfm, '--dataset', 'qryOrders', '--names', 'PRICE,QTY,TOTAL', '--direction', 'repo-to-dfm')
  $r = Run ($write + '--json')
  if (($r.Code -ne 0) -and $r.Out.Contains('unknown sub-verb "write-dfm"')) {
    Write-Host 'SKIP E5-E6: this engine has no repo write-dfm'
    if ($RequireWrite) { Check 'E5 repo write-dfm exists' $false $r.Out }
  }
  else {
    $f = Save 'plan-write.json' $r
    $m = Model @('--plan', $f, $sel)
    Check 'E5a plan: two added fields checked, two removals not' ($m -match '^plan: [0-9a-f]{16} 4 changes, 2 checked$') $m
    $before = [IO.File]::ReadAllText($dfm)
    $s = Run ($write + @('--select', $sel))
    $after = [IO.File]::ReadAllText($dfm)
    Check 'E5b the engine takes plan line and ids' (($s.Code -eq 0) -and $s.Out.Contains('applied: 2 changes')) $s.Out
    Check 'E5c exactly the checked changes' ($after.Contains('object qryOrdersPRICE: TFloatField') -and $after.Contains('object qryOrdersTOTAL: TFloatField') -and $after.Contains('object qryOrdersID:') -and $after.Contains('object qryOrdersOLD:') -and ($before -ne $after)) $after
    $s2 = Run ($write + @('--select', $sel))
    Check 'E6 the same file again: refused, nothing written' (($s2.Code -ne 0) -and ([IO.File]::ReadAllText($dfm) -ceq $after)) $s2.Out
  }
  # ---- R ----
  $entry = Get-Content (Join-Path $Repo 'features\entries\field-repository-forms.json') -Raw | ConvertFrom-Json
  $paths = @($entry.surfaces | Where-Object type -eq 'ide-menu' | ForEach-Object { $_.path })
  $want = @('Read Fields from Dataset...', 'Read Fields of All Datasets of Form...', 'Select Fields of Dataset...' | ForEach-Object { "drag-lint > Field Repository > $_" })
  Check 'R1 the entry registers exactly the three ide-menu paths' (($paths -join '|') -eq ($want -join '|')) ($paths -join '|')
  $wiki = Get-Content (Join-Path $Repo "docs\wiki\$($entry.wikiPage).md") -Raw
  Check 'R2 the wiki page names the three items' (@($want | Where-Object { -not $wiki.Contains(($_ -split ' > ')[-1].TrimEnd('.')) }).Count -eq 0)
  # ---- S ----
  $cmd = [IO.File]::ReadAllText((Join-Path $Repo 'src\delphi-plugin\DragLint.Plugin.Cmd.FieldRepo.pas'))
  foreach ($c in 'Read Fields from Dataset...', 'Read Fields of All Datasets of Form...', 'Select Fields of Dataset...') {
    Check "S1 a visible row: $c" ($cmd -match ("RegisterRow\('field-repository-0[789]-[a-z-]+', '" + [regex]::Escape($c) + "', True, Invoke\w+\);"))
  }
  Check 'S2 every dialog call passes the theme' ([regex]::Matches($cmd, '\b(PickDataset|SelectFields|ConfirmChanges)\([^\r\n]*ApplyIdeTheme').Count -eq 3)
  Check 'S3 a form edited after the dry run is not written' ($cmd -match "(?s)if ModuleIsDirty\(OpenModuleOf\(Form\.Dfm\)\) then Form\.Show\([^\r\n]*\r\n\s+else ApplySelection\(Form, SUB_WRITE_DFM")
  Check 'S4 a read is applied only when a second dry run is the same' ($cmd -match "if Newer\.Fingerprint = Plan\.Fingerprint then ApplySelection\(Form, SUB_READ_DFM")
  Check 'S5 --apply is never used: only --select writes' (([regex]::Matches($cmd.Substring($cmd.IndexOf('1.54 TT-DIALOG: the form')), '--apply').Count -eq 0))
} finally { Remove-WorkDir $work -Keep:($env:DL_KEEP_WORKDIR -eq '1') }
Write-Host "$script:Count checks"
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
