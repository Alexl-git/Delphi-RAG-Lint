<#
  run_enum_type_marker.ps1 -- TYPE-LEVEL dl:ok for enum-ordinal-cast, across units
  (lane ENUMRULES, owner rule 2026-10-28: ONE `dl:ok <rule-id>` on the type
  declaration silences that rule for every cast of the type).

    RUN 1  lint uEnumUse.pas --db   -> TFreeCmd(1) fires (positive control); the
                                       two TMarkedCmd casts are silent (marker in
                                       ANOTHER unit)
    RUN 2  lint uEnumDecl.pas --db  -> the type marker is NOT reported unused (a
                                       file-scoped run cannot see the casts)
    RUN 3  lint-all --db            -> same silence/fire; marker not unused
    RUN 4  scratch copy with the marker removed -> the TMarkedCmd casts fire

  `lint --json` is a BARE ARRAY whose line key is `start_line`.
  Usage: pwsh -File tests\lint-project\enum-type-marker\run_enum_type_marker.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
Set-Location $repo
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP "draglint_enum_type_marker_$PID"
$Rule    = 'enum-ordinal-cast'
try {
if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path (Join-Path $scratch 'src') | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'uEnumDecl.pas') (Join-Path $scratch 'src')
Copy-Item (Join-Path $PSScriptRoot 'uEnumUse.pas') (Join-Path $scratch 'src')
$decl = Join-Path $scratch 'src\uEnumDecl.pas'
$use  = Join-Path $scratch 'src\uEnumUse.pas'
$db   = Join-Path $scratch 'enumtypemarker.sqlite'

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
function LineIn([string]$File, [string]$Text) {
  $m = @(Select-String -LiteralPath $File -SimpleMatch -Pattern $Text)
  if ($m.Count -ne 1) { throw "text '$Text' found $($m.Count) times in $File" }
  return [int]$m[0].LineNumber
}
function At($Set, [string]$Leaf, [int]$L) {
  return @($Set | Where-Object { ((Split-Path $_.file_path -Leaf) -eq $Leaf) -and ([int]$_.start_line -eq $L) })
}
$typeLine = LineIn $decl 'TMarkedCmd = ('
$mCast = LineIn $use 'CONTROL-MARKED-CAST'
$mOrd  = LineIn $use 'CONTROL-MARKED-ORD'
$fCast = LineIn $use 'TRIGGER-FREE-CAST'

& $exePath index (Join-Path $scratch 'src') --db $db 2>&1 | Out-Null
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

# RUN 1 -- the using unit alone
$r1 = Parse-Findings (& $exePath lint $use --db $db --json 2>$null)
$c1 = @($r1 | Where-Object { $_.rule -eq $Rule })
Check 'run 1 positive control: TFreeCmd(1) fires' ((At $c1 'uEnumUse.pas' $fCast).Count -eq 1) "count=$($c1.Count)"
Check 'run 1 TMarkedCmd(1) silenced by the type marker in another unit' ((At $c1 'uEnumUse.pas' $mCast).Count -eq 0)
Check 'run 1 Ord(M) = 2 silenced by the type marker in another unit' ((At $c1 'uEnumUse.pas' $mOrd).Count -eq 0)

# RUN 2 -- the declaring unit alone: the casts are elsewhere, so the marker cannot be judged
$r2 = Parse-Findings (& $exePath lint $decl --db $db --json 2>$null)
Check 'run 2 type marker is NOT reported unused by a file-scoped run' (@(At @($r2 | Where-Object { $_.rule -eq 'review-marker-unused' }) 'uEnumDecl.pas' $typeLine).Count -eq 0)

# RUN 3 -- lint-all
$r3 = Parse-Findings (& $exePath lint-all --db $db --format json 2>$null)
$c3 = @($r3 | Where-Object { $_.rule -eq $Rule })
Check 'run 3 lint-all: TFreeCmd(1) fires' ((At $c3 'uEnumUse.pas' $fCast).Count -eq 1) "count=$($c3.Count)"
Check 'run 3 lint-all: TMarkedCmd casts silent' (((At $c3 'uEnumUse.pas' $mCast).Count + (At $c3 'uEnumUse.pas' $mOrd).Count) -eq 0)
Check 'run 3 lint-all: type marker NOT reported unused' (@(At @($r3 | Where-Object { $_.rule -eq 'review-marker-unused' }) 'uEnumDecl.pas' $typeLine).Count -eq 0)

# RUN 4 -- positive control: remove the marker, the casts come back
$txt = [IO.File]::ReadAllText($decl)
$mark = '// dl:ok enum-ordinal-cast -- REVIEWED 2026-10-28 ordinals mirror the wire protocol'
Check 'fixture spells the marker' ($txt.Contains($mark))
[IO.File]::WriteAllText($decl, $txt.Replace($mark, '// marker removed'), [Text.Encoding]::ASCII)
$r4 = Parse-Findings (& $exePath lint $use --db $db --json 2>$null)
$c4 = @($r4 | Where-Object { $_.rule -eq $Rule })
Check 'run 4 marker removed -> TMarkedCmd(1) fires' ((At $c4 'uEnumUse.pas' $mCast).Count -eq 1) "count=$($c4.Count)"
Check 'run 4 marker removed -> Ord(M) = 2 fires' ((At $c4 'uEnumUse.pas' $mOrd).Count -eq 1)
}
finally {
  if (Test-Path $scratch) { try { [System.IO.Directory]::Delete($scratch, $true) } catch { } }
}
if ($script:fail) { Write-Host 'FAIL'; exit 1 }
Write-Host 'PASS'; exit 0