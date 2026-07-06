<#
  run_doc_extend.ps1 -- `document` EXTEND: preserve hand prose, add managed bits.

  Fixture doc_extend.pas carries a hand-written comment on Compute(X, Y):
    /// <summary>Real prose.</summary>
    /// <param name="X">Real param desc.</param>
    /// <remarks>
    /// First remark line.
    /// Second remark line.
    /// </remarks>
  Only X is documented; Y has no <param>. A caller (UseCompute) gives facts.

  After document --apply, asserts:
    * "Real prose." preserved verbatim (summary untouched)
    * "Real param desc." preserved verbatim (X param untouched)
    * a <param name="Y"> managed tag (AUTO_PARAM sentinel) was ADDED
    * BOTH hand <remarks> lines survive, each with a /// prefix (Task 4 fix #1:
      multi-line prose is re-emitted line-by-line, never one bare-LF line)
    * a managed facts block (Called from:) was inserted inside <remarks>

  Run from a NEUTRAL CWD (C:\TEMP).
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\doc_extend.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_docext'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target  = Join-Path $scratch 'doc_extend.pas'
$db      = Join-Path $scratch 'ext.sqlite'
Copy-Item $fixture $target -Force

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null

  $ap = & $exePath document --qname doc_extend.Compute --db $db --apply 2>$null | Out-String
  Check 'apply: reports extended' ($ap -match 'doc: extended -- \d+ edit\(s\) applied')

  $txt   = [IO.File]::ReadAllText($target)
  $lines = [IO.File]::ReadAllLines($target)

  Check 'preserved: hand summary "Real prose." verbatim' ($txt.Contains('/// <summary>Real prose.</summary>'))
  Check 'preserved: hand param "Real param desc." verbatim (no AUTO_PARAM marker)' `
    ($txt.Contains('/// <param name="X">Real param desc.</param>') -and `
     ($txt -notmatch '///\s*<param name="X">Real param desc\.</param><!-- drag-lint:auto param -->'))
  Check 'added: managed <param name="Y"> with AUTO_PARAM sentinel' `
    ($txt -match '///\s*<param name="Y">TODO: describe\.</param><!-- drag-lint:auto param -->')

  # Both hand remark lines survive, EACH with a /// prefix (Task 4 fix #1).
  $hasLine1 = ($lines | Where-Object { $_.Trim() -eq '/// First remark line.' }).Count -eq 1
  $hasLine2 = ($lines | Where-Object { $_.Trim() -eq '/// Second remark line.' }).Count -eq 1
  Check 'multi-line prose: "/// First remark line." survives on its own line'  $hasLine1
  Check 'multi-line prose: "/// Second remark line." survives on its own line' $hasLine2

  Check 'inserted: managed facts block with Called from: doc_extend.UseCompute' `
    ($txt.Contains('<!-- drag-lint:auto BEGIN -->') -and ($txt -match 'Called from:.*doc_extend\.UseCompute'))
  Check 'structure: exactly one <remarks> open tag (prose + facts share one block)' `
    (([regex]::Matches($txt, '///\s*<remarks>')).Count -eq 1)
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
