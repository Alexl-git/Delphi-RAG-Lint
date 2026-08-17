<#
  run_lintall_order_stable_across_reindex.ps1 -- `lint-all` output must be
  byte-identical across a reindex of the SAME sources.

  WHY THIS EXISTS. Byte-identity of lint-all stdout is this repo's primary
  verification gate: every performance change this session was accepted or
  rejected on it. A gate that silently holds only WITHIN one index state is not
  the gate anyone thinks it is.

  Measured 2026-08-17 on ORM3, and it did not hold. Reindexing the same sources
  produced the same 14,764 findings and the same 2,161,951 bytes -- but a
  different SHA256. Sorted, the two reports were identical line for line; 61
  findings had simply MOVED (58 high-response, 2 low-cohesion, 1
  too-many-children).

  Cause: TClassMetrics.Run emitted in `Inv.Values` order. Inv is a
  TDictionary keyed by SYMBOL ID, so enumeration follows the hash layout, and a
  reindex reassigns ids. Fixed by sorting on (path, decl line, decl col, name) --
  source coordinates, which a reindex cannot move.

  WHAT THIS ASSERTS, and why it is a reindex rather than a sort check: asserting
  "the findings come out sorted" would pass on any stable order, including a
  wrong one, and would not notice a future rule that reintroduces
  dictionary-order emission somewhere else. Comparing two runs across a forced
  reparse tests the property that actually matters.

  POSITIVE CONTROL: the fixture must produce class-metrics findings at all. A
  fixture that trips none would make step 3 pass trivially -- which is exactly
  how this bug survived, since nothing had ever compared two runs across a
  reindex.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path

$scratch = Join-Path C:\TEMP 'draglint_orderstable'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $scratch 'src') | Out-Null

# THIRTY files, each with a base class + 11 subclasses, so `too-many-children`
# (default threshold 10) fires 30 times across 30 files.
#
# THE SIZE IS LOAD-BEARING, and the first draft got it wrong. With three files
# the dictionary's enumeration order happened to equal file order, so the suite
# passed against the UNFIXED build -- a guard that could not fail. Enumeration
# of a TDictionary<Int64,...> only diverges from insertion order once the hash
# table has grown and rehashed, so the fixture has to be big enough to scramble.
# Verified: at 30 files the unfixed build emits out of order.
$units = 1..30 | ForEach-Object { 'u{0:d2}' -f $_ }
foreach ($u in $units) {
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine("unit $u;")
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('interface')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('type')
  [void]$sb.AppendLine("  TBase$u = class")
  [void]$sb.AppendLine('  public')
  [void]$sb.AppendLine('    procedure Go;')
  [void]$sb.AppendLine('  end;')
  [void]$sb.AppendLine('')
  for ($i = 1; $i -le 11; $i++) { [void]$sb.AppendLine("  TKid$u$i = class(TBase$u)") ; [void]$sb.AppendLine('  end;') }
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('implementation')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine("procedure TBase$u.Go;")
  [void]$sb.AppendLine('begin')
  [void]$sb.AppendLine('end;')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('end.')
  $t = $sb.ToString() -replace "`r`n","`n" -replace "`n","`r`n"
  [System.IO.File]::WriteAllText((Join-Path $scratch "src\$u.pas"), $t, (New-Object System.Text.ASCIIEncoding))
}

$db = Join-Path $scratch 'order.sqlite'

Push-Location C:\TEMP
try {
  & $exePath index (Join-Path $scratch 'src') --db $db 2>&1 | Out-Null
  $out1 = (& $exePath lint-all --db $db --quiet 2>$null | Out-String)

  $n = ([regex]::Matches($out1, 'too-many-children')).Count
  Check 'POSITIVE CONTROL: the fixture trips class-metrics in many files' ($n -ge 25) `
        "too-many-children findings=$n (a small count makes the order checks vacuous)"

  # THE DISCRIMINATING CHECK. The reindex comparison below is the property that
  # matters, but whether a reindex actually reshuffles ids depends on the corpus;
  # emitting in source order is the invariant that guarantees it, and it fails
  # directly against the unfixed build.
  $cm = @($out1 -split "`r?`n" | Where-Object { $_ -match 'too-many-children' } |
          ForEach-Object { if ($_ -match '^(.+?\.pas):(\d+):') { [pscustomobject]@{ File=$Matches[1]; Line=[int]$Matches[2] } } })
  $sorted = @($cm | Sort-Object File, Line)
  $inOrder = $true
  for ($i = 0; $i -lt $cm.Count; $i++) {
    if (($cm[$i].File -ne $sorted[$i].File) -or ($cm[$i].Line -ne $sorted[$i].Line)) { $inOrder = $false; break }
  }
  Check 'class-metrics findings are emitted in source order (path, line)' $inOrder `
        $(if ($inOrder) { "$($cm.Count) finding(s) in order" } else {
            "first out-of-place at #$($i+1): got $(Split-Path $cm[$i].File -Leaf):$($cm[$i].Line), expected $(Split-Path $sorted[$i].File -Leaf):$($sorted[$i].Line)" })

  # --force-reparse rewrites every file, which is what reassigns the symbol ids
  # the old emit order depended on. Without it the ids are untouched and the
  # comparison could not fail even against the unfixed build.
  & $exePath index (Join-Path $scratch 'src') --db $db --force-reparse 2>&1 | Out-Null
  $out2 = (& $exePath lint-all --db $db --quiet 2>$null | Out-String)

  Check 'lint-all output is byte-identical across a reindex' ($out1 -ceq $out2) `
        $(if ($out1 -ceq $out2) { '' } else {
            $a = $out1 -split "`r?`n"; $b = $out2 -split "`r?`n"
            $moved = 0; for ($i=0; $i -lt [Math]::Min($a.Count,$b.Count); $i++) { if ($a[$i] -cne $b[$i]) { $moved++ } }
            "$moved line(s) differ; same multiset = $((($a|Sort-Object) -join '|') -ceq (($b|Sort-Object) -join '|'))" })
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
