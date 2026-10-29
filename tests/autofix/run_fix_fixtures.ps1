<#
  run_fix_fixtures.ps1 -- table-driven proof of every autofix (autofix wave lane A0).

  Layout (additive: each lane adds its OWN directory, lanes never share a file):
    tests\autofix\fixtures\<rule-id>\<case>.pas           input; the rule fires on it
    tests\autofix\fixtures\<rule-id>\<case>.fixed.pas     expected result, written BY HAND
    tests\autofix\fixtures\<rule-id>\<case>.config.json   optional: passed as --config
                                                           (an OFF rule needs {"enabled":["<id>"]})
    tests\autofix\fixtures\<rule-id>\<case>.extra-args    optional: extra CLI tokens for every run of the case (--project-rules)
    tests\autofix\fixtures\<rule-id>\<case>.leaves        optional: integer N -- findings of <id> that legitimately remain after the fix\r\n                                                           (declined / report-only lines); default 0\r\n    tests\autofix\fixtures\<rule-id>\<case>.db-needed     optional marker: the case directory is
                                                           indexed into a scratch DB and --db is passed
    tests\autofix\fixtures\<rule-id>\_rules\              optional: a rules folder passed as --rules-dir to every
                                                           run of the directory's cases -- a test-only .scm rule
                                                           (zz-template-probe proves the sidecar "fix" path this way)
  Only directories holding at least one *.fixed.pas are cases; the loose legacy fixtures
  next to them (multi.pas, gating\, proj\ ...) are not touched.

  Per case, against a scratch copy named <case>.pas (so the unit name matches):
    1. lint --file <copy> --fix --fix-rule <id> --json --apply --no-backup
       -> the copy is BYTE-identical to <case>.fixed.pas (CRLF, ASCII, trailing newline)
    2. the same fix again (text mode) -> "autofix: no fixable findings", bytes unchanged
       (idempotence)
    3. lint --file <copy> --rule <id> --json -> zero rows for <id> (the fix resolves its
       own finding)
    4. with -Compile: dcc64 compiles the .fixed.pas (as <case>.pas); SKIP without rsvars.bat

  Usage:
    run_fix_fixtures.ps1 -Exe <drag-lint.exe> [-Filter <id-wildcard>] [-Compile] [-KeepScratch]
  Exit 0 = every case passed (or the filter matched none and -AllowEmpty was given).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$Filter  = '*',
  [switch]$Compile,
  [switch]$KeepScratch,
  [switch]$AllowEmpty,
  [string]$Rsvars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat',
  [string]$WorkDir = "$env:TEMP\drag-lint-fix-fixtures-$PID"
)
$ErrorActionPreference = 'Stop'
$script:pass = 0; $script:fail = 0; $script:skip = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:pass++; Write-Host "[PASS] $Name" -ForegroundColor Green }
  else {
    $script:fail++; Write-Host "[FAIL] $Name" -ForegroundColor Red
    if ($Detail) { Write-Host ("       " + $Detail) }
  }
}
function BytesEqual([byte[]]$A, [byte[]]$B) {
  if ($A.Length -ne $B.Length) { return $false }
  for ($i = 0; $i -lt $A.Length; $i++) { if ($A[$i] -ne $B[$i]) { return $false } }
  return $true
}
function FirstDiff([string]$PathA, [string]$PathB) {
  $a = [IO.File]::ReadAllLines($PathA); $b = [IO.File]::ReadAllLines($PathB)
  $n = [Math]::Max($a.Count, $b.Count)
  for ($i = 0; $i -lt $n; $i++) {
    $x = if ($i -lt $a.Count) { $a[$i] } else { '<eof>' }
    $y = if ($i -lt $b.Count) { $b[$i] } else { '<eof>' }
    if ($x -cne $y) { return "line $($i + 1): got '$x' want '$y'" }
  }
  return 'same lines, different bytes (line endings / trailing newline / encoding)'
}

$exePath = (Resolve-Path $Exe).Path
$root    = Join-Path $PSScriptRoot 'fixtures'
$canCompile = $Compile -and (Test-Path $Rsvars)
if ($Compile -and -not $canCompile) { Write-Host "SKIP compile: no rsvars.bat ($Rsvars)" -ForegroundColor Yellow }

$caseDirs = @(Get-ChildItem $root -Directory | Where-Object {
  ($_.Name -like $Filter) -and (@(Get-ChildItem $_.FullName -Filter '*.fixed.pas').Count -gt 0) } | Sort-Object Name)

