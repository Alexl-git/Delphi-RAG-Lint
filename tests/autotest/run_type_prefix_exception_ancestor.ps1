<#
  run_type_prefix_exception_ancestor.ps1 -- type-name-prefix must not ask for "T"
  on an exception class whose ancestry leaves the index.

  ORM3 BASICS.PAS:446 (2026-10-16): `EKeyViolation = class(EDatabaseError)`.
  EDatabaseError lives in Data.DB, outside the project index, so the store's
  IsDescendantOf answered "no" and the rule reported `should start with the "T"
  prefix`; Fix all planned EKeyViolation -> TEKeyViolation. The fallback reads
  the direct ancestor's NAME: Exception, or E + a capital, makes it an exception.

  Store-less lint of a fixture (no --db), the path where only the fallback can
  answer. Positive controls: a T-less class of TObject still fires, and so does
  an E-named class whose ancestor is not exception-named (EWidget = class(TObject))
  -- E alone is not an exemption.
  Full ancestry tracing: docs\INBOX-type-name-prefix-exception-ancestry.md.

  1.31.4 sections (2026-10-17):
    A  X1..X5   store-less, no --db
    Y  Y1..Y3   store-backed, library store forced nil
    B  B0a-d premises + B1..B11 (+count): fixture tests\lint-project\typeprefix-split,
       lint --db <app> --library-db <lib>. Gap cases B6/B7/B8 (unknown origin) each get
       ONE finding, severity "error", message `Ancestor "...`, and NO prefix finding.
    BA same lines via `lint-all --db <app> --db <lib>` (parity with B)
    C  C1..C5   `lint <copy> --db --library-db --fix --fix-naming --apply` on its own
       app unit (KeyDup -> EKeyDup, Widget -> TWidget; Foo/EKeyViolation untouched;
       no TE*/TK* names). Own unit: no collision with an existing EKeyViolation.
  Run GREEN with -Exe src\cli\Win64\Debug\drag-lint.exe (the default, dll-win64, is
  still the previous release until the deploy).

  RED-CHECK (2026-10-17; 43 checks in all):
    new build (0b626cfa + NamingFix begin/end)  : 43 PASS, 0 FAIL
    dll-win64 1.31.3-alpha (default -Exe)       : 24 PASS, 19 FAIL. RED: Y1-Y3 (no finding
        for TObject chains under a store with nil library); B2 B4 B5 B6 B7 B8 and the
        same in BA, both count checks; C1 C2 (no rename). B1/B3a/B3b PASS there only
        because 1.31.3 reports nothing on these classes; B2/B4/B5 are the controls
        that show it.
    1.30.1 (drag-lint.exe.bak-1.30.1-20261014 copied to scratch as drag-lint.exe with
        the dlls): 20 PASS, 23 FAIL. RED: X1-X3 (the original TEKeyViolation bug:
        library-owned exception chains asked for T); B1 B2 B3a B3b B6 B7 B8 + BA same
        + counts; C1, C3, C4, C5 (C4/C5: EKeyViolation became TEKeyViolation and the
        gap class Foo was renamed). C2 and X4/X5/Y1-Y3/B4/B5/B9-B11 PASS (unchanged
        behaviour). The B6-B8 gap finding is new in 1.31.4, so it is RED on both.
  Findings are mapped by name (lint --json is a bare array: start_line, severity,
  message), never $_.line.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail) {
  if ($Ok) { Write-Host "  PASS $Name" -ForegroundColor Green }
  else { Write-Host "  FAIL $Name -- $Detail" -ForegroundColor Red; $script:Failed = $true }
}

