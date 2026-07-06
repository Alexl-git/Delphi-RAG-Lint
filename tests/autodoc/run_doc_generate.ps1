<#
  run_doc_generate.ps1 -- TDD harness for `document` GENERATE (fresh comment).

  Fixture doc_generate.pas: a public UNDOCUMENTED
    function Add(A, B: Integer): Integer;
  plus a caller (UseAdd) so Called-from is non-empty. Copies the fixture to a
  scratch dir under C:\TEMP, indexes it to a scratch db, then runs
    document --qname doc_generate.Add --apply
  and asserts the inserted managed DocInsight comment contains:
    <summary>TODO: describe.</summary>, <param name="A">, <param name="B">,
    <returns>, and a <remarks> fenced block with "Called from:".

  Run from a NEUTRAL CWD (C:\TEMP) so no drag-lint-lint.json is picked up.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\doc_generate.pas')).Path

# Fresh scratch dir; keep the unit name so unit-name-matches-file stays quiet.
$scratch = Join-Path C:\TEMP 'draglint_docgen'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target  = Join-Path $scratch 'doc_generate.pas'
$db      = Join-Path $scratch 'gen.sqlite'
Copy-Item $fixture $target -Force

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null

  # Dry-run first: file must NOT change, action=created.
  $before = [IO.File]::ReadAllBytes($target)
  $j = & $exePath document --qname doc_generate.Add --db $db --json 2>$null | Out-String
  $o = $null; try { $o = ($j | ConvertFrom-Json) } catch { $o = $null }
  Check 'dry-run: json action = created' ($null -ne $o -and $o.action -eq 'created')
  Check 'dry-run: json applied = false'  ($null -ne $o -and $o.applied -eq $false)
  $after = [IO.File]::ReadAllBytes($target)
  Check 'dry-run: file NOT modified' ([System.Linq.Enumerable]::SequenceEqual([byte[]]$before,[byte[]]$after))

  # Apply: writes the comment + a .bak.
  $ap = & $exePath document --qname doc_generate.Add --db $db --apply 2>$null | Out-String
  Check 'apply: reports created + edits applied' ($ap -match 'doc: created -- \d+ edit\(s\) applied')
  Check 'apply: .bak written' (Test-Path "$target.bak")

  $txt = [IO.File]::ReadAllText($target)
  Check 'comment: <summary>TODO: describe.</summary> present' ($txt.Contains('/// <summary>TODO: describe.</summary>'))
  Check 'comment: <param name="A"> present' ($txt -match '///\s*<param name="A">')
  Check 'comment: <param name="B"> present' ($txt -match '///\s*<param name="B">')
  Check 'comment: <returns> present'         ($txt -match '///\s*<returns>')
  Check 'comment: <remarks> fenced block present' ($txt.Contains('/// <remarks>') -and $txt.Contains('<!-- drag-lint:auto BEGIN -->') -and $txt.Contains('<!-- drag-lint:auto END -->'))
  Check 'comment: Called from: doc_generate.UseAdd present' ($txt -match 'Called from:.*doc_generate\.UseAdd')
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
