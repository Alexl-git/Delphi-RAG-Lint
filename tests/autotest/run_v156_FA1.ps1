<#
  run_v156_FA1.ps1 -- 1.56 lane FA-1: noreturn-contract (G-13) on tests\fixtures\v156-fa1, and the
  flow graph reading the stored noreturn fact (symbol_extras.noreturn, B1).

  A fixture line that must report carries "// FIRE noreturn-contract"; every other line must stay
  silent, so the rule has firing and silent controls in the same run.
    code after a call that never returns  -- the callee's directive stands in ANOTHER unit (or on the
        interface declaration only), so every one of these lines needs the stored fact: an engine whose
        flow graph does not read it reports none of them.
    a routine that never returns and is not declared noreturn -- reported only where the indexed RTL
        declares Abort noreturn (Delphi 13); four of the five need the stored fact of a callee.
  Also: silent on a file the index does not know (the rule needs the index), ON by default, the two
  severities, and the control of the "Delphi 13 RTL" gate (an RTL without the directive).

  Positive control of the whole runner: -Exe <an engine whose graph does not read the fact> -- the
  FIRE checks fail. Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-v156-fa1-$PID"
)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
try {
$ErrorActionPreference = 'Stop'
$script:Failed = 0
$script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $(if ($ok) { '' } else { $d })) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { $script:Failed++ }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Fix = (Resolve-Path "$PSScriptRoot\..\fixtures\v156-fa1").Path
$Rule = 'noreturn-contract'
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$Src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $Src | Out-Null
Copy-Item "$Fix\*.pas" $Src
$Db  = Join-Path $WorkDir 'p.sqlite'
$Cfg = Join-Path $WorkDir 'cfg.json'
[IO.File]::WriteAllText($Cfg, '{}', [Text.Encoding]::ASCII)
& { $ErrorActionPreference = 'Continue'; & $Exe index $Src --db $Db 2>&1 | ForEach-Object { "$_" } } | Out-Null
Check 'index exit 0' ($LASTEXITCODE -eq 0) "rc=$LASTEXITCODE"

# every finding of the run: file:line rule, severity, line (lint --json is a bare ARRAY with start_line)
function Get-Found([string[]]$Argv) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $Exe @Argv --json 2>$null }
  $txt = ($raw | Where-Object { $_ -is [string] }) -join "`n"
  $i = $txt.IndexOf('['); if ($i -lt 0) { return ,@() }
  return ,@($txt.Substring($i) | ConvertFrom-Json | ForEach-Object { $_ } | ForEach-Object {
    $r = if ($_.rule_id) { $_.rule_id } else { $_.rule }
    $p = if ($_.file_path) { $_.file_path } elseif ($_.path) { $_.path } else { $_.file }
    [pscustomobject]@{ Key = ("{0}:{1} {2}" -f (Split-Path $p -Leaf), $_.start_line, $r); Severity = "$($_.severity)"; Line = [int]$_.start_line } })
}
function Get-Wanted([string]$Dir) {
  return ,@(Get-ChildItem $Dir -Filter *.pas | ForEach-Object { $f = $_; $n = 0
    Get-Content $f.FullName | ForEach-Object { $n++; if ($_ -match "// FIRE $Rule\b") { "{0}:{1} {2}" -f $f.Name, $n, $Rule } } })
}
# 1-based line of the first fixture line holding $Text
function Line-Of([string]$Text) {
  $n = 0
  foreach ($l in Get-Content (Join-Path $Src 'uFa1.pas')) { $n++; if ($l.Contains($Text)) { return $n } }
  return 0
}

# positive-control: noreturn-contract
Write-Host 'WITH THE INDEX' -ForegroundColor Cyan
$want = Get-Wanted $Src
$got  = Get-Found @('lint-all', '--db', $Db, '--config', $Cfg, '--rule', $Rule)
$keys = @($got | ForEach-Object Key)
Check 'the fixture has eleven firing controls' ($want.Count -eq 11) "$($want.Count)"
foreach ($w in $want) { Check "fires $w" ($keys -contains $w) }
$extra = @($keys | Where-Object { $want -notcontains $_ })
Check "$Rule is silent elsewhere" ($extra.Count -eq 0) ($extra -join ', ')
$twice = @($keys | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name)
Check "$Rule reports a line once" ($twice.Count -eq 0) ($twice -join ', ')

