<#
  run_lone_cr_line_accounting.ps1 -- docs\INBOX-a-lone-CR-shifts-every-reported-line-by-one.md

  A CR that is not part of a CRLF is a line terminator to Delphi, the RAD Studio
  IDE, VS Code and .NET. tree-sitter advances its row counter on LF ONLY, so
  before the fix every line the engine reported after such a byte was one lower
  than the editor showed.

  WHY THAT IS DATA DAMAGE, NOT A COSMETIC OFFSET. `allow --fix-line N` writes a
  review marker to the line the user read off the report, so it lands one line
  off -- the shape DataCopy reported in
  INBOX-drag-lint-allow-corrupts-the-source-it-annotates. Gutter icons and the
  Problems panel point at the wrong line, and review-marker-stale then hashes the
  wrong line, so a marker in such a file can never verify.

  THREE FIXTURES, AND THE THIRD IS THE ONE THAT MAKES THIS GUARD MEAN ANYTHING
  ---------------------------------------------------------------------------
  All three hold the same unit; only the terminator after `implementation`
  differs.

    clean.pas   CRLF only ................ editor lines 13 / 17
    lonecr.pas  one extra BARE CR ........ editor lines 14 / 18
    withlf.pas  one extra LF ............. editor lines 14 / 18

  `withlf` is the ORACLE. It is byte-identical to `lonecr` except that the
  disputed byte is 10 instead of 13, and the engine always numbered it correctly.
  So "lonecr must report what withlf reports" is a statement about the ONE byte
  under test and not about this fixture's layout -- if someone edits the unit
  body, both expected numbers move together and the assertion still holds.

  `clean` is the REGRESSION control: the normalisation must not shift a file that
  has no lone CR, and 13/17 pins that.

  MEASURED RED, THEN GREEN (2026-09-08). Against the pre-fix engine `lonecr`
  reported 13/17 -- i.e. identical to `clean`, one lower than the editor -- while
  `withlf` already reported 14/18. After the fix `lonecr` reports 14/18 and
  `clean` is unchanged. Both halves were observed, not assumed.

  WHY IT LINTS RATHER THAN INDEXES. `empty-procedure-body` is store-free, so this
  needs no database and no reindex, and it exercises the LINT path -- which is
  the path every harm listed above actually travels. The indexer has its own
  parse entry point (DRagLint.Parser.Delphi13.Parse) and gets the same transform;
  it is not observable without building an index, so it is not asserted here.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = ''
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

