<#
  run_fix_overlap_deferred.ps1 -- a batch `--fix --apply` must never apply two
  fixes from DIFFERENT findings whose edits overlap. The first by finding order
  is applied, the rest are DEFERRED (reported "deferred": true, applied false),
  and a second --fix run applies what was deferred.

  Measured 2026-10-27 (lane DIRLINT, controller item 4): on
      R := ((UpperCase(S) = 'ABC'));
  uppercase-compare rewrites C10..30 in-line and redundant-parentheses rewrites
  C8..32 -- an overlap the applier never refused (it refused only overlapping
  DELETES). Both rows said applied:true and the line came out as
      R := (UpperCase(S) = 'ABC')
  -- the SameText rewrite lost and the statement's ';' gone: mixed bytes that
  do not compile.

    c1  pass 1: on line 10, exactly one of the two applied, the other deferred
    c2  pass 1 output compiles (dcc64; SKIP without rsvars.bat)
    c3  pass 2 applies the deferred finding; its output compiles too
    c4  control: line 13 (redundant-not-not / nonminimal-bool, its own conflict)
        still gets its FIRST fix in pass 1 -- deferral is per conflict, not per file

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$Rsvars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat',
  [string]$WorkDir = "$env:TEMP\draglint_fix_overlap_$PID"
)
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check([string]$what, [bool]$ok, [string]$detail = '') {
  if ($ok) { Write-Host "PASS  $what" } else { Write-Host "FAIL  $what $detail" -ForegroundColor Red; $script:fail = $true }
}
function Compiles([string]$dir, [string]$unit) {
  if (-not (Test-Path $Rsvars)) { Write-Host "SKIP  compile: no rsvars.bat" -ForegroundColor Yellow; return $true }
  $out = cmd /c "call `"$Rsvars`" >nul && cd /d `"$dir`" && dcc64 -M -Q -NSSystem;Winapi;Vcl -NU`"$dir`" `"$unit`"" 2>&1 | Out-String
  return -not ($out -match '(?m)\b(Error|Fatal)\b|[EF]\d{4}')
}
function Rows([string]$raw) { $r = @(); try { $r = @($raw | ConvertFrom-Json) } catch { $r = @() }; return ,@($r) }

$exePath = (Resolve-Path $Exe).Path
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$pas = Join-Path $WorkDir 'ov.pas'
$src = "unit ov;`r`n`r`ninterface`r`n`r`nimplementation`r`n`r`nuses`r`n  System.SysUtils;`r`n`r`n" +
       "procedure Demo(P: Pointer; S: string; var R: Boolean);`r`nbegin`r`n" +
       "  R := ((UpperCase(S) = 'ABC'));`r`n" +
       "  R := not not (P <> nil);`r`n" +
       "end;`r`n`r`nend.`r`n"
[IO.File]::WriteAllText($pas, $src, [Text.Encoding]::ASCII)
$lineA = 12; $lineB = 13
$pair  = @('uppercase-compare', 'redundant-parentheses')

Push-Location $env:TEMP
try {
  $r1 = Rows (& $exePath lint --file $pas --fix --apply --no-backup --json 2>$null | Out-String)
  $onA = @($r1 | Where-Object { $_.line -eq $lineA -and $pair -contains $_.rule })
  $app = @($onA | Where-Object { $_.applied -eq $true })
  $def = @($onA | Where-Object { $_.deferred -eq $true -and $_.applied -eq $false })
  Check "c1 pass 1: line $lineA has both findings, 1 applied + 1 deferred" (($onA.Count -eq 2) -and ($app.Count -eq 1) -and ($def.Count -eq 1)) (($onA | ForEach-Object { "$($_.rule):applied=$($_.applied),deferred=$($_.deferred)" }) -join '; ')
  $after1 = [IO.File]::ReadAllLines($pas)[$lineA - 1]
  Check "c2 pass 1 output compiles: '$after1'" (Compiles $WorkDir 'ov.pas')
  $nn = @($r1 | Where-Object { $_.line -eq $lineB -and $_.applied -eq $true })
  Check "c4 control: line $lineB (its own conflict) still applies its first fix in pass 1" ($nn.Count -eq 1)

  if ($def.Count -eq 1) {
    $deferredRule = $def[0].rule
    $r2 = Rows (& $exePath lint --file $pas --fix --apply --no-backup --json 2>$null | Out-String)
    $got = @($r2 | Where-Object { $_.rule -eq $deferredRule -and $_.applied -eq $true })
    $after2 = [IO.File]::ReadAllLines($pas)[$lineA - 1]
    Check "c3 pass 2 applies the deferred $deferredRule ('$after2')" ($got.Count -ge 1)
    Check "c3 pass 2 output compiles" (Compiles $WorkDir 'ov.pas')
  }
} finally {
  Pop-Location
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
if ($script:fail) { Write-Host 'run_fix_overlap_deferred: FAIL'; exit 1 }
Write-Host 'run_fix_overlap_deferred: PASS'
exit 0
