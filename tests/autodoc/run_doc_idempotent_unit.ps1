<#
  run_doc_idempotent_unit.ps1 -- the UNIT-SCALE idempotency lock for `document`.

  run_doc_idempotent.ps1 already locks ONE symbol (--qname) in a two-symbol
  fixture. That assertion is real but narrow, and a corpus-scale convergence
  failure walked straight past it: over src/ the engine wrote 1,316 edits, and a
  SECOND pass still wanted more, which showed up as 514 `doc-drift: managed facts
  block is out of date` findings.

  THE OWNER'S ACCEPTANCE GATE (2026-08-10): "if autodoc can revert back to 0 for
  cases where there was no original doc from user, then the feature works
  correctly and every new autodoc run is a reproducible result."

  So: index -> document --unit --apply (pass A) -> RE-INDEX -> document --unit
  (pass B, DRY RUN) must report 0 edits, and applying pass B must leave the file
  byte-identical.

  The re-index between the passes is load-bearing: the store caches file content,
  and a stale index hands back pre-insert line numbers -- which is itself one of
  the two diagnosed causes of the corpus failure (facts computed against a DB
  that no longer matched disk).

  Fixture doc_idem_unit.pas deliberately contains NESTED routines, because
  documenting a nested routine inserts lines INSIDE its enclosing routine's
  implementation span, and the enclosing routine's own
  "N lines (full implementation)" fact is derived from that span
  (DRagLint.Doc.SymbolFacts: BodyLoc := ImplEndLine - ImplStartLine). A fact
  invalidated by its own emission cannot converge in one pass.

  If this FAILS, do NOT weaken it -- the whole point is that the narrow test
  passed while the engine was not reproducible.

  Run from a NEUTRAL CWD (C:\TEMP).
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\doc_idem_unit.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_docidem_unit'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'doc_idem_unit.pas'
$db     = Join-Path $scratch 'idemunit.sqlite'
Copy-Item $fixture $target -Force

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null

  # --- pass A: document the whole unit ---
  $a = & $exePath document --unit $target --db $db --apply --json 2>$null | Out-String
  $oa = $null; try { $oa = ($a | ConvertFrom-Json) } catch { $oa = $null }
  Check 'passA: produced edits' ($null -ne $oa -and [int]$oa.edits -gt 0)
  $bytesA = [IO.File]::ReadAllBytes($target)
  Get-ChildItem $scratch -Filter *.bak | Remove-Item -Force -ErrorAction SilentlyContinue

  # --- CRITICAL: re-index so facts are computed against the post-insert file ---
  & $exePath index $scratch --db $db 2>$null | Out-Null

  # --- pass B: DRY RUN. This is the gate. ---
  $b = & $exePath document --unit $target --db $db --json 2>$null | Out-String
  $ob = $null; try { $ob = ($b | ConvertFrom-Json) } catch { $ob = $null }
  Check 'passB parsed'            ($null -ne $ob)
  Check 'GATE passB: edits = 0 (reproducible)' ($null -ne $ob -and [int]$ob.edits -eq 0)

  if ($null -ne $ob -and [int]$ob.edits -ne 0) {
    Write-Host ("  pass B still wants {0} edit(s) -- applying to show WHAT moves:" -f $ob.edits) -ForegroundColor Yellow
    & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
    $bytesB2 = [IO.File]::ReadAllBytes($target)
    $tmpA = Join-Path $scratch '_passA.pas'
    [IO.File]::WriteAllBytes($tmpA, $bytesA)
    # Show the unstable lines; this is the diagnostic that names the offending fact.
    (Compare-Object (Get-Content $tmpA) (Get-Content $target) |
      Select-Object -First 12 |
      ForEach-Object { '    {0} {1}' -f $_.SideIndicator, $_.InputObject }) | Write-Host -ForegroundColor Yellow
  }

  # --- applying pass B must change nothing ---
  & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
  Get-ChildItem $scratch -Filter *.bak | Remove-Item -Force -ErrorAction SilentlyContinue
  $bytesB = [IO.File]::ReadAllBytes($target)
  Check 'IDEMPOTENT: bytes identical after pass B vs pass A' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$bytesA,[byte[]]$bytesB))
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