if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$cases = 0
try {
  foreach ($dir in $caseDirs) {
    $id = $dir.Name
    foreach ($src in @(Get-ChildItem $dir.FullName -Filter '*.pas' | Where-Object { $_.Name -notlike '*.fixed.pas' } | Sort-Object Name)) {
      $case  = [IO.Path]::GetFileNameWithoutExtension($src.Name)
      $tag   = "$id/$case"
      $fixed = Join-Path $dir.FullName "$case.fixed.pas"
      if (-not (Test-Path $fixed)) { Check "${tag}: has $case.fixed.pas" $false; continue }
      $cases++
      $scr = Join-Path $WorkDir "$id\$case"
      New-Item -ItemType Directory -Force $scr | Out-Null
      $copy = Join-Path $scr "$case.pas"
      Copy-Item $src.FullName $copy -Force
      $extra = @()
      $db = $null
      $cfg = Join-Path $dir.FullName "$case.config.json"
      if (Test-Path $cfg) { $extra += @('--config', $cfg) }
      $rdir = Join-Path $dir.FullName '_rules'
      if (Test-Path $rdir) { $extra += @('--rules-dir', $rdir) }
      if (Test-Path (Join-Path $dir.FullName "$case.db-needed")) {
        $db = Join-Path $scr '_case.sqlite'
        Push-Location $scr
        try { & $exePath index $scr --db $db *> (Join-Path $scr '_index.log') } finally { Pop-Location }
        $extra += @('--db', $db)
      }
      $xa = Join-Path $dir.FullName "$case.extra-args"
      if (Test-Path $xa) { $extra += @((Get-Content $xa -Raw).Trim() -split '\s+') }   # e.g. --project-rules (doc rules)
      Push-Location $scr
      try {
        # 1. apply, byte-identical
        $raw = & $exePath lint --file $copy --fix --fix-rule $id --json --apply --no-backup @extra 2>$null | Out-String
        $rows = @(); try { $rows = @($raw | ConvertFrom-Json) } catch { $rows = @() }
        $applied = @($rows | Where-Object { $_.rule -eq $id -and $_.applied -eq $true }).Count
        Check "${tag}: --fix --apply applied >= 1 row" ($applied -ge 1) $raw.Trim()
        $same = BytesEqual ([IO.File]::ReadAllBytes($copy)) ([IO.File]::ReadAllBytes($fixed))
        Check "${tag}: result is byte-identical to $case.fixed.pas" $same $(if (-not $same) { FirstDiff $copy $fixed } else { '' })
        # a store-backed fix is re-checked against a FRESH index: the stale rows still name the deleted lines
        if ($db) { & $exePath index $scr --db $db *> (Join-Path $scr '_reindex.log') }
        # 2. idempotence
        $before = [IO.File]::ReadAllBytes($copy)
        $txt = & $exePath lint --file $copy --fix --fix-rule $id --apply --no-backup @extra 2>&1 | Out-String
        Check "${tag}: second run is a no-op ('autofix: no fixable findings')" ($txt -match 'autofix: no fixable findings') $txt.Trim()
        Check "${tag}: second run left the bytes unchanged" (BytesEqual $before ([IO.File]::ReadAllBytes($copy)))
        # 3. the rule no longer fires (a --db case was re-indexed after the fix, above)
        $raw3 = & $exePath lint --file $copy --rule $id --json @extra 2>$null | Out-String
        $left = -1; try { $left = @(@($raw3 | ConvertFrom-Json) | Where-Object { $_.rule -eq $id }).Count } catch { $left = -1 }
        $want = 0; $lf = Join-Path $dir.FullName "$case.leaves"; if (Test-Path $lf) { $want = [int](Get-Content $lf -Raw).Trim() }
        Check "${tag}: '$id' fires on the fixed file exactly $want time(s) (got $left)" ($left -eq $want) $raw3.Trim()
      } finally { Pop-Location }
      # 4. compile the expected result
      if ($canCompile) {
        $cdir = Join-Path $scr '_compile'
        New-Item -ItemType Directory -Force $cdir | Out-Null
        Copy-Item $fixed (Join-Path $cdir "$case.pas") -Force
        $out = cmd /c "call `"$Rsvars`" >nul && cd /d `"$cdir`" && dcc64 -M -Q -NSSystem;Winapi;Vcl -NU`"$cdir`" `"$case.pas`"" 2>&1 | Out-String
        $bad = ($out -match '(?m)\b(Error|Fatal)\b|[EF]\d{4}')
        Check "${tag}: $case.fixed.pas compiles (dcc64)" (-not $bad) (($out -split "`n" | Where-Object { $_ -match 'Error|Fatal|[EF]\d{4}' } | Select-Object -First 5) -join ' | ')
      }
    }
  }
} finally {
  if (-not $KeepScratch -and (Test-Path $WorkDir)) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
if ($cases -eq 0 -and -not $AllowEmpty) { Check "filter '$Filter' matched at least one case" $false }
Write-Host ("fix-fixtures: {0} case(s), {1} pass / {2} fail" -f $cases, $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
