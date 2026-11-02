<#
  run_large_magic_number_float.ps1 -- `large-magic-number` must report INTEGER
  literals only; a float literal is never reported.

  WHY. Owner IDE test 2026-11-02 (1.40): ORM3 COMMON\BASICS.PAS 389-391
  `AQLValueLimit : double = 0.1 ;` / `= 0.01;` reported "Integer literal --
  consider naming the constant" at a float. The query matched every
  literalNumber and its header said floats "fall through intentionally",
  contradicting both the message and the rule name. Float magic numbers belong
  to float-equality-comparison, not here.

  CONTROLS. The last case is the point: a bare integer `GInt := 12345;` in the
  SAME file must still fire. A fix keyed on "skip everything" passes the float
  cases and silently kills the rule.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_magic_float_$PID",
  [switch]$Quiet
)
try {
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

# Line numbers are what the assertions key on; keep them stable if you edit this.
$src = Join-Path $WorkDir 'uFloat.pas'
W $src @'
unit uFloat;

interface

implementation

var
  QLimitA : double = 0.1 ;
  QLimitB : double = 0.01;
  GReal: Double;
  GInt : Integer;

procedure Go;
begin
  GReal:= 0.01;
  GReal:= 1.5e3;
  GReal:= 3.14159;
  GInt := 12345;
  GInt := $DEADBEEF;
  GReal:= 12345.5;
end;

end.
'@

Write-Host '== large-magic-number: float literals ==' -ForegroundColor Cyan

$json = (& $Exe lint $src --rule large-magic-number --json 2>$null) -join "`n"
$i = $json.IndexOf('[')
if ($i -lt 0) { $i = $json.IndexOf('{') }
if ($i -lt 0) { Write-Host 'FATAL: no JSON from lint' -ForegroundColor Red; exit 2 }
$parsed = $null
try { $parsed = $json.Substring($i) | ConvertFrom-Json } catch { }
if ($null -eq $parsed) { Write-Host 'FATAL: lint JSON did not parse' -ForegroundColor Red; exit 2 }
$findings = @($parsed)
if (-not ($parsed -is [Array]) -and $parsed.PSObject.Properties.Name -contains 'findings') { $findings = @($parsed.findings) }
$findings = @($findings | Where-Object { $_.rule -eq 'large-magic-number' -or $_.ruleId -eq 'large-magic-number' -or $_.rule_id -eq 'large-magic-number' })
$lines = @($findings | ForEach-Object { if ($null -ne $_.line) { [int]$_.line } elseif ($null -ne $_.startLine) { [int]$_.startLine } else { [int]$_.start_line } })
if (-not $Quiet) { Write-Host ("  reported lines: " + (($lines | Sort-Object -Unique) -join ', ')) -ForegroundColor DarkGray }

Check 'initialised float var 0.1 / 0.01 do NOT fire (lines 8, 9)' (-not ($lines -contains 8) -and -not ($lines -contains 9)) 'a float const literal is reported'
Check 'float statement literals 0.01 / 1.5e3 / 3.14159 do NOT fire (lines 15-17)' (-not ($lines -contains 15) -and -not ($lines -contains 16) -and -not ($lines -contains 17)) 'a float literal is reported'
Check 'a large float 12345.5 does NOT fire (line 20)' (-not ($lines -contains 20)) 'a float literal with a large integer part is reported'
Check 'CONTROL: integer GInt := 12345 STILL fires (line 18)' ($lines -contains 18) 'integer literal no longer reported -- the rule was disabled, not scoped'

Write-Host ''
if ($script:fail) { Write-Host 'MAGIC-NUMBER-FLOAT GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'MAGIC-NUMBER-FLOAT GUARD: PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d in @("$env:TEMP\draglint_magic_float_$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