$work = Join-Path $env:TEMP ('draglint-excprefix-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
$pas = Join-Path $work 'ExcPrefix.pas'
$src = @(
  'unit ExcPrefix;'
  ''
  'interface'
  ''
  'uses'
  '  Data.DB;'
  ''
  'type'
  '  EKeyViolation = class(EDatabaseError);'
  '  EQualified = class(Data.DB.EDatabaseError);'
  '  EPlain = class(Exception);'
  '  Widget = class(TObject);'
  '  EWidget = class(TObject);'
  ''
  'implementation'
  ''
  'end.'
) -join "`r`n"
[IO.File]::WriteAllText($pas, $src + "`r`n", [Text.Encoding]::ASCII)

# lint --json is a bare ARRAY whose line field is start_line (not line)
$raw = & $Exe lint $pas --rule type-name-prefix --json 2>$null
$json = ($raw | Where-Object { $_ -notmatch '^\(loaded' }) -join "`n"
$found = @()
if ($json.Trim().StartsWith('[')) { $found = @($json | ConvertFrom-Json) }
$lines = @($found | Where-Object { $_.rule -eq 'type-name-prefix' } | ForEach-Object { [int]$_.start_line })
Write-Host "type-name-prefix lines: $($lines -join ',')"

Check 'X1 EKeyViolation = class(EDatabaseError): no finding' (-not ($lines -contains 9)) "lines: $($lines -join ',')"
Check 'X2 EQualified = class(Data.DB.EDatabaseError): no finding' (-not ($lines -contains 10)) "lines: $($lines -join ',')"
Check 'X3 EPlain = class(Exception): no finding' (-not ($lines -contains 11)) "lines: $($lines -join ',')"
Check 'X4 Widget = class(TObject) still fires (positive control)' ($lines -contains 12) "lines: $($lines -join ',')"
Check 'X5 EWidget = class(TObject) still fires: E alone is no exemption' ($lines -contains 13) "lines: $($lines -join ',')"

# Store-backed, NO library store (Y1..Y3). A TObject leaf is a certain plain-class
# root without any library index, so a class chained only to TObject must still
# be asked for "T". Library store forced nil: an explicit --library-db to a path
# that does not exist wins over the manifest/platform library (LintLibraryDb in
# DRagLint.CLI.pas), so the manifest library is NOT picked up silently.
$sdir = Join-Path $work 'store'
[IO.Directory]::CreateDirectory($sdir) | Out-Null
$spas = Join-Path $sdir 'StoreChain.pas'
$ssrc = @(
  'unit StoreChain;'
  ''
  'interface'
  ''
  'type'
  '  EWidget = class(TObject);'
  '  Foo = class(EWidget);'
  '  Widget = class(TObject);'
  ''
  'implementation'
  ''
  'end.'
) -join "`r`n"
[IO.File]::WriteAllText($spas, $ssrc + "`r`n", [Text.Encoding]::ASCII)
$sdb = Join-Path $work 'store.sqlite'
& $Exe index $sdir --db $sdb 2>&1 | Out-Null
$sraw = & $Exe lint $spas --db $sdb --library-db (Join-Path $work 'no-such-library.sqlite') --rule type-name-prefix --json 2>$null
$sjson = ($sraw | Where-Object { $_ -notmatch '^\(loaded' }) -join "`n"
$sfound = @()
if ($sjson.Trim().StartsWith('[')) { $sfound = @($sjson | ConvertFrom-Json) }
$sf = @($sfound | Where-Object { $_.rule -eq 'type-name-prefix' })
$slines = @($sf | ForEach-Object { [int]$_.start_line })
Write-Host "store-backed type-name-prefix lines: $($slines -join ',')"
function PrefixOk($line) { @($sf | Where-Object { [int]$_.start_line -eq $line -and $_.message -match 'should start with the "T" prefix' }).Count -eq 1 }
Check 'Y1 store-backed, no lib: EWidget = class(TObject) asks for T' (PrefixOk 6) "lines: $($slines -join ',')"
Check 'Y2 store-backed, no lib: Foo = class(EWidget) asks for T' (PrefixOk 7) "lines: $($slines -join ',')"
Check 'Y3 store-backed, no lib: Widget = class(TObject) asks for T' (PrefixOk 8) "lines: $($slines -join ',')"

# ---------------------------------------------------------------------------
# Section B: two-folder split (library index + project index), lint --library-db.
# Fixture: tests\lint-project\typeprefix-split\{lib,app}. EDatabaseError lives
# ONLY in the library DB, as in ORM3 (Data.DB). Findings are mapped by name
# (start_line, severity, message), per line AND per message letter.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'Section B: split library/project (lint --library-db)'
$fx     = (Resolve-Path (Join-Path $PSScriptRoot '..\lint-project\typeprefix-split')).Path
$libDir = Join-Path $fx 'lib'
$appDir = Join-Path $fx 'app'
$apas   = Join-Path $appDir 'typeprefixapp.pas'
$libDb  = Join-Path $work 'tp_lib.sqlite'
$appDb  = Join-Path $work 'tp_app.sqlite'
& $Exe index $libDir --db $libDb 2>&1 | Out-Null
& $Exe index $appDir --db $appDb 2>&1 | Out-Null
Check 'B0a both fixture dbs built' ((Test-Path $libDb) -and (Test-Path $appDb)) 'index failed'
$qa = (& $Exe query --name EDatabaseError --db $appDb --json 2>$null) -join "`n"
$ql = (& $Exe query --name EDatabaseError --db $libDb --json 2>$null) -join "`n"
Check 'B0b premise: EDatabaseError NOT in the app db' ($qa -notmatch 'EDatabaseError') 'the split is gone'
Check 'B0c premise: EDatabaseError IS in the lib db' ($ql -match 'EDatabaseError') 'lib db lacks it'

function ReadFindings($rawLines) {
  $j = ($rawLines | Where-Object { $_ -notmatch '^\(loaded' -and $_ -notmatch '^lint-all:' }) -join "`n"
  $b = $j.IndexOf('[')
  if ($b -lt 0) { return @() }
  try { return @(($j.Substring($b) | ConvertFrom-Json) | Where-Object { $_.rule -eq 'type-name-prefix' }) } catch { return @() }
}
$asrc = [IO.File]::ReadAllLines($apas)
function LineOfDecl([string]$name) {
  for ($i = 0; $i -lt $asrc.Count; $i++) { if ($asrc[$i] -match ('^\s+' + [regex]::Escape($name) + '\s*=')) { return $i + 1 } }
  return -1
}
$L = @{}
foreach ($n in 'EKeyViolation','KeyViolation','EBase','EDerived','Widget','EWidget','Foo','Vendor','EVendor','Plain','Svc','Rec') { $L[$n] = LineOfDecl $n }
Check 'B0d fixture lines located' (-not ($L.Values -contains -1)) (($L.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' ')

# One finding per line, with an exact severity and message shape.
function AssertSet([string]$tag, $fs) {
  function One($name, [string]$sev, [string]$rx) {
    $m = @($fs | Where-Object { [int]$_.start_line -eq $L[$name] })
    $ok = ($m.Count -eq 1) -and ($m[0].severity -eq $sev) -and ($m[0].message -match $rx)
    $d = if ($m.Count -eq 0) { 'no finding' } else { ($m | ForEach-Object { "[$($_.severity)] $($_.message)" }) -join ' | ' }
    return @($ok, $d)
  }
  function None($name) { $m = @($fs | Where-Object { [int]$_.start_line -eq $L[$name] }); return @(($m.Count -eq 0), "$($m.Count) finding(s)") }
  $gap = '^Ancestor "'
  $r = None 'EKeyViolation'; Check "$tag-B1 EKeyViolation(EDatabaseError): no finding (library hop)" $r[0] $r[1]
  $r = One 'KeyViolation' 'info' 'the "E" prefix'; Check "$tag-B2 KeyViolation(EDatabaseError): asks E (positive control)" $r[0] $r[1]
  $r = None 'EBase'; Check "$tag-B3a EBase(EDatabaseError): no finding" $r[0] $r[1]
  $r = None 'EDerived'; Check "$tag-B3b EDerived(EBase): no finding (two-level chain)" $r[0] $r[1]
  $r = One 'Widget' 'info' 'the "T" prefix'; Check "$tag-B4 Widget(TObject): asks T" $r[0] $r[1]
  $r = One 'EWidget' 'info' 'the "T" prefix'; Check "$tag-B5 EWidget(TLibThing): asks T (E is no exemption)" $r[0] $r[1]
  $r = One 'Foo' 'error' $gap; Check "$tag-B6 Foo(TVendorThing): one error gap finding, no prefix finding" $r[0] $r[1]
  $r = One 'Vendor' 'error' $gap; Check "$tag-B7 Vendor(EVendorBase): one error gap finding" $r[0] $r[1]
  $r = One 'EVendor' 'error' $gap; Check "$tag-B8 EVendor(EVendorBase): one error gap finding" $r[0] $r[1]
  $r = One 'Plain' 'info' 'the "T" prefix'; Check "$tag-B9 Plain = class: asks T" $r[0] $r[1]
  $r = One 'Svc' 'info' 'the "I" prefix'; Check "$tag-B10 Svc = interface: asks I" $r[0] $r[1]
  $r = One 'Rec' 'info' '^Record .*the "T" prefix'; Check "$tag-B11 Rec = record: asks T, says Record" $r[0] $r[1]
  Check "$tag total finding count is 9 (nothing extra)" (@($fs).Count -eq 9) "count=$(@($fs).Count)"
}
$bf = ReadFindings (& $Exe lint $apas --db $appDb --library-db $libDb --rule type-name-prefix --json 2>$null)
AssertSet 'B' $bf

Write-Host ''
Write-Host 'Section B-all: lint-all --db <app> --db <lib> (parity with Section B)'
$af = ReadFindings (& $Exe lint-all --db $appDb --db $libDb --rule type-name-prefix --json 2>$null)
AssertSet 'BA' $af

# ---------------------------------------------------------------------------
# Section C: fix parity (--fix --fix-naming). Own app unit (no KeyViolation
# beside EKeyViolation, so the fixer's collision refusal does not apply).
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'Section C: --fix --fix-naming on a copy'
$cdir = Join-Path $work 'fix'
$clib = Join-Path $cdir 'lib'
$capp = Join-Path $cdir 'app'
[IO.Directory]::CreateDirectory($clib) | Out-Null
[IO.Directory]::CreateDirectory($capp) | Out-Null
[IO.File]::Copy((Join-Path $libDir 'typeprefixlib.pas'), (Join-Path $clib 'typeprefixlib.pas'))
$cpas = Join-Path $capp 'typeprefixfix.pas'
$csrc = @(
  'unit typeprefixfix;'
  ''
  'interface'
  ''
  'uses'
  '  typeprefixlib;'
  ''
  'type'
  '  KeyDup = class(EDatabaseError);'
  '  Widget = class(TObject);'
  '  Foo = class(TVendorThing);'
  '  EKeyViolation = class(EDatabaseError);'
  ''
  'implementation'
  ''
  'end.'
) -join "`r`n"
[IO.File]::WriteAllText($cpas, $csrc + "`r`n", [Text.Encoding]::ASCII)
$cLibDb = Join-Path $cdir 'c_lib.sqlite'
$cAppDb = Join-Path $cdir 'c_app.sqlite'
& $Exe index $clib --db $cLibDb 2>&1 | Out-Null
& $Exe index $capp --db $cAppDb 2>&1 | Out-Null
& $Exe lint $cpas --db $cAppDb --library-db $cLibDb --fix --fix-naming --apply --rule type-name-prefix 2>&1 | Out-Null
$out = [IO.File]::ReadAllLines($cpas)
$outTxt = $out -join "`n"
Check 'C1 KeyDup = class(EDatabaseError) became EKeyDup' ($out -contains '  EKeyDup = class(EDatabaseError);') $outTxt
Check 'C2 Widget = class(TObject) became TWidget' ($out -contains '  TWidget = class(TObject);') $outTxt
Check 'C3 Foo = class(TVendorThing) untouched (gap)' ($out -contains '  Foo = class(TVendorThing);') $outTxt
Check 'C4 EKeyViolation = class(EDatabaseError) untouched' ($out -contains '  EKeyViolation = class(EDatabaseError);') $outTxt
Check 'C5 no TEKeyDup / TKeyDup / TEKeyViolation / TKeyViolation anywhere' ($outTxt -notmatch 'TEKeyDup|TKeyDup|TEKeyViolation|TKeyViolation') $outTxt
# ---------------------------------------------------------------------------
# Section S: stale project index. A class appended to the unit AFTER indexing is
# absent from the project DB; it must be silent (toUnknown), never a plain
# class. Positive control: the indexed Widget still asks for T.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'Section S: stale project index (class not in the index is silent)'
$stdir = Join-Path $work 'stale'
[IO.Directory]::CreateDirectory($stdir) | Out-Null
$stpas = Join-Path $stdir 'StaleUnit.pas'
$stlines = @('unit StaleUnit;', '', 'interface', '', 'type', '  Widget = class(TObject);', '', 'implementation', '', 'end.')
[IO.File]::WriteAllText($stpas, ($stlines -join "`r`n") + "`r`n", [Text.Encoding]::ASCII)
$stdb = Join-Path $work 'stale.sqlite'
& $Exe index $stdir --db $stdb 2>&1 | Out-Null
$stlines = @('unit StaleUnit;', '', 'interface', '', 'type', '  Widget = class(TObject);', '  EStale1 = class(Exception);', '  Stale2 = class(TObject);', '', 'implementation', '', 'end.')
[IO.File]::WriteAllText($stpas, ($stlines -join "`r`n") + "`r`n", [Text.Encoding]::ASCII)
$stf = @(ReadFindings (& $Exe lint $stpas --db $stdb --library-db $libDb --rule type-name-prefix --json 2>$null))
$stl = @($stf | ForEach-Object { [int]$_.start_line })
Write-Host "stale type-name-prefix lines: $($stl -join ',')"
Check 'S1 stale: indexed Widget = class(TObject) still asks for T (positive control)' (@($stf | Where-Object { [int]$_.start_line -eq 6 -and $_.message -match 'should start with the "T" prefix' }).Count -eq 1) "lines: $($stl -join ',')"
Check 'S2 stale: EStale1 = class(Exception) has no finding' (@($stf | Where-Object { [int]$_.start_line -eq 7 }).Count -eq 0) "lines: $($stl -join ',')"
Check 'S3 stale: Stale2 = class(TObject) has no finding' (@($stf | Where-Object { [int]$_.start_line -eq 8 }).Count -eq 0) "lines: $($stl -join ',')"
& $Exe lint $stpas --db $stdb --library-db $libDb --fix --fix-naming --apply --rule type-name-prefix 2>&1 | Out-Null
$stout = [IO.File]::ReadAllLines($stpas)
Check 'S4 stale --fix --fix-naming: EStale1 unchanged' ($stout -contains '  EStale1 = class(Exception);') ($stout -join "`n")
Check 'S5 stale --fix --fix-naming: Stale2 unchanged' ($stout -contains '  Stale2 = class(TObject);') ($stout -join "`n")

[IO.Directory]::Delete($work, $true)
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
