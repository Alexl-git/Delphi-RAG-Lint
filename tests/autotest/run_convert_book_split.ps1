<#
run_convert_book_split.ps1 -- D2 guard: BDE-to-FireDAC.rules + DataDB-to-FireDAC.rules
must together plan/produce exactly what the pre-split single book did.

  A  dry runs (convert-apply, no --apply) on the tests\autotest\fixtures\bdesplit form:
     multiset of items (kind, instance, path, value, old_value, field, from_type, to_type,
     file leaf, line, text without its "line N:" prefix) of BDE UNION Data.DB == pre-split
     book; same for warnings (book line numbers stripped), converted, unlinked and the
     distinct uses edits. The migrate items are compared apart (1.38: identifier #migrate
     lines rename in code, file-scope or not): the split books rename every site the
     pre-split book renames (A3), plus TDBScreenCursor, which the pre-split book misspelt (A3b).
  B  BYTES (a dry run proves the plan, not the bytes): the pre-split book --apply on a
     scratch copy of the fixture vs BDE book --apply then Data.DB book --apply on another
     copy (reindex between): .dfm identical, .pas identical after dropping the audit stamp
     comments and sorting the uses units. Also Origin is gone from the TAutoIncField.
  C  positive controls: a BDE book with one #link deleted fails A; a Data.DB book with the
     TAutoIncField To-unit dropped fails A; a Data.DB book without '#remove DFM: Origin'
     fails B (the stale BDE Origin survives).

