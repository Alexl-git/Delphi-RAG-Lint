<#
  run_large_magic_number_date_args.ps1 -- `large-magic-number` must not fire on
  the arguments of a date/time constructor.

  WHY. DataCopy reported 16 findings on `EncodeDate(2026, 8, 11)`-shaped code.
  The "large integer literal" is 2026, a YEAR, and the rule's remedy is to name
  it -- but `YEAR_2026 = 2026` is a worse way of writing 2026. The owner
  accepted the exemption on 2026-08-31 with that framing, and noted it is not
  test-specific: a date literal is a date literal in production code too.

  HOW, and why it is not exclude_if_ancestor. That key tests an ancestor's node
  KIND. The kind here is `exprCall`, shared by every call in the language, so
  listing it would silence the rule almost everywhere. The distinguishing fact
  is WHICH routine is called -- node TEXT. Hence a new key,
  `exclude_if_argument_of`.

  >>> THE CONTROLS ARE THE POINT, AND ONE OF THEM IS THE WHOLE TEST.

  An exemption keyed on the VALUE (2026 is a plausible year, so skip it) would
  pass the positive case and silently kill the rule. Case 2 -- a bare
  `X := 2026;` in the SAME file must still fire -- is what separates the correct
  implementation from that one. A guard with only case 1 is satisfied by
  disabling the rule.

  Case 4 is the second trap: in `EncodeDate(2026, 8, Foo(5000))` the 5000 is an
  argument of Foo, not of EncodeDate, and must still fire. An implementation
  that walks ancestors to the root instead of stopping at the NEAREST argument
  list passes cases 1-3 and fails this one.

  RED-CHECK: against a build without exclude_if_argument_of, cases 1 and 3 fail
  (the date arguments are reported) and cases 2 and 4 pass. Verified.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_magic_date_args",
  [switch]$Quiet
)
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n, $ok, $d) {
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
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

# Every case in ONE file on purpose: the exempt and the non-exempt literals must
# be judged against the same rule set, same parse, same run. Line numbers are
# what the assertions key on, so keep them stable if you edit this.
$src = Join-Path $WorkDir 'uDateArgs.pas'
W $src @'
unit uDateArgs;

interface

implementation

uses
  System.SysUtils, System.DateUtils;

var
  GBase : TDateTime;
  GPlain: Integer  ;

function Foo(const AValue: Integer): Integer;
begin
  Result := AValue;
end;

procedure Go;
begin
  GBase  := EncodeDate(2026, 8, 11);
  GPlain := 2026;
  GBase  := EncodeDateTime(2027, 8, 11, 9, 0, 0, 0);
  GBase  := EncodeDate(2028, 8, Foo(5000));
end;

end.
'@

Write-Host '== large-magic-number: date-constructor arguments ==' -ForegroundColor Cyan

$json = (& $Exe lint $src --rule large-magic-number --json 2>$null) -join "`n"
$i = $json.IndexOf('[')
if ($i -lt 0) { $i = $json.IndexOf('{') }
if ($i -lt 0) { Write-Host 'FATAL: no JSON from lint' -ForegroundColor Red; exit 2 }
$parsed = $null
try { $parsed = $json.Substring($i) | ConvertFrom-Json } catch { }
if ($null -eq $parsed) { Write-Host 'FATAL: lint JSON did not parse' -ForegroundColor Red; exit 2 }

$findings = @()
if ($parsed -is [Array]) { $findings = @($parsed) }
elseif ($parsed.PSObject.Properties.Name -contains 'findings') { $findings = @($parsed.findings) }
else { $findings = @($parsed) }
$findings = @($findings | Where-Object { $_.rule -eq 'large-magic-number' -or $_.ruleId -eq 'large-magic-number' -or $_.rule_id -eq 'large-magic-number' })

function LinesOf { @($findings | ForEach-Object { if ($null -ne $_.line) { [int]$_.line } elseif ($null -ne $_.startLine) { [int]$_.startLine } else { [int]$_.start_line } }) }
$lines = LinesOf
if (-not $Quiet) { Write-Host ("  reported lines: " + (($lines | Sort-Object -Unique) -join ', ')) -ForegroundColor DarkGray }

# 1. EncodeDate arguments are exempt (line 21)
Check 'EncodeDate(2026, 8, 11) arguments do NOT fire' (-not ($lines -contains 21)) `
  'line 21 reported -- the year is being called a magic number'

# 2. >>> THE CONTROL. A bare literal in the SAME file must still fire (line 22).
#    Without this, switching the rule off satisfies case 1.
Check 'CONTROL: a bare X := 2026 in the same file STILL fires' ($lines -contains 22) `
  'line 22 not reported -- the exemption is silencing the rule, not scoping it'

# 3. EncodeDateTime is covered too (line 23). It lives in DateUtils rather than
#    SysUtils, which is why it is the one most likely to be left out.
Check 'EncodeDateTime arguments do NOT fire' (-not ($lines -contains 23)) `
  'line 23 reported -- EncodeDateTime was omitted from the list'

# 4. >>> THE SECOND CONTROL. Nested call: 5000 belongs to Foo, not EncodeDate.
Check 'CONTROL: a literal in a NESTED call inside EncodeDate STILL fires' ($lines -contains 24) `
  'line 24 not reported -- the climb went past the nearest argument list and over-exempted'

Write-Host ''
if ($script:fail) { Write-Host 'MAGIC-NUMBER-DATE-ARGS GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'MAGIC-NUMBER-DATE-ARGS GUARD: PASS' -ForegroundColor Green
exit 0
