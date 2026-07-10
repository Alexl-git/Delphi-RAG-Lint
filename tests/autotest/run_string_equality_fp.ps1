<#
  run_string_equality_fp.ps1 -- regression for the string-equality-comparison
  FALSE POSITIVE on NON-string '=' comparisons (BACKLOG FP #3, 2026-07-10).

  THE BUG: the crude .scm rule (no-store path -- used by `lint` and, until the
  fix, by the IDE plugin's LSP diagnostics) is TYPE-BLIND. Its regex guards only
  suppress bare numeric/nil/bool/char literals, so it FIRES on comparisons whose
  operands are named constants / enums / integer-typed vars:
    if Key = VK_F10 then ...              (Key: Word  vs  an integer const)
    if B = kFlex then ...                 (B: an enum  vs  an enum const)
  Neither operand is a string, so the rule must NOT fire.

  THE FIX: on the STORE path, the precise type-aware built-in (CheckTypeAware)
  supersedes the .scm rule -- it flags '=' only when BOTH operands resolve to a
  string type. ResolveTypeCategory classifies intrinsics (Word -> integer,
  string -> tcString) WITHOUT needing the library DB. `lint-all --db` and
  `check-ast --db` already drop the .scm finding and run the type-aware rule;
  the plugin's LSP `BuildDiagnostics` was fixed to do the same when a store is
  present.

  This test asserts, on a fixture with the two non-string shapes PLUS a genuine
  string comparison (to prove the type-aware rule still fires when it should):
    - store path (check-ast --db): ZERO findings on the non-string lines, but
      the genuine `S1 = S2` (both string) STILL flagged;
    - no-store path (lint): the .scm rule fires on the non-string lines (this is
      the documented no-store limitation -- the plugin now uses the store path).

  Run from a neutral CWD.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-string-eq-fp"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $src | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# Fixture: two NON-string '=' comparisons (Word vs int const; enum vs enum const)
# plus one GENUINE string '=' comparison that SHOULD still be flagged.
$Body = @'
unit StrEqFp;

interface

const
  VK_F10 = 121;

type
  TBoxKind = (bkNone, bkFlex);

const
  Kind_Flex = bkFlex;

implementation

procedure Test(var Key: Word; B: TBoxKind; const S1, S2: string);
begin
  if Key = VK_F10 then Exit;        // Word vs integer const -- NOT a string compare
  if B = Kind_Flex then Exit;       // enum vs enum const   -- NOT a string compare
  if S1 = S2 then Exit;             // string vs string     -- GENUINE, must flag
end;

end.
'@
Write-Ascii (Join-Path $src 'StrEqFp.pas') $Body

$db = Join-Path $WorkDir 'seq.sqlite'
Write-Host 'Indexing fixture (--deep)' -ForegroundColor Cyan
$idx = & $Exe index $src --db $db --deep 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) "$($idx -join ' | ')"

$fixture = Join-Path $src 'StrEqFp.pas'

Push-Location $WorkDir
try {
  Write-Host ''
  Write-Host 'STORE path (check-ast --db): type-aware rule -- non-string compares must NOT fire' -ForegroundColor Cyan
  # check-ast exits non-zero when it reports findings (linter convention), so we
  # do NOT assert exit 0 -- we assert on the FINDINGS instead.
  $storeOut = (& $Exe check-ast $fixture --db $db 2>&1) -join "`n"
  # check-ast prints findings as `<file>(<line>,<col>): <sev> <rule>: ...`.
  $seLines = @()
  foreach ($line in ($storeOut -split "`n")) {
    if ($line -match 'string-equality-comparison') {
      if ($line -match '\((\d+),\d+\):') { $seLines += [int]$Matches[1] }
    }
  }
  # The Word-vs-int compare is on the 'if Key = VK_F10' line; the enum on 'if B ='.
  # Neither should appear. The genuine 'if S1 = S2' SHOULD appear.
  $keyLine  = (Select-String -Path $fixture -Pattern 'if Key = VK_F10').LineNumber
  $enumLine = (Select-String -Path $fixture -Pattern 'if B = Kind_Flex').LineNumber
  $strLine  = (Select-String -Path $fixture -Pattern 'if S1 = S2').LineNumber
  Check "store: NO string-equality FP on 'Key = VK_F10' (line $keyLine)" (-not ($seLines -contains $keyLine)) ("hits=" + ($seLines -join ','))
  Check "store: NO string-equality FP on 'B = Kind_Flex' (line $enumLine)" (-not ($seLines -contains $enumLine)) ("hits=" + ($seLines -join ','))
  Check "store: genuine 'S1 = S2' string compare STILL flagged (line $strLine)" ($seLines -contains $strLine) ("hits=" + ($seLines -join ','))

  Write-Host ''
  Write-Host 'NO-STORE path (lint): crude .scm is type-blind -- documents the limitation the plugin now avoids by using the store' -ForegroundColor Cyan
  $noStoreOut = (& $Exe lint $fixture 2>&1) -join "`n"
  $nsSe = ($noStoreOut -split "`n" | Where-Object { $_ -match 'string-equality-comparison' }).Count
  # This is the DOCUMENTED no-store limitation: the .scm fires on the non-string
  # lines. We assert it here so a future .scm tightening that also fixes the
  # no-store path is a deliberate, test-visible change (not a silent drift).
  Check 'no-store .scm still fires (documents the store-path-is-authoritative design)' ($nsSe -ge 1) "count=$nsSe"
} finally {
  Pop-Location
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
