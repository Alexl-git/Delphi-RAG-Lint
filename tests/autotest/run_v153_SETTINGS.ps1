<#
  run_v153_SETTINGS.ps1 -- 1.53.0 SETTINGS-CORE: `drag-lint settings list|get|set|unset`
  over <anchor>\_D-RAG\drag-lint-project.json (+ .local.json). Spec criteria S1-S14
  (docs\superpowers\specs\2026-11-20-settings-store-design.md section 8), plus the usage errors.

  Fixture (temp folder): P\App.dproj (dummy), P\_D-RAG\ (empty), P\src\u.pas; Q\ has no _D-RAG.
  Against an engine without the verb every check fails (RED).

  Usage: pwsh -File tests\autotest\run_v153_SETTINGS.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param([string]$Exe = '')
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ($Exe -eq '') { $Exe = Join-Path $Root 'src\cli\Win64\Debug\drag-lint.exe' }
if (-not (Test-Path $Exe)) { Write-Host "SKIP: engine not found: $Exe"; exit 0 }

$Work = Join-Path ([IO.Path]::GetTempPath()) ('dl-v153-settings-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$P = Join-Path $Work 'P'
$Q = Join-Path $Work 'Q'
[void](New-Item -ItemType Directory -Force (Join-Path $P '_D-RAG'))
[void](New-Item -ItemType Directory -Force (Join-Path $P 'src'))
[void](New-Item -ItemType Directory -Force $Q)
$Dproj = Join-Path $P 'App.dproj'
$Unit = Join-Path $P 'src\u.pas'
$QUnit = Join-Path $Q 'a.pas'
$ProjFile = Join-Path $P '_D-RAG\drag-lint-project.json'
$LocalFile = Join-Path $P '_D-RAG\drag-lint-project.local.json'
function WriteAscii([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text, [Text.Encoding]::ASCII) }
WriteAscii $Dproj "<Project/>`r`n"
WriteAscii $Unit "unit u;`r`ninterface`r`nimplementation`r`nend.`r`n"
WriteAscii $QUnit "unit a;`r`ninterface`r`nimplementation`r`nend.`r`n"

$Pass = 0; $Fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Pass++; Write-Host "  PASS  $Name" } else { $script:Fail++; Write-Host "  FAIL  $Name  $Detail" }
}
# Every engine call: merged stdout+stderr, exit code. -Cwd defaults to a folder with no _D-RAG above it.
function Run([string[]]$A, [string]$Cwd = $Q) {
  Push-Location $Cwd
  try { $Out = & { $ErrorActionPreference = 'Continue'; & $Exe @A 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -notmatch '^drag-lint: warning: no drag-lint\.json found' } }; $Code = $LASTEXITCODE } finally { Pop-Location }
  return @{ out = (($Out | ForEach-Object { "$_" }) -join "`n"); code = $Code }
}
function Reset-Files { foreach ($F in @($ProjFile, $LocalFile)) { if (Test-Path $F) { [IO.File]::Delete($F) } } }
function BytesOf([string]$F) { if (Test-Path $F) { return ,[IO.File]::ReadAllBytes($F) } else { return ,[byte[]]@() } }
function SameBytes([byte[]]$A, [byte[]]$B) { return ([Convert]::ToBase64String($A) -eq [Convert]::ToBase64String($B)) }
function IsAsciiCrlf([string]$Path) {
  $B = [IO.File]::ReadAllBytes($Path)
  for ($i = 0; $i -lt $B.Length; $i++) {
    if ($B[$i] -gt 127) { return $false }
    if (($B[$i] -eq 10) -and (($i -eq 0) -or ($B[$i - 1] -ne 13))) { return $false }
  }
  return $true
}
function Json([string]$F) { if (-not (Test-Path $F)) { return $null }; return (Get-Content $F -Raw | ConvertFrom-Json | ForEach-Object { $_ }) }
$Pj = @('--project', $Dproj)

