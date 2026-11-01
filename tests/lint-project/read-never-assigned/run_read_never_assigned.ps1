<#
  run_read_never_assigned.ps1 -- the `read-never-assigned` project lint rule
  (owner request #5b, 1.40 lane flow).

  A field or global variable that something READS but that nothing in the whole
  project ever assigns or creates. It must not fire on a hard-cast write
  T(X).F := v (ref-gap G5), an out / var argument, an RTL var-parameter
  intrinsic (SetLength, Inc), a property write accessor, a published or
  default-section (DFM-streamed) field, a `with` write, an `absolute` alias, an
  initialised global, an initialization-section write, an address-of, a typed
  constant, or a record field.

    RUN 1  lint-all --rule read-never-assigned  -> exactly the TRIGGER lines, no CONTROL line
    RUN 1b plain lint-all (the rule is ON by default) -> the same TRIGGER lines
    RUN 2  lint-all --disable read-never-assigned -> no finding of the rule
    RUN 3  scratch copy with five exempting writes turned into reads -> each of
           those five fields / globals now fires (positive controls: the
           exemption, not an accident, kept it silent)

  Line numbers come from the fixture's TRIGGER-* / CONTROL-* markers.
  `lint-all --format json` is a BARE ARRAY whose line key is `start_line`.

  Usage: pwsh -File tests\lint-project\read-never-assigned\run_read_never_assigned.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
Set-Location $repo
$exePath = (Resolve-Path $Exe).Path
$decl    = Join-Path $PSScriptRoot 'uRnaDecl.pas'
$use     = Join-Path $PSScriptRoot 'uRnaUse.pas'
$scratch = Join-Path C:\TEMP "draglint_read_never_assigned_$PID"
$Rule    = 'read-never-assigned'
try {
if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path (Join-Path $scratch 'src') | Out-Null
Copy-Item $decl, $use (Join-Path $scratch 'src')
$db = Join-Path $scratch 'rna.sqlite'

$script:fail = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $tag = if ($Ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("[{0}] {1}{2}" -f $tag, $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
  if (-not $Ok) { $script:fail = $true }
}
function Parse-Findings([string[]]$Raw) {
  $txt = ($Raw -join "`n"); $b = $txt.IndexOf('[')
  $out = @(); if ($b -ge 0) { try { $out = @($txt.Substring($b) | ConvertFrom-Json) } catch { $out = @() } }
  if ($null -eq $out) { $out = @() }
  return ,@($out)
}
function LineOf([string]$Marker) {
  $m = @(Select-String -LiteralPath $decl -SimpleMatch -Pattern "// $Marker")
  if ($m.Count -ne 1) { throw "marker '$Marker' found $($m.Count) times in the fixture" }
  return [int]$m[0].LineNumber
}
function Of($Set) { return @($Set | Where-Object { $_.rule -eq $Rule -and (Split-Path $_.file_path -Leaf) -eq 'uRnaDecl.pas' }) }
function At($Set, [int]$L) { return @($Set | Where-Object { [int]$_.start_line -eq $L }) }

& $exePath index (Join-Path $scratch 'src') --db $db 2>&1 | Out-Null
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

$triggers = @('TRIGGER-FIELD', 'TRIGGER-OBJ', 'TRIGGER-GLOBAL')
$controls = @('CONTROL-CROSSUNIT', 'CONTROL-SELFWRITE', 'CONTROL-HARDCAST', 'CONTROL-WITH', 'CONTROL-VARARG',
              'CONTROL-OUTARG', 'CONTROL-RTLVAR', 'CONTROL-PROPSETTER', 'CONTROL-UNREAD', 'CONTROL-ADDR',
              'CONTROL-PUBLISHED', 'CONTROL-DEFAULTSECTION', 'CONTROL-INIT', 'CONTROL-VALUEINIT',
              'CONTROL-ABSBASE', 'CONTROL-ABSOLUTE', 'CONTROL-INC', 'CONTROL-TYPEDCONST')

# RUN 1 -- --rule names it (on any default)
$all = Parse-Findings (& $exePath lint-all --db $db --format json --rule $Rule 2>$null)
$a = Of $all
$a | ForEach-Object { Write-Host ("    {0}:{1} {2}" -f (Split-Path $_.file_path -Leaf), $_.start_line, $_.message) }
Check 'run 1: exactly 3 findings' ($a.Count -eq 3) "count=$($a.Count)"
foreach ($t in $triggers) { $l = LineOf $t; Check "$t fires" ((At $a $l).Count -eq 1) "line=$l" }
$msg = @(At $a (LineOf 'TRIGGER-GLOBAL'))
Check 'message names the global' ($msg.Count -eq 1 -and $msg[0].message -like '*GLimit*')
foreach ($c in $controls) { $l = LineOf $c; Check "$c stays silent" ((At $a $l).Count -eq 0) "line=$l" }

# RUN 1b -- ON by default: plain lint-all reports the same 3
$def = Of (Parse-Findings (& $exePath lint-all --db $db --format json 2>$null))
Check 'run 1b ON by default: plain lint-all gives the same 3' ($def.Count -eq 3) "count=$($def.Count)"

# RUN 2 -- --disable turns it off
$r2 = Parse-Findings (& $exePath lint-all --db $db --format json --disable $Rule 2>$null)
Check 'run 2 is not vacuous (lint-all returned findings)' ($r2.Count -gt 0) "total=$($r2.Count)"
Check 'run 2 --disable: no finding of the rule' ((Of $r2).Count -eq 0)

# RUN 3 -- positive controls: each exempting write becomes a read
$sd = Join-Path $scratch 'src\uRnaDecl.pas'; $su = Join-Path $scratch 'src\uRnaUse.pas'
$td = [IO.File]::ReadAllText($sd); $tu = [IO.File]::ReadAllText($su)
$edits = @(
  @($su, 'TRnaHolder(pObj).FCast:= 3;', 'Show(TRnaHolder(pObj).FCast);', 'CONTROL-HARDCAST'),
  @($su, 'with H do FWith:= 5;', 'with H do Show(FWith);', 'CONTROL-WITH'),
  @($sd, 'Fill(FVarArg);', 'Show(FVarArg);', 'CONTROL-VARARG'),
  @($sd, 'read FSize write FSize;', 'read FSize;', 'CONTROL-PROPSETTER'),
  @($sd, 'GInitSec:= 4;', 'Show(GInitSec);', 'CONTROL-INIT'))
foreach ($e in $edits) {
  $txt = if ($e[0] -eq $sd) { $td } else { $tu }
  Check "fixture spells '$($e[1])'" ($txt.Contains($e[1]))
  if ($e[0] -eq $sd) { $td = $td.Replace($e[1], $e[2]) } else { $tu = $tu.Replace($e[1], $e[2]) }
}
[IO.File]::WriteAllText($sd, $td, [Text.Encoding]::ASCII)
[IO.File]::WriteAllText($su, $tu, [Text.Encoding]::ASCII)
& $exePath index (Join-Path $scratch 'src') --db $db 2>&1 | Out-Null
$c3 = Of (Parse-Findings (& $exePath lint-all --db $db --format json --rule $Rule 2>$null))
Check 'run 3: 3 triggers + 5 positive controls' ($c3.Count -eq 8) "count=$($c3.Count)"
foreach ($e in $edits) { $l = LineOf $e[3]; Check "run 3 $($e[3]) fires once its write is gone" ((At $c3 $l).Count -eq 1) "line=$l" }
}
finally {
  if (Test-Path $scratch) { try { [System.IO.Directory]::Delete($scratch, $true) } catch { } }
}
if ($script:fail) { Write-Host 'FAIL'; exit 1 }
Write-Host 'PASS'; exit 0
