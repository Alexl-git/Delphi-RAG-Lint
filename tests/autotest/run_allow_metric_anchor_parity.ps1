<#
  run_allow_metric_anchor_parity.ps1 -- `allow` must accept a whole-routine metric
  marker on EXACTLY the line `lint` reports the finding on, however far down a
  big file that routine sits.

  THE DEFECTS THIS PINS (1.31.5 lane 7: B-10, B-11):
    `allow` re-measured the routine with every threshold at 1 so that "every
    routine reports". But each checker stops collecting at 200 findings, and at
    threshold 1 a file with ~100 routines hits that cap long before the end.
    A routine past the cap was therefore INVISIBLE to `allow` while `lint` (at
    the real thresholds) reported it -- so `allow` refused the exact command the
    review-marker-stale hint printed (YADF.Layout.pas:4063, B-10), and refused
    the lint-all anchors on a nested routine (CLI.pas RunUnit) and a multi-line
    header (Convert.Apply.pas BuildApplyPlan) (B-11). Measured pre-fix: all
    three cases below exit 2 "no routine at ... produces one".
    The cure: `allow` measures through the SAME function, with the SAME
    thresholds, that `lint` uses (RoutineMetricFindings in DRagLint.CLI).

  Also pins B-11 part 2: `lint-all --file` used to be accepted and ignored (a
  "scoped" --fix preview silently planned the whole project). It is now a
  usage error.

  And B-12 (check 7): in an allow batch on a wrapped statement, allowing the
  start line used to DELETE the continuation line's own live marker as
  "superseded", re-opening that finding.

  CONTROLS:
    * check 1 proves each finding fires before any marker exists;
    * the positive control (LongTwo) is a second over-long routine that is never
      allowed and must STILL be reported after the others are suppressed;
    * check 6 proves the lint-all refusal is about --file, not about the DB.

  Exit code: 0 on full pass, 1 on any failure.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = (Join-Path ([IO.Path]::GetTempPath()) ("draglint-allowparity-" + [Guid]::NewGuid().ToString('N')))
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
  if (-not $Ok) { $script:Failed = $true }
}

Write-Host '== allow accepts a metric marker where lint anchors it ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: engine not found at $Exe" -ForegroundColor Red; exit 1 }
$Exe = (Resolve-Path $Exe).Path
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$pas     = Join-Path $WorkDir 'uAllowParity.pas'
$errFile = Join-Path $WorkDir 'stderr.txt'

