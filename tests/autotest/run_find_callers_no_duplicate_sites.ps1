<#
  run_find_callers_no_duplicate_sites.ps1 -- `query find-callers` must print
  each CALL SITE once, and must still print two sites that share a line.

  THE DEFECT (INBOX-find-callers-duplicate-rows.md, filed session 93).
  Measured on this repo's own index: `find-callers --name Migrate` printed
  **75 rows for 38 unique file:line:col** -- 38 of kind 'call' and 37 of kind
  'member-access'. Not a clean 2x, which is what made it look like an indexer
  defect in the original note.

  IT IS NOT AN INDEXER DEFECT, AND THAT MATTERS -- the note's proposed settling
  query would have concluded "duplicates in the table" and billed an extractor
  version bump (~5h15m re-parse of every database). The two rows are GENUINELY
  DISTINCT and both are correct: a QUALIFIED call `Obj.Run` emits one ref of
  kind 'call' and one of kind 'member-access' at the same position, which is
  exactly what `usages` groups by and what find-callers --resolved reads to tell
  a callback reach from an ordinary member call. An UNQUALIFIED call `Run` emits
  only the 'call' row -- hence 38 vs 37, and hence "some appear once, most
  twice".

  So the duplication is a RENDERING fault in one verb: the text form prints no
  kind, so two correct rows are indistinguishable to the reader. The fix is a
  POST-FILTER on the `find-callers` VERB that collapses refs sharing one
  file_id/line/col, exactly as DropRefsThatCannotBeCallers screens locally
  rather than changing the shared store query. Case 6 pins that.

  >>> THE POSITIVE CONTROL THIS GUARD EXISTS FOR. Two calls on ONE LINE is legal
  Pascal (`A.Run; B.Run;`) and they are two real call sites. A de-duplication
  keyed on file+LINE would silently delete one of them -- turning an
  over-report into an UNDER-report, which is the worse direction. Case 5
  asserts both survive. A dedup that passes cases 3 and 4 while failing case 5
  is a regression, not a fix.

  RED-CHECK: against the build at HEAD 63fe8514 (no post-filter), cases 3 and 4
  FAIL and every other case passes. Verified before the fix was written.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_find_callers_dupsites",
  [switch]$Quiet
)
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n, $ok, $d = '') {
  if ($Quiet) { if (-not $ok) { $script:fail = $true }; return }
  Write-Host ("  [{0}] {1}" -f (@('FAIL', 'PASS')[[int]$ok]), $n) -ForegroundColor (@('Red', 'Green')[[int]$ok])
  if (-not $ok) { if ($d) { Write-Host "        $d" -ForegroundColor DarkGray }; $script:fail = $true }
}
function W($p, $s) {
  [System.IO.File]::WriteAllText($p, (($s -replace "`r`n", "`n") -replace "`n", "`r`n"),
                                 (New-Object System.Text.UTF8Encoding($false)))
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path (Join-Path $WorkDir '_D-RAG') | Out-Null

W (Join-Path $WorkDir 'uProbe.pas') @'
unit uProbe;

interface

type
  TWorker = class
  public
    procedure Run;
    procedure Start;
  end;

procedure Go;

implementation

procedure TWorker.Run;
begin
end;

procedure TWorker.Start;
begin
  Run;
end;

procedure Go;
var
  A: TWorker;
  B: TWorker;
begin
  A := TWorker.Create;
  B := TWorker.Create;
  A.Run;
  A.Run; B.Run;
end;

end.
'@
W (Join-Path $WorkDir 'App.dpr') @'
program App;
uses
  uProbe in 'uProbe.pas';
begin
end.
'@

$db = Join-Path $WorkDir '_D-RAG\App.sqlite'
& $Exe index --project (Join-Path $WorkDir 'App.dpr') --db $db 2>&1 | Out-Null

# Line numbers are DERIVED from the fixture, never hardcoded.
$src = Get-Content (Join-Path $WorkDir 'uProbe.pas')
function LineOf($needle) {
  for ($i = 0; $i -lt $src.Count; $i++) { if ($src[$i] -like "*$needle*") { return $i + 1 } }
  return 0
}
$lnBare      = LineOf '  Run;'
$lnQualified = LineOf '  A.Run;'
$lnTwoCalls  = LineOf 'A.Run; B.Run;'
Check 'all three fixture lines located' `
  (($lnBare -gt 0) -and ($lnQualified -gt 0) -and ($lnTwoCalls -gt 0) -and ($lnQualified -ne $lnTwoCalls)) `
  "bare=$lnBare qualified=$lnQualified twocalls=$lnTwoCalls"

$out = (& $Exe query find-callers --name Run --db $db 2>&1)
$sites = @()
foreach ($l in $out) { if ("$l" -match 'uProbe\.pas:(\d+):(\d+)') { $sites += ('{0}:{1}' -f $Matches[1], $Matches[2]) } }
if (-not $Quiet) {
  Write-Host ("  find-callers rows (line:col): " + ($sites -join ', ')) -ForegroundColor DarkGray
  Write-Host ("  rows={0} unique={1}" -f $sites.Count, (@($sites | Sort-Object -Unique)).Count) -ForegroundColor DarkGray
}
function RowsOnLine($n) { return @($sites | Where-Object { $_ -like "$n`:*" }).Count }

Write-Host '== find-callers prints each call site once, and two sites on one line twice ==' -ForegroundColor Cyan

# 1 + 2. CONTROLS FIRST -- a dedup that deletes everything satisfies 3 and 4.
Check "CONTROL: the UNQUALIFIED call (line $lnBare) is still listed" ((RowsOnLine $lnBare) -ge 1) `
  'the post-filter removed a genuine unqualified call -- find-callers is now under-reporting'
Check "CONTROL: the QUALIFIED call (line $lnQualified) is still listed" ((RowsOnLine $lnQualified) -ge 1) `
  'the post-filter removed a genuine qualified call'

# 3. THE DEFECT -- one qualified call is one row, not a call + member-access pair.
Check "the QUALIFIED call (line $lnQualified) is listed EXACTLY ONCE" ((RowsOnLine $lnQualified) -eq 1) `
  ("listed {0} time(s): the 'call' and 'member-access' refs at one position are both being rendered" -f (RowsOnLine $lnQualified))

# 4. No position is printed twice, anywhere.
Check 'no file:line:col is printed more than once' `
  ($sites.Count -eq (@($sites | Sort-Object -Unique)).Count) `
  ("rows={0} unique={1}" -f $sites.Count, (@($sites | Sort-Object -Unique)).Count)

# 5. >>> POSITIVE CONTROL. Two real calls on one line must BOTH survive. A dedup
#    keyed on file+line instead of file+line+col fails exactly here.
Check "POSITIVE CONTROL: the line with TWO real calls (line $lnTwoCalls) reports TWO rows" `
  ((RowsOnLine $lnTwoCalls) -eq 2) `
  ("reported {0} row(s); two calls on one line are two distinct call sites and a line-keyed dedup would eat one" -f (RowsOnLine $lnTwoCalls))

# 6. >>> THE SHARED QUERY MUST STAY KIND-BLIND, i.e. the collapse is a POST-FILTER
#    on this one verb. If it were pushed down into FindCallersByName, rename would
#    stop rewriting every occurrence and find-callers --resolved would lose the
#    'call'-at-the-same-line signal it tells a callback reach apart with.
#
#    OBSERVED THROUGH `usages`, which renders one entry per REF: the store still
#    returning BOTH refs at the qualified site means both are still there to be
#    had. This guard takes NO position on whether `usages` should collapse them
#    in its own output -- that is a separate rendering question, deliberately out
#    of scope. If `usages` is ever given the same post-filter, this case must be
#    re-pointed at another kind-bearing reader, NOT deleted.
$usg = (& $Exe usages --name Run --db $db --format json 2>&1) -join "`n"
$usgSites = @()
foreach ($m in [regex]::Matches($usg, '"line":\s*(\d+),\s*"col":\s*(\d+)')) {
  $usgSites += ('{0}:{1}' -f $m.Groups[1].Value, $m.Groups[2].Value)
}
$usgAtQualified = @($usgSites | Where-Object { $_ -eq "$lnQualified`:5" }).Count
Check 'CONTROL: the store still returns BOTH refs at the qualified site (post-filter, not a store change)' `
  ($usgAtQualified -eq 2) `
  ("usages reported {0} ref(s) at ${lnQualified}:5, expected 2 -- the collapse was pushed into the shared store query" -f $usgAtQualified)

Write-Host ''
if ($script:fail) { Write-Host 'FIND-CALLERS-DUPSITES GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'FIND-CALLERS-DUPSITES GUARD: PASS' -ForegroundColor Green
exit 0