Write-Host 'THE TWO FINDINGS' -ForegroundColor Cyan
$afterLine = Line-Of 'Count := 1; // FIRE'
$after = @($got | Where-Object { $_.Line -eq $afterLine })
Check 'code after a noreturn call is a warning' (($after.Count -eq 1) -and ($after[0].Severity -eq 'warning')) "line $afterLine n=$($after.Count) $($after | ForEach-Object Severity)"
$viaLine = Line-Of 'procedure ViaOther('
$via = @($got | Where-Object { $_.Line -eq $viaLine })
Check 'a routine that never returns is a hint' (($via.Count -eq 1) -and ($via[0].Severity -eq 'hint')) "line $viaLine n=$($via.Count) $($via | ForEach-Object Severity)"
$one = Get-Found @('lint', (Join-Path $Src 'uFa1.pas'), '--db', $Db, '--config', $Cfg, '--rule', $Rule)
$oneKeys = @($one | ForEach-Object Key)
Check 'lint <file> reports the same lines as lint-all' ((($oneKeys | Sort-Object) -join ' ') -eq (($keys | Sort-Object) -join ' ')) "$($oneKeys.Count) vs $($keys.Count)"

Write-Host 'A FILE THE INDEX DOES NOT KNOW' -ForegroundColor Cyan
$Other = Join-Path $WorkDir 'other'
New-Item -ItemType Directory $Other | Out-Null
[IO.File]::WriteAllText((Join-Path $Other 'Lone.pas'), "unit Lone;`r`ninterface`r`nimplementation`r`nend.`r`n", [Text.Encoding]::ASCII)
$OtherDb = Join-Path $WorkDir 'other.sqlite'
& { $ErrorActionPreference = 'Continue'; & $Exe index $Other --db $OtherDb 2>&1 | ForEach-Object { "$_" } } | Out-Null
$lone = Get-Found @('lint', (Join-Path $Src 'uFa1.pas'), '--db', $OtherDb, '--config', $Cfg, '--rule', $Rule)
$loneKeys = @($lone | ForEach-Object Key)
Check "$Rule is silent without the facts of the callees" ($loneKeys.Count -eq 0) ($loneKeys -join ', ')

Write-Host 'AN RTL WITHOUT THE DIRECTIVE (before Delphi 13)' -ForegroundColor Cyan
$Old = Join-Path $WorkDir 'old'
New-Item -ItemType Directory $Old | Out-Null
Copy-Item "$Fix\*.pas" $Old
$rtl = Join-Path $Old 'System.SysUtils.pas'
[IO.File]::WriteAllText($rtl, [IO.File]::ReadAllText($rtl).Replace(' noreturn;', ''), [Text.Encoding]::ASCII)
$OldDb = Join-Path $WorkDir 'old.sqlite'
& { $ErrorActionPreference = 'Continue'; & $Exe index $Old --db $OldDb 2>&1 | ForEach-Object { "$_" } } | Out-Null
$oldGot  = Get-Found @('lint-all', '--db', $OldDb, '--config', $Cfg, '--rule', $Rule)
$oldHint = @($oldGot | Where-Object Severity -eq 'hint' | ForEach-Object Key)
$oldWarn = @($oldGot | Where-Object Severity -eq 'warning' | ForEach-Object Key)
Check 'no "declare it noreturn" hint when the RTL has no directive' ($oldHint.Count -eq 0) ($oldHint -join ', ')
Check 'code after a noreturn call is still reported there' ($oldWarn.Count -eq 6) "$($oldWarn.Count)"

Write-Host 'DEFAULTS' -ForegroundColor Cyan
$default = Get-Found @('lint-all', '--db', $Db, '--config', $Cfg)
$n = @($default | Where-Object { $_.Key -like "* $Rule" }).Count
Check "$Rule is ON by default" ($n -eq $want.Count) "$n findings"
$rules = & { $ErrorActionPreference = 'Continue'; & $Exe rules --json 2>$null }
Check "rules --json lists $Rule" ((($rules | Where-Object { $_ -is [string] }) -join "`n").Contains('"' + $Rule + '"'))

Write-Host ("{0} passed, {1} failed" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  # this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP
  if (($WorkDir -like "$env:TEMP\drag-lint-v156-fa1-$PID*") -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}