# --- fixture -----------------------------------------------------------------
# 210 small fillers: at threshold 1 each yields too-many-locals + method-too-long
# (420 > the 200 cap) and cyclomatic 2 (210 > 200), all of which are silent at
# the real thresholds.
$L = New-Object System.Collections.Generic.List[string]
$L.Add('unit uAllowParity;'); $L.Add(''); $L.Add('interface'); $L.Add(''); $L.Add('implementation'); $L.Add('')
for ($i = 1; $i -le 210; $i++) {
  $L.Add("procedure Fill$i(A: Integer);")
  $L.Add('var X, Y: Integer;')
  $L.Add('begin')
  $L.Add('  X:= A; Y:= X;')
  $L.Add('  if Y > 0 then X:= 0;')
  $L.Add('end;')
  $L.Add('')
}
function Add-Long([string]$Name, [string]$Marker) {
  $script:L.Add("procedure $Name;" + $Marker)
  $hdr = $script:L.Count
  $script:L.Add('var X: Integer;'); $script:L.Add('begin'); $script:L.Add('  X:= 0;')
  for ($k = 1; $k -le 260; $k++) { $script:L.Add('  X:= X + 1;') }
  $script:L.Add('end;'); $script:L.Add('')
  return $hdr
}
# B-10 shape: an existing MULTI-RULE marker whose method-too-long hash is stale.
$LONG1 = Add-Long 'LongOne' '  // dl:ok method-too-long@a1d0, deep-nesting@a1d0'
$LONG2 = Add-Long 'LongTwo' ''          # positive control: never allowed
# B-11 shape 1: a multi-line header with 26 locals.
$L.Add('procedure ManyLocals(')
$MANY = $L.Count
$L.Add('  A: Integer);')
$L.Add('var L01, L02, L03, L04, L05, L06, L07, L08, L09, L10, L11, L12, L13,')
$L.Add('    L14, L15, L16, L17, L18, L19, L20, L21, L22, L23, L24, L25, L26: Integer;')
$L.Add('begin'); $L.Add('  L01:= A;'); $L.Add('end;'); $L.Add('')
# B-11 shape 2: a NESTED routine over cyclomatic-complexity.
$L.Add('procedure Outer;')
$L.Add('  procedure Inner(A: Integer);')
$INNER = $L.Count
$L.Add('  begin')
for ($k = 1; $k -le 32; $k++) { $L.Add("    if A = $k then A:= 0;") }   # 33 > the default 30
$L.Add('  end;')
$L.Add('begin'); $L.Add('  Inner(0);'); $L.Add('end;'); $L.Add('')
$L.Add('end.')
[IO.File]::WriteAllText($pas, (($L -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)

function LintJson {
  $o = & $Exe lint $pas '--json' 2>$errFile
  $t = ($o | Out-String).Trim()
  if ($t -eq '') { return ,@() }
  return ,@($t | ConvertFrom-Json)
}
function Has($Fs, [string]$Rule, [int]$Line) { @($Fs | Where-Object { $_.rule -eq $Rule -and $_.start_line -eq $Line }).Count -gt 0 }
function Allow([int]$Line, [string]$Rule) {
  $o = & $Exe allow $pas '--fix-line' $Line '--fix-rule' $Rule '--apply' 2>$errFile
  [pscustomobject]@{ Out = (($o | Out-String) -replace "`r`n", "`n").Trim(); Code = $LASTEXITCODE }
}

# --- 1. every finding fires before any marker ----------------------------------
Write-Host '-- 1. KNOWN-FIRING' -ForegroundColor Cyan
$f = LintJson
Check "method-too-long fires on LongTwo:$LONG2 (positive control)" (Has $f 'method-too-long' $LONG2)
Check "too-many-locals fires on the multi-line header ManyLocals:$MANY" (Has $f 'too-many-locals' $MANY)
Check "cyclomatic-complexity fires on nested Inner:$INNER" (Has $f 'cyclomatic-complexity' $INNER)
$hint = @($f | Where-Object { $_.rule -eq 'review-marker-stale' -and $_.start_line -eq $LONG1 })
Check "review-marker-stale fires on LongOne:$LONG1 and names the remedy" ($hint.Count -eq 1 -and $hint[0].message -match "allow --fix-line $LONG1 --fix-rule method-too-long")

# --- 2-4. allow accepts the line lint reported ---------------------------------
Write-Host '-- 2. B-10: the remedy the stale hint prints is accepted' -ForegroundColor Cyan
$a = Allow $LONG1 'method-too-long'
Check 'allow exits 0' ($a.Code -eq 0) $a.Out
$hdrLine = (Get-Content -LiteralPath $pas)[$LONG1 - 1]
Check 'exactly one method-too-long marker, re-hashed in place' (([regex]::Matches($hdrLine, 'method-too-long@')).Count -eq 1 -and $hdrLine -notmatch 'method-too-long@a1d0') $hdrLine
Write-Host '-- 3. B-11: multi-line header' -ForegroundColor Cyan
$a = Allow $MANY 'too-many-locals'
Check 'allow exits 0' ($a.Code -eq 0) $a.Out
Write-Host '-- 4. B-11: nested routine' -ForegroundColor Cyan
$a = Allow $INNER 'cyclomatic-complexity'
Check 'allow exits 0' ($a.Code -eq 0) $a.Out

# --- 5. lint honours each marker; the positive control still fires ---------------
Write-Host '-- 5. SUPPRESSED where written, and nowhere else' -ForegroundColor Cyan
$f = LintJson
Check 'LongOne method-too-long suppressed'          (-not (Has $f 'method-too-long' $LONG1))
Check 'LongOne review-marker-stale gone'            (-not (Has $f 'review-marker-stale' $LONG1))
Check 'ManyLocals too-many-locals suppressed'       (-not (Has $f 'too-many-locals' $MANY))
Check 'Inner cyclomatic-complexity suppressed'      (-not (Has $f 'cyclomatic-complexity' $INNER))
Check 'LongTwo method-too-long STILL reported'      (Has $f 'method-too-long' $LONG2)
$st = @($f | Where-Object { $_.rule -like 'review-marker-stale' })
Check 'no review-marker-stale anywhere' ($st.Count -eq 0) ("count=" + $st.Count)

# --- 6. lint-all --file is a usage error ------------------------------------------
Write-Host '-- 6. lint-all --file is refused, not ignored' -ForegroundColor Cyan
$noDb = Join-Path $WorkDir 'none.sqlite'
$o = & $Exe lint-all '--db' $noDb '--file' $pas 2>&1; $code = $LASTEXITCODE
$txt = ($o | Out-String)
Check 'lint-all --file exits 2 naming --file' ($code -eq 2 -and $txt -match 'lint-all does not take --file') $txt.Trim()
$o = & $Exe lint-all '--db' $noDb 2>&1
$txt = ($o | Out-String)
Check 'control: lint-all without --file does not print the --file refusal' ($txt -notmatch 'does not take --file') $txt.Trim()

# --- 7. B-12: a batch must not delete a continuation line's OWN marker ------------
# Two findings on one wrapped statement: line 7 (start) and line 8 (continuation).
# Pre-fix, `allow 8` then `allow 7` "superseded" the line-8 marker -- a marker
# hashed at its own line, i.e. another finding's -- and line 8 re-opened.
Write-Host '-- 7. B-12: allow batch on a wrapped statement keeps both markers' -ForegroundColor Cyan
$pas = Join-Path $WorkDir 'uB12.pas'
$B = @('unit uB12;', 'interface', 'procedure P(var X: Integer);', 'implementation',
       'procedure P(var X: Integer);', 'begin', '  X:= X + 4711 +', '    9876;', '  X:= X + 5555;', 'end;', 'end.')
[IO.File]::WriteAllText($pas, (($B -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
$f = LintJson
Check 'precondition: large-magic-number fires on 7, 8 and 9' ((Has $f 'large-magic-number' 7) -and (Has $f 'large-magic-number' 8) -and (Has $f 'large-magic-number' 9))
$a8 = Allow 8 'large-magic-number'
$a7 = Allow 7 'large-magic-number'
Check 'both allows exit 0' ($a8.Code -eq 0 -and $a7.Code -eq 0) ($a8.Out + ' | ' + $a7.Out)
Check 'allow 7 superseded nothing' ($a7.Out -notmatch 'superseded') $a7.Out
$f = LintJson
Check 'line 7 suppressed' (-not (Has $f 'large-magic-number' 7))
Check 'line 8 suppressed (its marker survived)' (-not (Has $f 'large-magic-number' 8))
Check 'line 9 STILL reported (positive control)' (Has $f 'large-magic-number' 9)

if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
try { [IO.Directory]::Delete($WorkDir, $true) } catch { }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
