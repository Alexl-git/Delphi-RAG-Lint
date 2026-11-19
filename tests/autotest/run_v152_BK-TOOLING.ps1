<#
  run_v152_BK-TOOLING.ps1 -- lane BK-TOOLING (1.52): tooling backlog B13, B27, B28, B37, B46.
    B13  tools\dfm\compare-corpus.ps1 (the DFM grammar corpus A/B comparator) accepts a clean A/B pair and
         REJECTS a regression, a fixture that still fails and a short run (positive + negative controls; the
         HEAVY parse-corpus.ps1 itself is not run here).
    B27  run_hermetic_engine_guard.ps1 is green (every guard that relies on an absent manifest calls Get-HermeticEngine).
    B28  an engine whose own drag-lint.json says settings.ignoreLocalConfig reads no .drag-lint.json found by
         walking up from the CWD; the same engine WITHOUT the key still does (control).
    B37  run_encoding_guard.ps1 from a worktree finishes in under 90 s and still flags a lone LF (control).
    B46  run_resolver_version_guard.ps1 accepts -Exe; run_check_init_handlers.ps1 -Exe has a non-empty default.
  Parameters: -Exe engine for B28 (default: this tree's fresh Debug build).  Exit 0 = all pass.
#>
[CmdletBinding()]
param([string]$Exe = '')
$ErrorActionPreference = 'Continue'
$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$script:fail = $false
function Check($n, $ok, $d = '') {
  Write-Host ("  [{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $d) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:fail = $true }
}
$scratch = Join-Path ([IO.Path]::GetTempPath()) ("v152-bk-tooling-$PID")
[IO.Directory]::CreateDirectory($scratch) | Out-Null
try {
  # ---- B13 ----------------------------------------------------------------------------------------
  Write-Host '== B13 compare-corpus comparator ==' -ForegroundColor Cyan
  $cmp = Join-Path $Repo 'tools\dfm\compare-corpus.ps1'
  function WriteTsv($path, $rows) { [IO.File]::WriteAllText($path, (($rows | ForEach-Object { $_ -join "`t" }) -join "`r`n") + "`r`n", [Text.Encoding]::ASCII) }
  $fxA = 'C:\x\tests\fixtures\dfm-nonascii\FormAnsi.dfm'; $fxB = 'C:\x\tests\fixtures\dfm-nonascii\FormUtf8.dfm'
  $A = @(@('00001_a.dfm', 0, 'C:\c\a.dfm'), @('00002_b.dfm', 3, 'C:\c\b.dfm'), @('00003_FormAnsi.dfm', 2, $fxA), @('00004_FormUtf8.dfm', 1, $fxB))
  function MakeB([int]$aErr, [int]$fxErr) {
    return @(@('00001_a.dfm', $aErr, 'C:\c\a.dfm'), @('00002_b.dfm', 0, 'C:\c\b.dfm'), @('00003_FormAnsi.dfm', $fxErr, $fxA), @('00004_FormUtf8.dfm', 0, $fxB))
  }
  WriteTsv "$scratch\A.tsv" $A
  WriteTsv "$scratch\B.tsv" (MakeB 0 0)
  $null = & { $ErrorActionPreference = 'Continue'; & pwsh -NoProfile -File $cmp -A "$scratch\A.tsv" -B "$scratch\B.tsv" 2>&1 | ForEach-Object { "$_" } }
  Check 'B13 clean pair (B fixes b + both fixtures) passes' ($LASTEXITCODE -eq 0)
  WriteTsv "$scratch\Breg.tsv" (MakeB 4 0)
  $null = & { $ErrorActionPreference = 'Continue'; & pwsh -NoProfile -File $cmp -A "$scratch\A.tsv" -B "$scratch\Breg.tsv" 2>&1 | ForEach-Object { "$_" } }
  Check 'B13 CONTROL a regression in B is rejected' ($LASTEXITCODE -ne 0)
  WriteTsv "$scratch\Bfx.tsv" (MakeB 0 1)
  $null = & { $ErrorActionPreference = 'Continue'; & pwsh -NoProfile -File $cmp -A "$scratch\A.tsv" -B "$scratch\Bfx.tsv" 2>&1 | ForEach-Object { "$_" } }
  Check 'B13 CONTROL a fixture that still fails in B is rejected' ($LASTEXITCODE -ne 0)
  WriteTsv "$scratch\Bshort.tsv" ((MakeB 0 0) | Select-Object -First 3)
  $null = & { $ErrorActionPreference = 'Continue'; & pwsh -NoProfile -File $cmp -A "$scratch\A.tsv" -B "$scratch\Bshort.tsv" 2>&1 | ForEach-Object { "$_" } }
  Check 'B13 CONTROL a short run (different file set) is rejected' ($LASTEXITCODE -ne 0)

  # ---- B27 ----------------------------------------------------------------------------------------
  Write-Host '== B27 hermetic engine guard ==' -ForegroundColor Cyan
  $null = & { $ErrorActionPreference = 'Continue'; & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'run_hermetic_engine_guard.ps1') 2>&1 | ForEach-Object { "$_" } }
  Check 'B27 run_hermetic_engine_guard passes' ($LASTEXITCODE -eq 0)

  # ---- B37 ----------------------------------------------------------------------------------------
  Write-Host '== B37 encoding guard speed + control ==' -ForegroundColor Cyan
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $null = & { $ErrorActionPreference = 'Continue'; & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'run_encoding_guard.ps1') 2>&1 | ForEach-Object { "$_" } }
  $sw.Stop()
  Check 'B37 default run from this tree passes' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
  Check 'B37 default run finishes in under 90 s' ($sw.Elapsed.TotalSeconds -lt 90) ("{0:N0} s" -f $sw.Elapsed.TotalSeconds)
  $mini = Join-Path $scratch 'mini'; [IO.Directory]::CreateDirectory("$mini\src") | Out-Null
  [IO.File]::WriteAllBytes("$mini\src\lf.pas", [Text.Encoding]::ASCII.GetBytes("unit lf;`nend.`n"))
  $o2 = (& { $ErrorActionPreference = 'Continue'; & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'run_encoding_guard.ps1') -Repo $mini 2>&1 | ForEach-Object { "$_" } }) -join "`n"
  Check 'B37 CONTROL a lone-LF .pas is reported' ($o2 -match '\[FAIL\] no file has a lone LF')

  # ---- B46 ----------------------------------------------------------------------------------------
  Write-Host '== B46 -Exe parameters ==' -ForegroundColor Cyan
  $o3 = (& { $ErrorActionPreference = 'Continue'; & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'run_resolver_version_guard.ps1') -Exe 'C:\does\not\matter.exe' 2>&1 | ForEach-Object { "$_" } }) -join "`n"
  Check 'B46 run_resolver_version_guard accepts -Exe' (($o3 -notmatch 'parameter cannot be found|positional parameter') -and ($LASTEXITCODE -eq 0))
  $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'run_check_init_handlers.ps1'), [ref]$null, [ref]$null)
  $pe  = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Exe' }
  $def = if ($pe.DefaultValue) { $pe.DefaultValue.Extent.Text } else { '' }
  Check 'B46 run_check_init_handlers -Exe has a non-empty default' (($def -ne '') -and ($def -ne "''")) "default=[$def]"

  # ---- B28 ----------------------------------------------------------------------------------------
  Write-Host '== B28 ignoreLocalConfig ==' -ForegroundColor Cyan
  if ($Exe -eq '') { . "$PSScriptRoot\lib\FreshEngineExe.ps1"; $Exe = Get-FreshEngineExe }
  $srcDir = Split-Path -Parent (Resolve-Path -LiteralPath $Exe).Path
  function NewEngine($name, $manifestJson) {
    $d = Join-Path $scratch $name; [IO.Directory]::CreateDirectory($d) | Out-Null
    Get-ChildItem -LiteralPath $srcDir -File | Where-Object { $_.Name -match '\.(exe|dll|castlib)$' -and $_.Name -notmatch '\.bak' } |
      ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $d }
    if (Test-Path -LiteralPath (Join-Path $srcDir 'rules')) { Copy-Item -LiteralPath (Join-Path $srcDir 'rules') -Destination $d -Recurse }
    [IO.File]::WriteAllText((Join-Path $d 'drag-lint.json'), $manifestJson, [Text.Encoding]::ASCII)
    return (Join-Path $d 'drag-lint.exe')
  }
  $proj = Join-Path $scratch 'proj'; [IO.Directory]::CreateDirectory($proj) | Out-Null
  [IO.File]::WriteAllText("$proj\.drag-lint.json", '{"rule":"magic-literal"}', [Text.Encoding]::ASCII)
  $eOn  = NewEngine 'eng-on'  '{"settings":{"ignoreLocalConfig":true}}'
  $eOff = NewEngine 'eng-off' '{"settings":{"defaultPlatform":"Win32"}}'
  Push-Location $proj
  try {
    $rOn  = (& { $ErrorActionPreference = 'Continue'; & $eOn  --version 2>&1 | ForEach-Object { "$_" } } | Out-String)
    $rOff = (& { $ErrorActionPreference = 'Continue'; & $eOff --version 2>&1 | ForEach-Object { "$_" } } | Out-String)
  } finally { Pop-Location }
  Check 'B28 CONTROL engine without the key loads the local defaults file' ($rOff -match 'loaded defaults from')
  $seen = if ($rOn -match 'loaded defaults from[^\r\n]*') { $Matches[0] } else { '' }
  Check 'B28 engine with settings.ignoreLocalConfig loads NO local defaults file' ($rOn -notmatch 'loaded defaults from') $seen
} finally {
  try { [IO.Directory]::Delete($scratch, $true) } catch { $null = $_ }
}
if ($script:fail) { Write-Host 'run_v152_BK-TOOLING: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_v152_BK-TOOLING: PASS' -ForegroundColor Green; exit 0
