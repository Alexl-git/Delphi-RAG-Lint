<#
  run_doc_returns_merge.ps1 -- free-function Overload fact + mined returns shown
  in the doc even alongside a hand-written <returns>.

  Fixture docret\docret.pas:
    * Pick        -- two unit-level overloads -> "Overload 1 of 2" / "2 of 2"
                     (free functions, not methods) and NO spurious "Calls: Pick".
    * Doubler     -- has a HAND-WRITTEN <returns> + Result:= X * 2. The tag is
                     preserved AND a managed "Returns: X * 2" fact line is added.
    * Flag        -- no doc, Result:= 'yes'/'no' -> the mined cases fill the
                     <returns> TAG ("Observed: ...") and there is NO fact line.

  Sequence: index -> document --unit --apply -> RE-INDEX -> document --unit --apply.
  Asserts the above + idempotency (run 2 byte-identical).

  Run from a NEUTRAL CWD (C:\TEMP).
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docret\docret.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_docret'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'docret.pas'
$db     = Join-Path $scratch 'docret.sqlite'
Copy-Item $fixture $target -Force

# Return the doc-comment block (list of /// lines) immediately preceding a decl.
function DocBlockAbove([string[]]$lines, [string]$declRegex) {
  $idx = -1
  for ($i=0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $declRegex) { $idx = $i; break } }
  if ($idx -lt 0) { return @() }
  $blk = New-Object System.Collections.Generic.List[string]
  for ($i = $idx - 1; $i -ge 0; $i--) { if ($lines[$i] -notmatch '^\s*///') { break }; $blk.Insert(0, $lines[$i]) }
  return ,$blk.ToArray()
}

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null
  & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
  Check 'apply #1: exit 0' ($LASTEXITCODE -eq 0)

  $lines = [IO.File]::ReadAllLines($target)

  # Pick overloads (free functions)
  $pickInt = (DocBlockAbove $lines '^function Pick\(A: Integer\)') -join "`n"
  $pickStr = (DocBlockAbove $lines '^function Pick\(const A: string\)') -join "`n"
  Check 'Pick(Integer) has an Overload line' ($pickInt -match 'Overload \d of 2')
  Check 'Pick(string) has an Overload line'  ($pickStr -match 'Overload \d of 2')
  Check 'no spurious self Calls: Pick'        (-not ($pickInt -match 'Calls:.*\bPick\b'))

  # Doubler: hand returns preserved + Returns fact line added
  $dbl = (DocBlockAbove $lines '^function Doubler\(') -join "`n"
  Check 'Doubler keeps its hand-written <returns>' ($dbl -match '<returns>The doubled value\.</returns>')
  Check 'Doubler gains a managed Returns: fact line' ($dbl -match 'Returns: X \* 2')

  # Flag: mined cases in the <returns> tag, NO fact line
  $flag = (DocBlockAbove $lines '^function Flag\(') -join "`n"
  Check 'Flag has Observed cases in the <returns> tag' ($flag -match [regex]::Escape('<returns><!-- drag-lint:auto -->') + 'Observed:.*</returns>')
  Check 'Flag has NO separate Returns: fact line'       (-not ($flag -match '///\s*Returns:'))

  # idempotency
  $bytes1 = [IO.File]::ReadAllBytes($target)
  & $exePath index $scratch --db $db 2>$null | Out-Null
  & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
  $bytes2 = [IO.File]::ReadAllBytes($target)
  Check 'IDEMPOTENT: file bytes identical after run 2 vs run 1' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$bytes1,[byte[]]$bytes2))
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
