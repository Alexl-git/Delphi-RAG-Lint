<#
  run_allow_two_markers.ps1 -- `allow` on a line that carries TWO `// dl:ok` comments must keep
  each comment's reason attached to its own rule (INBOX-allow-double-marker-garbles-second-reason).

  THE DEFECT: InsertInto folded both comments into ONE (`// dl:ok a@h, b@h2 -- one; two`), so every
  rule on the line then claimed every reason.

  DESIGN POINT kept: a re-hash refreshes only the entry being allowed ("second finding, second
  click"); the neighbour keeps its own hash verbatim until it is allowed in turn.

  Cases (3 and 5 are controls):
    1. allow rule A: A re-hashed, comment B untouched byte for byte (reason two, @0000)
    2. both reasons survive verbatim, each exactly once, each beside its own rule
    3. CONTROL: a single-marker line is still re-hashed with its reason
    4. second click for rule B: B re-hashed too; both reasons still attached to their own rule
    5. CONTROL: a rule not on the line is appended to the LAST comment, earlier comments untouched
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe")
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

$WorkDir = Join-Path $env:TEMP ("allow_two_" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$pas = Join-Path $WorkDir 'uTwo.pas'
$src = @(
  'unit uTwo;', '', 'interface', '', 'procedure P(const A: array of string; out O: string);', '',
  'implementation', '', 'procedure P(const A: array of string; out O: string);', 'var', '  I: Integer;',
  '  S: string;', 'begin', "  S := '';", '  for I := 0 to High(A) do',
  '    S := S + A[I]; // dl:ok concat-in-loop@0000 -- reason one // dl:ok magic-literal@0000 -- reason two',
  '  O := S; // dl:ok concat-in-loop@0000 -- solo reason', 'end;', '', 'end.') -join "`r`n"
[IO.File]::WriteAllText($pas, $src + "`r`n", (New-Object System.Text.ASCIIEncoding))

function Line($n) { (Get-Content $pas)[$n - 1] }
function Allow($line, $rule) { & $Exe allow $pas --fix-line $line --fix-rule $rule --apply 2>&1 | Out-Null }

Allow 16 'concat-in-loop'
$l = Line 16
Check '1 rule A re-hashed' ($l -match 'concat-in-loop@(?!0000)[0-9a-f]{4} -- reason one') $l
Check '1 comment B untouched' ($l.EndsWith('// dl:ok magic-literal@0000 -- reason two')) $l
Check '2 each reason exactly once' (([regex]::Matches($l, 'reason one')).Count -eq 1 -and ([regex]::Matches($l, 'reason two')).Count -eq 1) $l
Allow 17 'concat-in-loop'
$l17 = Line 17
Check '3 CONTROL single marker re-hashed, reason kept' ($l17 -match 'concat-in-loop@(?!0000)[0-9a-f]{4} -- solo reason') $l17
Allow 16 'magic-literal'
$l = Line 16
Check '4 second click re-hashes B, reasons stay with their rule' (($l -match 'concat-in-loop@(?!0000)[0-9a-f]{4} -- reason one //') -and ($l -match 'magic-literal@(?!0000)[0-9a-f]{4} -- reason two$')) $l
Allow 16 'inherited-bare'
$l = Line 16
Check '5 CONTROL new rule goes to the last comment, first untouched' (($l -match '-- reason one // dl:ok magic-literal@[0-9a-f]{4}, inherited-bare@[0-9a-f]{4} -- reason two$')) $l

[IO.Directory]::Delete($WorkDir, $true)
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
