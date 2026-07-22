<#
  run_doc_multiline.ps1 -- multi-line hand-written summary/param/returns must
  keep their /// prefix through document --apply, and re-runs must be stable.

  The merge step re-emits hand-written <summary>/<param>/<returns> descriptions.
  If a description spans several source lines, the doc parser keeps the interior
  newlines; emitting it as one line then leaves the continuation lines WITHOUT a
  /// prefix -- which (a) corrupts the source and (b) breaks the ///-block so a
  second run mis-parses it and injects/duplicates managed blocks.

  Fixture docml\mlprose.pas: Frob with a 3-line <summary>, 2-line <param>,
  2-line <returns>, 2-line <remarks>. Sequence:
    index -> document --unit --apply (run 1) -> RE-INDEX -> document --unit --apply (run 2)
  Asserts:
    * EVERY non-blank line of the doc comment starts with /// (no orphan
      continuation lines) -- checked over the whole file between the first ///
      and the decl.
    * the summary/param/returns continuation TEXT is present AND ///-prefixed.
    * exactly ONE <summary> tag and ONE managed AUTO_BEGIN block (no injection/
      duplication).
    * IDEMPOTENT: file bytes after run 2 == after run 1.

  Run from a NEUTRAL CWD (C:\TEMP).
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docml\mlprose.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_docml'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'mlprose.pas'
$db     = Join-Path $scratch 'docml.sqlite'
Copy-Item $fixture $target -Force

# Every line from the first ///-line down to (but not including) the function
# decl must be a ///-line (or blank). An orphan continuation line (doc prose
# without ///) is the bug.
function OrphanDocLines([string]$path) {
  $lines = [IO.File]::ReadAllLines($path)
  $orphans = @()
  $inDoc = $false
  foreach ($ln in $lines) {
    if ($ln -match '^\s*///') { $inDoc = $true; continue }
    if ($ln -match '^\s*(function|procedure|constructor|destructor|property)\b') { $inDoc = $false; continue }
    if ($inDoc -and $ln.Trim() -ne '') { $orphans += $ln }  # a non-/// non-blank line inside a doc run
  }
  return ,$orphans
}

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null
  & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
  Check 'apply #1: exit 0' ($LASTEXITCODE -eq 0)

  $src = [IO.File]::ReadAllText($target)
  $orphans = OrphanDocLines $target
  if ($orphans.Count -gt 0) { Write-Host ("  orphan line: {0}" -f $orphans[0]) -ForegroundColor DarkYellow }
  Check 'no orphan (non-///) doc continuation lines' ($orphans.Count -eq 0)

  # continuation fragments are present and each on a ///-prefixed line
  foreach ($frag in @('several source lines to exercise','two source lines to be sure','multiple source lines as well')) {
    $ln = ([IO.File]::ReadAllLines($target) | Where-Object { $_ -match [regex]::Escape($frag) })
    Check ("frag present and ///-prefixed: '$frag'") ($ln -and ($ln -match '^\s*///'))
  }

  # no injection / duplication
  Check 'exactly one <summary> tag'        (([regex]::Matches($src,'<summary>')).Count -eq 1)
  Check 'exactly one AUTO_BEGIN block'      (([regex]::Matches($src,'drag-lint:auto BEGIN')).Count -eq 1)

  $bytes1 = [IO.File]::ReadAllBytes($target)
  & $exePath index $scratch --db $db 2>$null | Out-Null
  & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
  $bytes2 = [IO.File]::ReadAllBytes($target)
  Check 'IDEMPOTENT: file bytes identical after run 2 vs run 1' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$bytes1,[byte[]]$bytes2))
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
