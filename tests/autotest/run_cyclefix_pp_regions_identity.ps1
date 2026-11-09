# run_cyclefix_pp_regions_identity.ps1 -- lane 150 CY1 (EX2 150 row, cycles half): fabcyc case 9 (a uses entry in a
# single-branch conditional region) reads the region's shape from the index's pp_regions rows (149 EX2) by default; the
# brace scan of the clause text is the fallback (a DB without the table, or DRAGLINT_CYCLES_PP=scan).
#
# IDENTITY (the acceptance): on every variant of tests\fixtures\cyclefix\guardeduses the `cycles --plan` stdout is
# BYTE-identical between the default (table) path and the forced scan path.
#   t*  stderr of the default run with DRAGLINT_CYCLES_PP=table names `pp_regions (table)` for GuA.pas (the table path
#       really ran: RED on 1.49.0-alpha base, which has no table path and prints nothing)
#   s*  POSITIVE CONTROL: with DRAGLINT_CYCLES_PP=scan stderr names `the brace scan` (the compare compares two paths)
#   i*  stdout default == stdout scan, byte for byte
#   b*  (with -BaselineExe, the engine before this change) its plan on the same DB is byte-identical to the default
#   fb  (with -LegacyExe, an engine that writes no pp_regions, e.g. 1.48.0-alpha): its DB plans through the brace scan
#       and the stdout equals the table path's on the same variant
# Variants: g (the case-9 shape), n1 ELSE branch, n2 an entry that stays, n4 the guarded entry moves (CYB), m1 the region
# mid-line, c1 a comment inside the region, k1 a region nested in the region.
#
# Usage: pwsh -File run_cyclefix_pp_regions_identity.ps1 [-Exe <drag-lint.exe>] [-LegacyExe <exe>] [-WorkDir <dir>] [-KeepWorkDir]
param(
  [string]$Exe       = $(if (Test-Path -LiteralPath "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe") { "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" } else { "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }),
  [string]$LegacyExe = '',
  [string]$BaselineExe = '',
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-ppid-$PID",
  [switch]$KeepWorkDir
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false; $script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { $script:Failed = $true; if ($d) { Write-Host ("        " + ($d -replace '^(.{0,400}).*$', '$1')) } }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe   = (Resolve-Path $Exe).Path
$Repo  = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Ascii = [Text.Encoding]::ASCII
$script:N = 0

function Edit-Text([string]$Path, [string]$From, [string]$To) {
  $t = [IO.File]::ReadAllText($Path, $Ascii)
  $f = $From -replace "`r?`n", "`r`n"
  if (-not $t.Contains($f)) { throw "patch anchor not found in ${Path}: $From" }
  [IO.File]::WriteAllText($Path, $t.Replace($f, ($To -replace "`r?`n", "`r`n")), $Ascii)
}
function New-Proj([string]$Tag, [scriptblock]$Patch, [string]$IndexExe) {
  $script:N++
  $root = Join-Path $WorkDir ("{0}-{1}" -f $Tag, $script:N)
  New-Item -ItemType Directory -Force $root | Out-Null
  Get-ChildItem (Join-Path $Repo 'tests\fixtures\cyclefix\guardeduses') -File | ForEach-Object { Copy-Item $_.FullName (Join-Path $root $_.Name) }
  if ($Patch) { & $Patch $root }
  $db = "$root.sqlite"
  Push-Location $WorkDir
  try { $null | & $IndexExe index --project (Join-Path $root 'GuardedUses.dproj') --db $db --library-db none *> "$db.log" } finally { Pop-Location }
  return @{ Root = $root; Dproj = (Join-Path $root 'GuardedUses.dproj'); Db = $db }
}
# stdout bytes (base64) and stderr text of `cycles --plan`, DRAGLINT_CYCLES_PP = $Mode ('' = unset)
function Get-Plan($P, [string]$Mode, [string]$With = $Exe) {
  $o = "$($P.Db).$Mode.out"; $e = "$($P.Db).$Mode.err"
  $old = $env:DRAGLINT_CYCLES_PP
  try {
    if ($Mode) { $env:DRAGLINT_CYCLES_PP = $Mode } else { Remove-Item Env:\DRAGLINT_CYCLES_PP -ErrorAction SilentlyContinue }
    $null = Start-Process -FilePath $With -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
      -ArgumentList @('cycles', '--plan', '--project', ('"' + $P.Dproj + '"'), '--db', ('"' + $P.Db + '"'), '--library-db', 'none') `
      -RedirectStandardOutput $o -RedirectStandardError $e
  } finally { if ($null -ne $old) { $env:DRAGLINT_CYCLES_PP = $old } else { Remove-Item Env:\DRAGLINT_CYCLES_PP -ErrorAction SilentlyContinue } }
  return @{ Out = [Convert]::ToBase64String([IO.File]::ReadAllBytes($o)); Text = [IO.File]::ReadAllText($o); Err = [IO.File]::ReadAllText($e) }
}

$Region = "{`$IFDEF GU_EXTRA}`n  GuB,`n{`$ENDIF}"
$Variants = @(
  @{ Tag = 'g';  Patch = $null },
  @{ Tag = 'n1'; Patch = { param($r) Edit-Text (Join-Path $r 'GuA.pas') $Region "{`$IFDEF GU_EXTRA}`n  GuB,`n{`$ELSE}`n  System.Classes,`n{`$ENDIF}" } },
  @{ Tag = 'n2'; Patch = { param($r) Edit-Text (Join-Path $r 'GuA.pas') $Region "{`$IFDEF GU_EXTRA}`n  GuB,`n  System.Classes,`n{`$ENDIF}" } },
  @{ Tag = 'n4'; Patch = { param($r) Edit-Text (Join-Path $r 'GuA.pas') "  Result := UpperCase('gu-a');`nend;" "  Result := UpperCase('gu-a');`n  if Result = '' then`n    GuSay;`nend;" }; NoBase = $true },
  @{ Tag = 'm1'; Patch = { param($r) Edit-Text (Join-Path $r 'GuA.pas') "uses`n$Region`n  System.SysUtils;" "uses`n  {`$IFDEF GU_EXTRA} GuB, {`$ENDIF} System.SysUtils;" } },
  @{ Tag = 'c1'; Patch = { param($r) Edit-Text (Join-Path $r 'GuA.pas') $Region "{`$IFDEF GU_EXTRA}`n  { extra } GuB,`n{`$ENDIF}" } },
  @{ Tag = 'k1'; Patch = { param($r) Edit-Text (Join-Path $r 'GuA.pas') $Region "{`$IFDEF GU_EXTRA}`n{`$IFDEF MSWINDOWS}`n  GuB,`n{`$ENDIF}`n{`$ENDIF}" } }
)

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  foreach ($v in $Variants) {
    $t = $v.Tag
    Write-Host "== $t" -ForegroundColor Cyan
    $P = New-Proj $t $v.Patch $Exe
    $pd = Get-Plan $P ''
    $pt = Get-Plan $P 'table'
    $ps = Get-Plan $P 'scan'
    Check "t-$t the table path ran (stderr names pp_regions for GuA.pas)" ($pt.Err -match 'case 9 GuA\.pas uses: conditional regions from pp_regions \(table\)') $pt.Err
    Check "s-$t control: DRAGLINT_CYCLES_PP=scan takes the brace scan" (($ps.Err -match 'case 9 GuA\.pas uses: conditional regions from the brace scan') -and ($ps.Err -notmatch 'pp_regions \(table\)')) $ps.Err
    Check "i-$t plan stdout byte-identical: default (table) == scan" (($pd.Out.Length -gt 0) -and ($pd.Out -ceq $ps.Out) -and ($pt.Out -ceq $pd.Out)) ($pd.Text + ' ||| ' + $ps.Text)
    Check "o-$t the default run prints no trace (stderr names no path)" ($pd.Err -notmatch 'case 9') $pd.Err
    # n4: its plan text changed on purpose in the same lane (found-in-150, CY2 HANDOVER: a guarded entry is no longer
    # rendered as a **move**), so the pre-change engine is no identity reference for it; i-n4 still compares both paths
    if ($BaselineExe -and -not $v.NoBase) {
      $pb = Get-Plan $P 'base' ((Resolve-Path $BaselineExe).Path)
      Check "b-$t plan stdout byte-identical to the engine before the change (-BaselineExe)" ($pb.Out -ceq $pd.Out) ($pb.Text + ' ||| ' + $pd.Text)
    }
    if ($LegacyExe) {
      $L = New-Proj "$t-legacy" $v.Patch ((Resolve-Path $LegacyExe).Path)
      $pl = Get-Plan $L 'table'
      # the copy lives in another folder: its paths are put back before the compare
      $same = $pl.Text.Replace($L.Db, $P.Db).Replace($L.Root, $P.Root) -ceq $pd.Text
      Check "fb-$t a DB without pp_regions falls back to the brace scan, same plan text" (($pl.Err -match 'conditional regions from the brace scan') -and $same) ($pl.Err + ' ||| ' + $pl.Text)
    }
  }
} finally {
  if (-not $KeepWorkDir) {
    for ($i = 0; ($i -lt 15) -and (Test-Path -LiteralPath $WorkDir); $i++) {
      try { [IO.Directory]::Delete($WorkDir, $true) } catch { Start-Sleep -Seconds 2 }
    }
  }
}
Write-Host ("run_cyclefix_pp_regions_identity: {0} ({1} checks)" -f ($(if ($script:Failed) { 'FAIL' } else { 'PASS' })), $script:Passed)
if ($script:Failed) { exit 1 } else { exit 0 }
