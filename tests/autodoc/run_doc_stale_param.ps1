<#
  run_doc_stale_param.ps1 -- `document` STALE-PARAM handling.

  Fixture doc_stale_param.pas has a comment on Handle(X) carrying two params
  that are NOT in the signature:
    (a) MANAGED (AUTO_PARAM-marked, desc "TODO: describe."):
        /// <param name="Old">TODO: describe.</param><!-- drag-lint:auto param -->
    (b) HAND-TYPED (real desc):
        /// <param name="Gone">Real desc.</param>
  managed-vs-hand-typed is decided by desc CONTENT (empty / "TODO: describe." =
  managed; anything else = hand-typed).

  After document --apply, asserts:
    * the "Old" managed param line is GONE (regenerated away, not in the sig)
    * the "Gone" hand-typed param is KEPT with a "param no longer exists" flag
    * the real param X (hand desc "The kept param.") is preserved
    * a managed facts block was inserted

  Run from a NEUTRAL CWD (C:\TEMP).
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\doc_stale_param.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_docstale'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target  = Join-Path $scratch 'doc_stale_param.pas'
$db      = Join-Path $scratch 'stale.sqlite'
Copy-Item $fixture $target -Force

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null

  $ap = & $exePath document --qname doc_stale_param.Handle --db $db --apply 2>$null | Out-String
  Check 'apply: reports extended' ($ap -match 'doc: extended -- \d+ edit\(s\) applied')

  $txt = [IO.File]::ReadAllText($target)

  Check 'managed "Old" param DROPPED (not in signature)' `
    (-not ($txt -match '<param name="Old">'))
  Check 'hand-typed "Gone" param KEPT with "param no longer exists" flag' `
    ($txt -match '<param name="Gone">Real desc\.</param>\s*<!-- drag-lint: param no longer exists -->')
  Check 'real param "X" preserved (hand desc "The kept param.")' `
    ($txt.Contains('/// <param name="X">The kept param.</param>'))
  Check 'facts block inserted (Called from: doc_stale_param.UseHandle)' `
    ($txt.Contains('<!-- drag-lint:auto BEGIN -->') -and ($txt -match 'Called from:.*doc_stale_param\.UseHandle'))
  # ADP1: the dropped "Old" param carried the legacy managed 'TODO: describe.'
  # sentinel in the INPUT fixture (still a valid IsManagedDesc input -- see
  # fixtures\doc_stale_param.pas); since it is simply dropped (not in the
  # signature), no "TODO" text of any kind should survive in the OUTPUT.
  Check 'no "TODO" text anywhere in the output (legacy sentinel on "Old" was dropped, not re-emitted)' `
    ($txt -cnotmatch 'TODO')
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
