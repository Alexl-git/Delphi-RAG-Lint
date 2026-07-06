<#
  run_doc_dedupe.ps1 -- regression lock for CalledFrom dedupe.

  Fixture doc_dedupe.pas: a public
    function Target(A: Integer): Integer;
  and ONE caller routine CallsTwice that invokes Target TWICE (two call sites in
  the same enclosing routine). FindCallersByName returns two refs with the same
  EnclosingSymbolId -> the same 'Display|Location' key -> the CalledFrom dedupe's
  Continue path fires. Without the dedupe, CallsTwice would appear TWICE in the
  'Called from:' line; with it, exactly ONCE.

  Asserts: after `document --qname doc_dedupe.Target --apply`, the 'Called from:'
  line names doc_dedupe.CallsTwice EXACTLY ONCE.

  Run from a NEUTRAL CWD (C:\TEMP) so no drag-lint-lint.json is picked up.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\doc_dedupe.pas')).Path

# Fresh scratch dir; keep the unit name so unit-name-matches-file stays quiet.
$scratch = Join-Path C:\TEMP 'draglint_docdedupe'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target  = Join-Path $scratch 'doc_dedupe.pas'
$db      = Join-Path $scratch 'dedupe.sqlite'
Copy-Item $fixture $target -Force

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null

  & $exePath document --qname doc_dedupe.Target --db $db --apply 2>$null | Out-Null
  Check 'apply: .bak written' (Test-Path "$target.bak")

  $txt = [IO.File]::ReadAllText($target)

  # The 'Called from:' fact line -- grab it so we can count caller occurrences.
  $calledLine = ($txt -split "`r?`n" | Where-Object { $_ -match 'Called from:' } | Select-Object -First 1)
  Check 'Called from: line present' ($null -ne $calledLine)

  # CallsTwice must appear EXACTLY ONCE on that line (dedupe collapsed the 2 sites).
  $matches = [regex]::Matches($calledLine, 'doc_dedupe\.CallsTwice')
  Check ("Called from: names CallsTwice exactly once (got {0})" -f $matches.Count) ($matches.Count -eq 1)
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