try {
  # S1 defaults
  Reset-Files
  $R = Run (@('settings', 'get', 'lint.profile') + $Pj)
  Check 'S1 get lint.profile default is empty, exit 0' (($R.code -eq 0) -and ($R.out.Trim() -eq '')) "code=$($R.code) out=[$($R.out)]"
  $R = Run (@('settings', 'get', 'taint.envSource') + $Pj)
  $Rb = Run (@('settings', 'get', 'backupDir') + $Pj)
  Check 'S1 get backupDir (1.54) default is empty, exit 0' (($Rb.code -eq 0) -and ($Rb.out.Trim() -eq '')) "code=$($Rb.code) out=[$($Rb.out)]"
  Check 'S1 get taint.envSource default true' (($R.code -eq 0) -and ($R.out.Trim() -eq 'true')) "code=$($R.code) out=[$($R.out)]"

  # S2 set creates the file
  $R = Run (@('settings', 'set', 'lint.profile', 'strict') + $Pj)
  Check 'S2 set exit 0' ($R.code -eq 0) "code=$($R.code) out=[$($R.out)]"
  Check 'S2 project file created with lint.profile' ((Test-Path $ProjFile) -and ((Json $ProjFile).lint.profile -eq 'strict')) ''

  # S3 local wins
  $R = Run (@('settings', 'set', 'lint.profile', 'fast', '--local') + $Pj)
  $G = Run (@('settings', 'get', 'lint.profile') + $Pj)
  Check 'S3 get returns the local value' (($G.code -eq 0) -and ($G.out.Trim() -eq 'fast')) "out=[$($G.out)]"
  $L = Run (@('settings', 'list', '--json') + $Pj)
  $Row = $null
  try { $Row = @((($L.out | ConvertFrom-Json | ForEach-Object { $_ }).settings) | Where-Object { $_.key -eq 'lint.profile' })[0] } catch { }
  Check 'S3 list --json source local' (($null -ne $Row) -and ($Row.source -eq 'local')) "out=[$($L.out)]"

  # S4 round trip keeps unknown keys, order, ASCII CRLF
  Reset-Files
  WriteAscii $ProjFile "{`r`n  `"_comment`": [`"a/b`", `"c`"],`r`n  `"ownRoots`": [`"..\\..`"],`r`n  `"zzUnknown`": 1`r`n}`r`n"
  $R = Run (@('settings', 'set', 'taint.envSource', 'false') + $Pj)
  $Txt = [IO.File]::ReadAllText($ProjFile)
  $i1 = $Txt.IndexOf('"_comment"'); $i2 = $Txt.IndexOf('"ownRoots"'); $i3 = $Txt.IndexOf('"zzUnknown"')
  Check 'S4 set exit 0' ($R.code -eq 0) "code=$($R.code) out=[$($R.out)]"
  Check 'S4 the three keys survive in order' (($i1 -ge 0) -and ($i2 -gt $i1) -and ($i3 -gt $i2)) ''
  Check 'S4 file is 7-bit ASCII with CRLF' (IsAsciiCrlf $ProjFile) ''
  Check 'S4 slash is not escaped' (-not $Txt.Contains('\/')) ''
  $L = Run (@('settings', 'list', '--json') + $Pj)
  $U = $null
  try { $U = @(($L.out | ConvertFrom-Json | ForEach-Object { $_ }).unknown)[0] } catch { }
  Check 'S4 list --json unknown[0] is zzUnknown' (($null -ne $U) -and ($U.key -eq 'zzUnknown')) "out=[$($L.out)]"

  # S5 unknown key
  Reset-Files
  WriteAscii $ProjFile "{`r`n  `"ownRoots`": [`"src`"]`r`n}`r`n"
  $Bp = BytesOf $ProjFile; $Bl = BytesOf $LocalFile
  $R1 = Run (@('settings', 'set', 'no.such.key', '1') + $Pj)
  $R2 = Run (@('settings', 'unset', 'no.such.key') + $Pj)
  Check 'S5 set and unset unknown key -> 2' (($R1.code -eq 2) -and ($R2.code -eq 2)) "codes=$($R1.code),$($R2.code)"
  Check 'S5 files byte-identical' ((SameBytes $Bp (BytesOf $ProjFile)) -and (SameBytes $Bl (BytesOf $LocalFile))) ''

  # S6 bad values
  $R1 = Run (@('settings', 'set', 'taint.envSource', 'maybe') + $Pj)
  $R2 = Run (@('settings', 'set', 'lint.profile', ([string][char]0xE9)) + $Pj)
  $R3 = Run (@('settings', 'set', 'ownRoots', '[]') + $Pj)
  Check 'S6 bool maybe / non-ASCII / empty ownRoots -> 2' (($R1.code -eq 2) -and ($R2.code -eq 2) -and ($R3.code -eq 2)) "codes=$($R1.code),$($R2.code),$($R3.code)"
  Check 'S6 nothing written' ((SameBytes $Bp (BytesOf $ProjFile)) -and (-not (Test-Path $LocalFile))) ''

  # S7 malformed target file
  Reset-Files
  WriteAscii $LocalFile "[1,2]`r`n"
  $Bl = BytesOf $LocalFile
  $Rs = @(
    (Run (@('settings', 'list') + $Pj)),
    (Run (@('settings', 'get', 'lint.profile') + $Pj)),
    (Run (@('settings', 'set', 'lint.profile', 'x', '--local') + $Pj)),
    (Run (@('settings', 'unset', 'lint.profile', '--local') + $Pj)))
  $AllTwo = $true; $Named = $true
  foreach ($X in $Rs) { if ($X.code -ne 2) { $AllTwo = $false }; if (-not $X.out.Contains('drag-lint-project.local.json')) { $Named = $false } }
  Check 'S7 list/get/set/unset on a non-object file -> 2' $AllTwo ("codes=" + (($Rs | ForEach-Object { $_.code }) -join ','))
  Check 'S7 output names the file' $Named ''
  Check 'S7 local file bytes unchanged' (SameBytes $Bl (BytesOf $LocalFile)) ''

  # S8 --local on a project-only key
  Reset-Files
  $R = Run (@('settings', 'set', 'ownRoots', '["src"]', '--local') + $Pj)
  Check 'S8 set ownRoots --local -> 2' (($R.code -eq 2) -and (-not (Test-Path $LocalFile))) "code=$($R.code)"

  # S9 not settable
  WriteAscii $ProjFile "{`r`n  `"popupForms`": [{`"form`": `"TF`", `"note`": `"n`"}]`r`n}`r`n"
  $Bp = BytesOf $ProjFile
  $R1 = Run (@('settings', 'set', 'popupForms', 'x') + $Pj)
  $R2 = Run (@('settings', 'unset', 'popupForms') + $Pj)
  $G = Run (@('settings', 'get', 'popupForms') + $Pj)
  Check 'S9 set/unset popupForms -> 2' (($R1.code -eq 2) -and ($R2.code -eq 2)) "codes=$($R1.code),$($R2.code)"
  Check 'S9 get popupForms prints the stored JSON' (($G.code -eq 0) -and $G.out.Contains('"TF"')) "out=[$($G.out)]"
  Check 'S9 file unchanged' (SameBytes $Bp (BytesOf $ProjFile)) ''

  # S10 idempotent set
  Reset-Files
  $R1 = Run (@('settings', 'set', 'lint.profile', 'strict') + $Pj)
  $T1 = if (Test-Path $ProjFile) { (Get-Item $ProjFile).LastWriteTimeUtc } else { $null }
  Start-Sleep -Milliseconds 1100
  $R2 = Run (@('settings', 'set', 'lint.profile', 'strict') + $Pj)
  Check 'S10 second identical set -> 1' (($R1.code -eq 0) -and ($R2.code -eq 1)) "codes=$($R1.code),$($R2.code)"
  Check 'S10 mtime unchanged' ((Test-Path $ProjFile) -and ((Get-Item $ProjFile).LastWriteTimeUtc -eq $T1)) ''

  # S11 unset removes the empty parent
  $R = Run (@('settings', 'unset', 'lint.profile') + $Pj)
  $O = Json $ProjFile
  Check 'S11 unset exit 0 and .lint gone' (($R.code -eq 0) -and ($null -eq $O.lint)) "code=$($R.code)"
  $R = Run (@('settings', 'unset', 'lint.profile') + $Pj)
  Check 'S11 unset of an absent key -> 1' ($R.code -eq 1) "code=$($R.code)"

  # S12 anchors via --db and --in
  Reset-Files
  [void](Run (@('settings', 'set', 'lint.profile', 'viaProject') + $Pj))
  $G1 = Run @('settings', 'get', 'lint.profile', '--db', (Join-Path $P '_D-RAG\x.sqlite'))
  $G2 = Run @('settings', 'get', 'lint.profile', '--in', $Unit)
  Check 'S12 --db anchor' (($G1.code -eq 0) -and ($G1.out.Trim() -eq 'viaProject')) "out=[$($G1.out)]"
  Check 'S12 --in anchor' (($G2.code -eq 0) -and ($G2.out.Trim() -eq 'viaProject')) "out=[$($G2.out)]"

  # S13 no anchor
  $G = Run @('settings', 'get', 'lint.profile', '--in', $QUnit) $Q
  Check 'S13 no anchor -> 2 "no project"' (($G.code -eq 2) -and ($G.out -match 'no project')) "code=$($G.code) out=[$($G.out)]"

  # S14 ignore note once
  Reset-Files
  $R1 = Run (@('settings', 'set', 'lint.profile', 'a', '--local') + $Pj)
  $R2 = Run (@('settings', 'set', 'lint.profile', 'b', '--local') + $Pj)
  Check 'S14 first local set prints the ignore note' (($R1.code -eq 0) -and ($R1.out -match 'ignore')) "out=[$($R1.out)]"
  Check 'S14 second local set does not' (($R2.code -eq 0) -and ($R2.out -notmatch 'ignore')) "out=[$($R2.out)]"

  # usage
  $R1 = Run @('settings')
  $R2 = Run @('settings', 'bogus')
  Check 'usage: settings / settings bogus -> 2' (($R1.code -eq 2) -and ($R2.code -eq 2)) "codes=$($R1.code),$($R2.code)"
}
catch { $Fail++; Write-Host "  FAIL  exception: $($_.Exception.Message)" }
finally { try { [IO.Directory]::Delete($Work, $true) } catch { } }

Write-Host "$Pass passed, $Fail failed"
if ($Fail -gt 0) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }
