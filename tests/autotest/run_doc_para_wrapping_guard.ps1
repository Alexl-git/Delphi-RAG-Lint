<#
  run_doc_para_wrapping_guard.ps1 -- every managed FACT line is wrapped in
  <para>, and the two things that are not facts are not.

  WHY THIS FILE HAS TO EXIST, stated plainly because it is the whole point:
  P8 wrapped each fact line in <para>...</para>, which broke ~20 doc suites that
  match fact text directly. They were fixed by stripping the wrapper where each
  reads the block -- the right call, since they assert CONTENT and hundreds of
  expectations would otherwise have had to change. But that strip means those
  suites can no longer see the wrapper at all: delete the <para> emission
  tomorrow and every one of them still passes.

  So this is the positive control for a change that made twenty guards blind to
  it. Without it, P8 is asserted by nothing.

  THE ASK (owner, live IDE, 2026-08-24). The bare block ran the facts together:
  `Calls: uConfigurationService.LoadSettings Reads: FBackupSuffix` on one line.
  Tested before committing to it, with two methods side by side, one wrapped and
  one not -- the wrapped one broke onto three lines, the bare one did not.

  NOT WRAPPED, DELIBERATELY: <since> and <seealso>. They are real XML elements,
  not prose; nesting an element inside a paragraph would be wrong, and Help
  Insight renders them itself.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-para-wrapping"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function WriteAnsi($path, $text) {
  $t = ($text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($path, $t, (New-Object System.Text.ASCIIEncoding))
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $src | Out-Null
$file = Join-Path $src 'uPara.pas'
WriteAnsi $file @'
unit uPara;

interface

type
  TThing = class
  private
    FCount: Integer;
  public
    procedure Bump;
    function  Total: Integer;
  end;

procedure Driver;

implementation

procedure TThing.Bump;
begin
  FCount := FCount + 1;
end;

function TThing.Total: Integer;
begin
  Result := FCount;
end;

procedure Driver;
var
  T: TThing;
begin
  T := TThing.Create;
  T.Bump;
end;

end.
'@

$db = Join-Path $WorkDir 'para.sqlite'
& $Exe index $src --db $db 2>&1 | Out-Null
Check 'fixture indexed' (Test-Path $db)

& $Exe document --unit $file --db $db --apply --no-backup 2>&1 | Out-Null
$lines = [System.IO.File]::ReadAllLines($file)

# Only the MANAGED span counts: an author's own prose is none of this guard's
# business, and wrapping it would be a defect rather than a pass.
# EVERY managed span in the file, not just the first: the first block belongs to
# whichever declaration comes first, and the fact this guard names ('Called
# from:') belongs to a later one. Scanning one block let the emptiness of that
# block satisfy the wrapper check while proving nothing.
$spans = @()
$b = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match 'drag-lint:auto BEGIN') { $b = $i }
  elseif ($b -ge 0 -and $lines[$i] -match 'drag-lint:auto END') { $spans += ,@($b, $i); $b = -1 }
}
Check 'managed blocks were written' ($spans.Count -gt 0) "count=$($spans.Count)"
if ($spans.Count -eq 0) { Write-Host 'FAIL -- nothing to assert against.' -ForegroundColor Red; exit 1 }

$body = @()
foreach ($s in $spans) { for ($i = $s[0] + 1; $i -lt $s[1]; $i++) { $body += $lines[$i] } }
Check 'the managed blocks have fact lines' ($body.Count -gt 0) "count=$($body.Count)"
$firstBegin = $spans[0][0]

Write-Host ''
Write-Host 'THE CLAIM: every fact line is wrapped' -ForegroundColor Cyan
$unwrapped = @($body | Where-Object {
  $t = ($_ -replace '^\s*///\s?','').Trim()
  ($t -ne '') -and ($t -notmatch '^<para>.*</para>$') -and ($t -notmatch '^<(since|seealso)\b')
})
Check 'every prose fact line is <para>-wrapped' ($unwrapped.Count -eq 0) `
  $(if ($unwrapped.Count) { 'unwrapped: ' + ($unwrapped -join ' | ') } else { "$($body.Count) line(s)" })

# Name a fact we KNOW this fixture produces, so the check above cannot pass by
# the block being empty of the thing it claims to police.
$calledFrom = @($body | Where-Object { $_ -match 'Called from:' })
Check 'the block really does carry a Called from: fact' ($calledFrom.Count -ge 1) "count=$($calledFrom.Count)"
Check 'and that fact is wrapped'                       ($calledFrom -match '<para>Called from:.*</para>') ($calledFrom -join ' | ')

Write-Host ''
Write-Host 'CONTROLS: what must NOT be wrapped' -ForegroundColor Cyan
# <seealso> is a real element. If a future edit routes it through AppendFact it
# would become <para><seealso .../></para>, which is malformed doc XML.
$seeAlso = @($body | Where-Object { $_ -match '<seealso' })
if ($seeAlso.Count -gt 0) {
  Check 'CONTROL: <seealso> is NOT wrapped in <para>' (-not ($seeAlso -match '<para>\s*<seealso')) ($seeAlso -join ' | ')
} else {
  Write-Host '  [NOTE] this fixture emitted no <seealso>; the control cannot discriminate here.' -ForegroundColor DarkYellow
}

# The author's own lines live OUTSIDE the managed span and must be untouched.
$outside = @()
for ($i = 0; $i -lt $firstBegin; $i++) { if ($lines[$i] -match '^\s*///') { $outside += $lines[$i] } }
Check 'CONTROL: nothing outside the managed span was wrapped' (-not ($outside -match '<para>')) `
  "$($outside.Count) author line(s) above the block"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