Scratch only: the fixture is copied, every --db is under -WorkDir except the read-only
library DB; nothing is written to a real project. Plain 7-bit ASCII, CRLF.
#>
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$LibDb   = 'C:\Projects\.drag-lint\library-Win64.sqlite',
  [string]$PreRef  = '5bcc1ac5',
  [string]$WorkDir = "$env:TEMP\drag-lint-book-split-$PID"
)
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
try {
  if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
  if (-not (Test-Path $LibDb)) { Write-Host "SKIP: no library DB $LibDb" -ForegroundColor Yellow; exit 0 }
  $Exe = (Resolve-Path $Exe).Path
  $root = (Resolve-Path "$PSScriptRoot\..\..").Path
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  New-Item -ItemType Directory $WorkDir | Out-Null
  $bde = Join-Path $root 'convrules\BDE-to-FireDAC.rules'
  $dd  = Join-Path $root 'convrules\DataDB-to-FireDAC.rules'
  $pre = Join-Path $WorkDir 'pre-split.rules'
  Push-Location $root
  $preText = (git show "${PreRef}:convrules/BDE-to-FireDAC.rules") -join "`r`n"
  Pop-Location
  if (-not $preText) { Write-Host "FATAL: git show $PreRef failed" -ForegroundColor Red; exit 2 }
  [IO.File]::WriteAllText($pre, $preText + "`r`n", [Text.Encoding]::ASCII)

  function Copy-Fixture([string]$Name) {
    $d = Join-Path $WorkDir $Name
    Copy-Item (Join-Path $root 'tests\autotest\fixtures\bdesplit') $d -Recurse
    & $Exe index $d --db "$d.sqlite" 2>&1 | Out-Null
    return $d
  }
  function Apply([string]$Dir, [string]$Rules, [switch]$Write) {
    $a = @('convert-apply', '--unit', (Join-Path $Dir 'BdeSplitForm.pas'), '--rules', $Rules, '--db', "$Dir.sqlite", '--db', $LibDb, '--no-reindex', '--json')
    if ($Write) { $a += '--apply' }
    $o = (& $Exe @a 2>$null) -join "`n"
    $i = $o.IndexOf('{'); $j = $o.LastIndexOf('}')
    if ($i -lt 0 -or $j -le $i) { return $null }
    try { return ($o.Substring($i, $j - $i + 1) | ConvertFrom-Json) } catch { return $null }
  }
  function StripLine([string]$t) { return ($t -replace '^line \d+: ', '') }
  # Engine 1.36 echoes BOOK line numbers inside item text ("at line(s) 421, 424", "under #link at line 420")
  # and as the item line and file of warnings (file = the book); a split book renumbers them. Keep the COUNT of lines, drop the numbers.
  function BookLines([string]$t) {
    $t = [regex]::Replace($t, 'at line\(s\) ([\d, ]+)', { param($m) 'at line(s) x' + (($m.Groups[1].Value -split ',').Count) })
    return ($t -replace 'at line \d+', 'at line N')
  }
  # Q4b (deliberate, owner-accepted): the BDE book now carries '#migrate UpdateRecordTypes -> FilterChanges' INSIDE
  # the TTable/TQuery/TStoredProc blocks, so the engine applies it (migrate-applied) where the pre-split trailer was inert.
  # That one item kind is excluded from the A2 multiset and asserted separately in A4 / B4.
  # 1.38 (owner ruling D2, 2026-10-28): an identifier #migrate (file scope, or in a block with a uses unit) now RENAMES
  # in code, in the pre-split and the split books alike, and every site it does not rename is a migrate-check. The
  # books word those rules differently (the pre-split TDBScreenCursors typo, scoped forms), so every migrate item is
  # left out of A2 and compared in A3 / A3b.
  function ItemKeys($j) {
    @($j.items | Where-Object { $_.kind -ne 'migrate-check' -and $_.kind -ne 'migrate-applied' } | ForEach-Object {
      '{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}|{10}' -f $_.kind, $_.instance, $_.path, $_.value, $_.old_value, $_.field, $_.from_type, $_.to_type, $(if ($_.file -and $_.field -ne 'warnings') { Split-Path $_.file -Leaf } else { '' }), $(if ($_.field -eq 'warnings') { 0 } else { $_.line }), (BookLines (StripLine $_.text))
    })
  }
  function WarnKeys($j) { @($j.warnings | Where-Object { $_ -notmatch '#migrate ' } | ForEach-Object { StripLine $_ }) }
  function MigKeys($j) { @($j.items | Where-Object { $_.kind -eq 'migrate-applied' -and $_.text -notmatch 'UpdateRecordTypes' } | ForEach-Object { '{0}->{1}@{2}' -f $_.path, $_.value, $_.line }) }
  function UsesKeys($j) { @($j.uses | ForEach-Object { '{0}|{1}|{2}' -f $_.action, $_.unit, $_.section }) }
  function UnlKeys($j) { @($j.unlinked | ForEach-Object { '{0}|{1}|{2}|{3}' -f $_.from_type, $_.path, $_.sites, $_.instances }) }
  function Sig($j1, $j2) {
    # the multiset signature of the UNION of up to two results ($j2 may be $null)
    $items = @(ItemKeys $j1); $warn = @(WarnKeys $j1); $conv = @($j1.converted); $unl = @(UnlKeys $j1); $uses = @(UsesKeys $j1)
    if ($j2) { $items += ItemKeys $j2; $warn += WarnKeys $j2; $conv += @($j2.converted); $unl += UnlKeys $j2; $uses += UsesKeys $j2 }
    return [pscustomobject]@{
      Items = (($items | Sort-Object) -join "`n"); Warn = (($warn | Sort-Object) -join "`n"); Conv = (($conv | Sort-Object) -join "`n")
      Unl = (($unl | Sort-Object) -join "`n"); Uses = (($uses | Sort-Object -Unique) -join "`n"); N = $items.Count
    }
  }
  function SigDiff($a, $b) { $d = @(); foreach ($p in 'Items', 'Warn', 'Conv', 'Unl', 'Uses') { if ($a.$p -ne $b.$p) { $d += $p } }; return ($d -join ',') }

  # ---- A: dry runs ----------------------------------------------------------
  $fxA = Copy-Fixture 'fxA'
  $base = Apply $fxA $pre
  $jb   = Apply $fxA $bde
  $j2   = Apply $fxA $dd
  Check 'A0 the three dry runs answer (ok, apply/1)' (($base -and $base.ok) -and ($jb -and $jb.ok) -and ($j2 -and $j2.ok)) 'a dry run returned no JSON or ok=false'
  if ($base -and $jb -and $j2) {
    Check 'A1 the fixture converts all 8 From instances (positive control for the comparison)' ((@($base.converted).Count -eq 8) -and ((ItemKeys $base).Count -gt 40)) ('converted=' + @($base.converted).Count)
    $sb = Sig $base $null
    $su = Sig $jb $j2
    Check 'A2 BDE UNION Data.DB plans exactly the pre-split items / warnings / converted / unlinked / uses' ((SigDiff $sb $su) -eq '') ('differs in: ' + (SigDiff $sb $su))
    Check 'A4 expected difference (Q4b): only the split BDE book applies the UpdateRecordTypes member migrate, exactly once' ((@($base.items | Where-Object { $_.kind -eq 'migrate-applied' -and $_.text -match 'UpdateRecordTypes' }).Count -eq 0) -and (@($jb.items | Where-Object { $_.kind -eq 'migrate-applied' -and $_.text -match 'UpdateRecordTypes -> .*FilterChanges' }).Count -eq 1)) ''
    $mPre = @(MigKeys $base); $mSplit = @(MigKeys $jb) + @(MigKeys $j2)
    $lost = @($mPre | Where-Object { $mSplit -notcontains $_ })
    Check 'A3 identifier #migrate (1.38): the split books rename every site the pre-split book renames (non-vacuous: >= 15)' (($mPre.Count -ge 15) -and ($lost.Count -eq 0)) ('pre=' + $mPre.Count + ' lost: ' + ($lost -join ', '))
    Check 'A3b expected difference: only the split Data.DB book renames TDBScreenCursor (the pre-split line spells TDBScreenCursors, which resolves nowhere)' `
      ((@($mSplit | Where-Object { $_ -like 'TDBScreenCursor->TFDGUIxScreenCursor@*' }).Count -eq 1) -and (@($mPre | Where-Object { $_ -like 'TDBScreenCursor*' }).Count -eq 0)) ($mSplit -join ', ')

    # C1: a BDE book with one #link deleted must FAIL A2
    $t = [IO.File]::ReadAllText($bde)
    $link = "#link Active <- Active`r`n"
    $k = $t.IndexOf($link)
    if ($k -ge 0) {
      $broken = Join-Path $WorkDir 'bde-nolink.rules'
      [IO.File]::WriteAllText($broken, $t.Remove($k, $link.Length), [Text.Encoding]::ASCII)
      $jx = Apply $fxA $broken
      Check 'C1 control: a BDE book with one #link deleted is detected (A2 goes red)' ($jx -and ((SigDiff $sb (Sig $jx $j2)) -ne '')) ''
    } else { Check 'C1 control book built' $false 'no "#link Active <- Active" in the BDE book' }

    # C2: Book-2 with one TAutoIncField #link deleted must FAIL A2. (Dropping the To-unit from the header is no longer
    # visible in a dry run on engine 1.36: the unit is derived from the To class, so Uses is unchanged -- the old
    # control only went red through book line numbers, which A2 now ignores.)
    $t2 = [IO.File]::ReadAllText($dd)
    $hdr = '#convert Data.DB.TAutoIncField -> FireDAC.Comp.DataSet.TFDAutoIncField, FireDAC.Comp.DataSet'
    $lnk = "#link FieldName <- FieldName
"
    $h2 = $t2.IndexOf($hdr)
    $k2 = if ($h2 -ge 0) { $t2.IndexOf($lnk, $h2) } else { -1 }
    if ($k2 -ge 0) {
      $broken2 = Join-Path $WorkDir 'dd-nounit.rules'
      [IO.File]::WriteAllText($broken2, $t2.Remove($k2, $lnk.Length), [Text.Encoding]::ASCII)
      $jy = Apply $fxA $broken2
      Check 'C2 control: a Data.DB book with one TAutoIncField #link deleted is detected (A2 goes red)' ($jy -and ((SigDiff $sb (Sig $jb $jy)) -ne '')) ''
    } else { Check 'C2 control book built' $false 'no TAutoIncField #link FieldName in the Data.DB book' }
  }

  # ---- B: bytes -------------------------------------------------------------
  function PasNorm([string]$Path) {
    $o = foreach ($l in [IO.File]::ReadAllLines($Path)) {
      if ($l -match '^// drag-lint convert-apply ' -or $l -match '^//   backup: ') { continue }
      if ($l -match '^  .*FireDAC\.Comp\.') { '  ' + ((($l.Trim().TrimEnd(';') -split ',\s*') | Sort-Object) -join ', ') + ';' } else { $l }
    }
    return (($o -join "`n") -replace '\bFilterChanges\b', 'UpdateRecordTypes' -replace '\bTFDGUIxScreenCursor\b', 'TDBScreenCursor')  # A3b
  }
  function Run-Sequence([string]$Name, [string[]]$Books) {
    $d = Copy-Fixture $Name
    foreach ($b in $Books) {
      & $Exe index $d --db "$d.sqlite" 2>&1 | Out-Null
      $r = Apply $d $b -Write
      if (-not ($r -and $r.ok)) { return $null }
    }
    return $d
  }
  $dS = Run-Sequence 'fxS' @($pre)
  $dT = Run-Sequence 'fxT' @($bde, $dd)
  Check 'B0 both apply sequences ran' (($null -ne $dS) -and ($null -ne $dT)) ''
  if ($dS -and $dT) {
    $dfmS = [IO.File]::ReadAllText("$dS\BdeSplitForm.dfm"); $dfmT = [IO.File]::ReadAllText("$dT\BdeSplitForm.dfm")
    Check 'B1 .dfm after BDE book then Data.DB book is byte-identical to the pre-split single book' ($dfmS -eq $dfmT) 'dfm differs'
    Check 'B2 .pas identical after dropping audit stamps and sorting the FireDAC uses units' ((PasNorm "$dS\BdeSplitForm.pas") -eq (PasNorm "$dT\BdeSplitForm.pas")) 'pas differs'
    Check 'B4 expected difference (Q4b): only the split sequence rewrote UpdateRecordTypes to FilterChanges in the .pas' (([IO.File]::ReadAllText("$dT\BdeSplitForm.pas") -match 'Table1\.FilterChanges') -and ([IO.File]::ReadAllText("$dS\BdeSplitForm.pas") -notmatch 'FilterChanges')) ''
    Check 'B3 the TAutoIncField lost its BDE-format Origin; the unconverted TStringField kept its own' (($dfmT -notmatch 'DBDEMOS\.customer\.CustNo') -and ($dfmT -match "Origin = 'DBDEMOS\.customer\.Company'")) ''
    # C3: Book-2 without '#remove DFM: Origin' leaves the stale Origin
    $t3 = [IO.File]::ReadAllText($dd).Replace("`r`n#remove DFM: Origin`r`n", "`r`n")
    $noOrigin = Join-Path $WorkDir 'dd-noorigin.rules'
    [IO.File]::WriteAllText($noOrigin, $t3, [Text.Encoding]::ASCII)
    $dU = Run-Sequence 'fxU' @($bde, $noOrigin)
    Check 'C3 control: without "#remove DFM: Origin" in Book-2 the stale Origin survives (B1/B3 go red)' ($dU -and ((Get-Content "$dU\BdeSplitForm.dfm" -Raw) -match 'DBDEMOS\.customer\.CustNo')) ''
  }
}
catch { Write-Host ("FATAL: unhandled error: " + $_) -ForegroundColor Red; $script:Failed = $true }
finally {
  if (Test-Path -LiteralPath $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
