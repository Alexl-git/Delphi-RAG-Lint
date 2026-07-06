<#
  run_doc_seealso.ps1 -- <seealso> doc-source (`document --unit ... --seealso`).

  Uses fixtures\docsee\see.pas: class TSvc whose DoA calls DoB(..) and DoC(..)
  (parenthesized so the body-scan registers the Calls fact). DoB/DoC are both
  DoA's resolved callees AND its siblings (same parent TSvc), so DoA's related
  set = {see.TSvc.DoB, see.TSvc.DoC}. The <seealso> list is deduped, sorted, and
  capped at SEEALSO_CAP = 5.

  Asserts (WITH --seealso):
    * DoA's managed block contains <seealso cref="...DoB"/> and <seealso cref="...DoC"/>.
    * The seealso crefs are in DETERMINISTIC (sorted) order (DoB before DoC).
    * The seealso list is CAPPED at 5 (never more than 5 <seealso> lines).
    * No cref is a '?'-tagged / unresolved / fabricated name.
  Asserts (WITHOUT --seealso):
    * DoA's managed block has NO <seealso> line at all (opt-in per IncludeSeeAlso).
  IDEMPOTENCY: a second --apply --seealso leaves the file BYTE-IDENTICAL.

  Run from a NEUTRAL CWD (C:\TEMP).
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docsee\see.pas')).Path

# Returns JUST DoA's own doc-comment block (the /// lines immediately preceding
# its declaration), so an assertion never bleeds into DoB/DoC's comments.
function Get-DoABlock($file) {
  $lines = [IO.File]::ReadAllLines($file)
  $idx = -1
  for ($i=0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*procedure DoA;') { $idx = $i; break } }
  if ($idx -lt 0) { return $null }
  $block = New-Object System.Collections.Generic.List[string]
  for ($i = $idx - 1; $i -ge 0; $i--) {
    if ($lines[$i] -notmatch '^\s*///') { break }
    $block.Insert(0, $lines[$i])
  }
  return [string]::Join("`n", $block.ToArray())
}

Push-Location C:\TEMP
try {
  # === Part A: WITH --seealso ===
  $scratch = Join-Path C:\TEMP 'draglint_docsee'
  if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
  New-Item -ItemType Directory -Path $scratch | Out-Null
  $target = Join-Path $scratch 'see.pas'
  $db     = Join-Path $scratch 'docsee.sqlite'
  Copy-Item $fixture $target -Force

  & $exePath index $scratch --db $db 2>$null | Out-Null
  & $exePath document --unit $target --db $db --apply --seealso 2>$null | Out-Null
  $ec1 = $LASTEXITCODE
  Check 'apply #1 (--seealso): exit 0' ($ec1 -eq 0)

  $doaBlock = Get-DoABlock $target
  Check 'DoA decl + doc-comment found' ($null -ne $doaBlock -and $doaBlock -ne '')
  Check 'DoA has managed facts block' ($doaBlock -match '<!-- drag-lint:auto BEGIN -->')
  Check 'DoA seealso cref DoB present' ($doaBlock -match '<seealso cref="see\.TSvc\.DoB"/>')
  Check 'DoA seealso cref DoC present' ($doaBlock -match '<seealso cref="see\.TSvc\.DoC"/>')

  # deterministic order: DoB's cref line precedes DoC's cref line.
  Check 'seealso order is sorted (DoB before DoC)' ($doaBlock -match '(?s)cref="see\.TSvc\.DoB".*?cref="see\.TSvc\.DoC"')

  # capped at 5: never more than SEEALSO_CAP <seealso> lines.
  $seeCount = ([regex]::Matches($doaBlock, '<seealso cref=')).Count
  Check 'seealso count <= 5 (SEEALSO_CAP)' ($seeCount -le 5)
  Check 'seealso count is exactly 2 (DoB,DoC)' ($seeCount -eq 2)

  # ground-truth: no '?'-tagged / unresolved cref ever appears.
  Check 'no ?-tagged cref' ($doaBlock -notmatch 'cref="[^"]*\?')

  # --- idempotency: second --apply --seealso leaves file byte-identical ---
  $before = [IO.File]::ReadAllBytes($target)
  & $exePath index $scratch --db $db 2>$null | Out-Null
  & $exePath document --unit $target --db $db --apply --seealso 2>$null | Out-Null
  $after = [IO.File]::ReadAllBytes($target)
  Check 'idempotent: file byte-identical on 2nd --seealso run' ([System.Linq.Enumerable]::SequenceEqual([byte[]]$before,[byte[]]$after))

  # === Part B: WITHOUT --seealso (opt-in gate) ===
  $scratch2 = Join-Path C:\TEMP 'draglint_docsee_off'
  if (Test-Path $scratch2) { Remove-Item $scratch2 -Recurse -Force }
  New-Item -ItemType Directory -Path $scratch2 | Out-Null
  $target2 = Join-Path $scratch2 'see.pas'
  $db2     = Join-Path $scratch2 'docsee_off.sqlite'
  Copy-Item $fixture $target2 -Force

  & $exePath index $scratch2 --db $db2 2>$null | Out-Null
  & $exePath document --unit $target2 --db $db2 --apply 2>$null | Out-Null
  $ec2 = $LASTEXITCODE
  Check 'apply (no --seealso): exit 0' ($ec2 -eq 0)

  $doaBlockOff = Get-DoABlock $target2
  Check 'DoA (no --seealso) still has managed block' ($doaBlockOff -match '<!-- drag-lint:auto BEGIN -->')
  Check 'DoA (no --seealso) has NO seealso line' ($doaBlockOff -notmatch '<seealso')
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
