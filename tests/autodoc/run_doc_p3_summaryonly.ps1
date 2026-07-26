<#
  run_doc_p3_summaryonly.ps1 -- Auto-Document Phase 3, Task 3 (review
  follow-up, Finding 3): a comment consisting ONLY of a human's blank
  <summary></summary> slot (no <param>, so Params.Count stays 0 too) must
  route through the REPAIR path, not the fresh-insert path.

  Before this fix, TParsedDoc.HasContent's OR-chain did not include
  HasSummaryTag/HasReturnsTag, so a bare <summary></summary> with nothing
  else parsed to HasContent = False (every OTHER field -- Summary itself,
  Remarks, ReturnsText, Params, Exceptions, Deprecated -- is also empty/
  zero). BuildForSymbol then wrongly took the FRESH path (treats the symbol
  as undocumented) and INSERTED A SECOND, separate comment block directly
  below the human's untouched line whenever there was something to insert
  (a mined <returns>, a facts block) -- non-destructive (it converges to one
  block on the NEXT run, once the repair path finally kicks in), but WRONG:
  visually it can look like one merged comment while being two separate
  operations, and outside a test the discrepancy plus the pointless extra
  edit is exactly the kind of thing that should not happen at all.

  The Task 3 report's original run_doc_p3_emptytags.ps1 fixture did NOT
  catch this: its HumanBlanks symbol ALSO carries a <param> tag, and it is
  the Params.Count > 0 entry that sets HasContent there, masking the gap.
  This fixture isolates the summary-only case.

  Fixture fixtures\docp3\summaryonly.pas: Echo3(AValue: Integer): Integer
  carries ONLY a blank <summary></summary> (no <param>, no <returns>); it
  has a mined return case (Result := AValue) and a caller (UseEcho3, for a
  Called-from fact), so BuildForSymbol has real content to insert.

  Drives `index` -> `document --qname summaryonly.Echo3 --apply` and asserts:
    1. Exactly ONE doc-comment block exists above the declaration (the
       repair path was taken -- no second block stacked below the human's
       line).
    2. The human's <summary></summary> line survives, byte-identical,
       unmarked.
    3. A managed <returns> (marked, mined Observed case) and a facts block
       (Called from:) are present INSIDE that SAME block.
    4. Idempotency: reindex + a second --apply reports edits=0/applied=false
       and leaves the file byte-identical.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\summaryonly.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_docp3summaryonly'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'summaryonly.pas'
$db     = Join-Path $scratch 'docp3summaryonly.sqlite'
Copy-Item $fixture $target -Force

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  $applyJson = (& $exePath document --qname summaryonly.Echo3 --db $db --apply --json 2>$null) -join "`n"
  Check 'document --qname --apply exits 0' ($LASTEXITCODE -eq 0)
  # v(ADP3 T3 review fix, Finding 3): must be "extended" (repair path, one
  # comment updated) -- NOT "created" (fresh path, which would mean a
  # SECOND block was inserted below the human's existing line).
  Check '1. action = extended (repair path, NOT a fresh second insert)' ($applyJson -match '"action":"extended"') $applyJson

  $lines = [IO.File]::ReadAllLines($target)
  # Exactly one contiguous ///-block directly above the declaration.
  $declIdx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^function Echo3\(AValue: Integer\): Integer;') { $declIdx = $i; break } }
  Check 'Echo3 decl found' ($declIdx -ge 0)
  $blockLines = @()
  $j = $declIdx - 1
  while ($j -ge 0 -and $lines[$j].TrimStart() -match '^///') { $blockLines = ,($lines[$j]) + $blockLines; $j-- }
  $block = $blockLines -join "`n"
  # The line immediately ABOVE the captured block must NOT also be a doc
  # line -- i.e. there is exactly one contiguous run, not two runs
  # separated by nothing (which the "second block" bug would produce as one
  # long contiguous run anyway) -- so instead assert directly on content:
  # exactly ONE <summary> tag and ONE <returns> tag in the whole file.
  $summaryCount = ([regex]::Matches($block, '<summary>')).Count
  $returnsCount = ([regex]::Matches($block, '<returns>')).Count
  Check '1. exactly one <summary> tag in Echo3''s block (no duplicate block)' ($summaryCount -eq 1) $block
  Check '1. exactly one <returns> tag in Echo3''s block (no duplicate block)' ($returnsCount -eq 1) $block

  Check '2. human''s <summary></summary> survives byte-identical, unmarked' `
    (($lines | Where-Object { $_.Trim() -eq '/// <summary></summary>' }).Count -eq 1)

  Check '3. managed <returns> present with the mined Observed case' `
    ($block -match [regex]::Escape('<returns><!-- drag-lint:auto -->') + 'Observed:\s*AValue\.')
  Check '3. facts block present with Called from:' `
    ($block -match '<!-- drag-lint:auto BEGIN -->' -and $block -match 'Called from:.*summaryonly\.UseEcho3')

  # --- 4. Idempotency ---
  $before = [IO.File]::ReadAllBytes($target)
  & $exePath index $scratch --db $db 2>$null | Out-Null
  $reApplyJson = (& $exePath document --qname summaryonly.Echo3 --db $db --apply --json 2>$null) -join "`n"
  Check '4. second apply reports edits=0'      ($reApplyJson -match '"edits":0')      $reApplyJson
  Check '4. second apply reports applied=false' ($reApplyJson -match '"applied":false') $reApplyJson
  $after = [IO.File]::ReadAllBytes($target)
  Check '4. idempotent: file byte-identical after reindex + 2nd apply' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$before,[byte[]]$after))
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