$exePath = (Resolve-Path $Exe).Path
if ($WorkDir -eq '') {
  $WorkDir = Join-Path ([IO.Path]::GetTempPath()) ("lonecr_" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
}
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

# One unit, written as an explicit line array so the expected line numbers below
# can be read off it by counting. Alpha's `end;` is line 15 and Beta's is 19;
# the finding is reported at the routine header, lines 13 and 17.
$lines = @(
  'unit LoneCrProbe;', '', 'interface', '', 'type', '  TProbe = class',
  '    procedure Alpha;', '    procedure Beta;', '  end;', '',
  'implementation', '', 'procedure TProbe.Alpha;', 'begin', 'end;', '',
  'procedure TProbe.Beta;', 'begin', 'end;', '', 'end.'
)
$body = $lines -join "`r`n"

function Write-Fixture([string]$Name, [string]$Text) {
  $p = Join-Path $WorkDir "$Name.pas"
  [IO.File]::WriteAllText($p, $Text + "`r`n", [Text.Encoding]::ASCII)
  return $p
}

$fClean  = Write-Fixture 'clean'  $body
$fLoneCr = Write-Fixture 'lonecr' ($body -replace "implementation`r`n", "implementation`r`n`r")
$fWithLf = Write-Fixture 'withlf' ($body -replace "implementation`r`n", "implementation`r`n`n")

# The fixtures are only meaningful if they really differ in the way described,
# so that is asserted rather than trusted -- a `-replace` that silently matched
# nothing would leave three identical files and every check below would pass.
function Count-LoneCR([string]$Path) {
  $b = [IO.File]::ReadAllBytes($Path)
  $n = 0
  for ($i = 0; $i -lt $b.Length; $i++) {
    if ($b[$i] -eq 13 -and ($i + 1 -ge $b.Length -or $b[$i + 1] -ne 10)) { $n++ }
  }
  return $n
}

Write-Host ''
Write-Host 'The fixtures are what this guard says they are' -ForegroundColor Cyan
Check 'clean.pas contains NO lone CR'      ((Count-LoneCR $fClean)  -eq 0) "found $(Count-LoneCR $fClean)"
Check 'lonecr.pas contains EXACTLY one'    ((Count-LoneCR $fLoneCr) -eq 1) "found $(Count-LoneCR $fLoneCr)"
Check 'withlf.pas contains NO lone CR'     ((Count-LoneCR $fWithLf) -eq 0) "found $(Count-LoneCR $fWithLf)"
Check 'lonecr and withlf are the same LENGTH (one byte differs, 13 vs 10)' `
  ((Get-Item $fLoneCr).Length -eq (Get-Item $fWithLf).Length) `
  "lonecr=$((Get-Item $fLoneCr).Length) withlf=$((Get-Item $fWithLf).Length)"
Check 'lonecr is exactly one byte longer than clean' `
  ((Get-Item $fLoneCr).Length -eq (Get-Item $fClean).Length + 1) `
  "lonecr=$((Get-Item $fLoneCr).Length) clean=$((Get-Item $fClean).Length)"

function Get-EmptyBodyLines([string]$Path) {
  $out = & $exePath lint $Path 2>$null
  return @($out |
    Select-String 'empty-procedure-body' |
    ForEach-Object { if ($_.Line -match ':(\d+):\d+\s') { [int]$Matches[1] } })
}

$lnClean  = Get-EmptyBodyLines $fClean
$lnLoneCr = Get-EmptyBodyLines $fLoneCr
$lnWithLf = Get-EmptyBodyLines $fWithLf

Write-Host ''
Write-Host 'The rule fires at all (without this, every line check below is vacuous)' -ForegroundColor Cyan
Check 'clean.pas yields two empty-procedure-body findings'  ($lnClean.Count  -eq 2) "got $($lnClean -join ',')"
Check 'lonecr.pas yields two'                               ($lnLoneCr.Count -eq 2) "got $($lnLoneCr -join ',')"
Check 'withlf.pas yields two'                               ($lnWithLf.Count -eq 2) "got $($lnWithLf -join ',')"

Write-Host ''
Write-Host 'Reported lines match the EDITOR' -ForegroundColor Cyan
Check 'clean.pas reports 13 and 17 (regression control -- no lone CR, nothing must shift)' `
  (($lnClean -join ',') -eq '13,17') "got $($lnClean -join ',')"
Check 'withlf.pas reports 14 and 18 (the ORACLE -- an ordinary LF, always numbered correctly)' `
  (($lnWithLf -join ',') -eq '14,18') "got $($lnWithLf -join ',')"
Check 'lonecr.pas reports 14 and 18 -- THE FIX' `
  (($lnLoneCr -join ',') -eq '14,18') `
  "got $($lnLoneCr -join ',') -- 13,17 is the PRE-FIX behaviour: tree-sitter did not count the bare CR as a row"

Write-Host ''
Write-Host 'The bare CR and the LF are treated identically' -ForegroundColor Cyan
Check 'lonecr and withlf report the SAME lines' `
  (($lnLoneCr -join ',') -eq ($lnWithLf -join ',')) `
  "lonecr=$($lnLoneCr -join ',') withlf=$($lnWithLf -join ',') -- these two files differ by ONE byte, 13 vs 10"
Check 'and they differ from clean by exactly one line each' `
  ($lnLoneCr.Count -eq 2 -and $lnClean.Count -eq 2 -and
   ($lnLoneCr[0] - $lnClean[0]) -eq 1 -and ($lnLoneCr[1] - $lnClean[1]) -eq 1) `
  "clean=$($lnClean -join ',') lonecr=$($lnLoneCr -join ',')"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
