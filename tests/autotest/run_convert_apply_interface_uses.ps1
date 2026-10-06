<#
  run_convert_apply_interface_uses.ps1 -- convert-apply puts the To type's unit
  into the INTERFACE uses when the retyped field is declared in the interface
  section (C13 a, 1.23.0-alpha).

  THE DEFECT. Both uses planners hard-coded the implementation section:
  TFindUnitRefactoring.Build (the no-unit-rules path) chose the implementation
  uses whenever the unit had one, and PlanUnitRules (the unit-rules path) did
  the same for a #convert block's adds. A form unit declares its component
  fields in the interface, so a unit WITH an implementation uses clause got
  'btnTop: TDstBtn;' in the interface and TDstBtn's unit in the implementation
  -- E2003 Undeclared identifier at the field. PlanFieldRetype had the field
  symbol's Section and discarded it.

  THE CONTRACT this guard pins, on BOTH planner paths:
    * field declared in the interface  -> the To unit goes to the interface uses
      (appended after its last entry); the implementation uses is untouched.
    * field declared in the implementation (a class in the implementation
      section) -> the To unit stays in the implementation uses, as before.
    * unit-rules path: a #use in the same book still lands in the
      implementation uses -- only the #convert surface's add moves.
    * every converted unit compiles with dcc64 (the real check: before the fix
      the interface fixtures fail E2003).

  Fixtures live in tests\autotest\fixtures\intfuses and are COPIED to a $PID
  scratch folder, indexed into a scratch --db there. Nothing shared is touched.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_convert_apply_intf_uses_$PID",
  [string]$RsVars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
)
try {
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check($n,$ok,$d=''){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir -Force | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'fixtures\intfuses\*') $WorkDir

$db = Join-Path $WorkDir 'fx.sqlite'
& $Exe index $WorkDir --db $db 2>&1 | Out-Null
Check 'V the fixture index was built' (Test-Path $db)

function P([string]$n) { return (Join-Path $WorkDir $n) }
function Text([string]$n) { return [IO.File]::ReadAllText((P $n)) }
function Apply([string]$Unit, [string]$Rules, [string[]]$Extra = @()) {
  $o = (& $Exe @(@('convert-apply', '--unit', (P $Unit), '--rules', (P $Rules), '--db', $db) + $Extra) 2>&1) -join "`n"
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}
$CRLF = "`r`n"

# ---- path 1: no unit rules (TFindUnitRefactoring.Build) ---------------------
$r = Apply 'IntfForm.pas' 'convert.rules' @('--apply', '--no-backup')
$t = Text 'IntfForm.pas'
Check 'A1 interface field, #convert-only book: --apply exits 0' ($r.Code -eq 0) $r.Out
Check 'A2 ... LibB lands in the INTERFACE uses' ($t.Contains("interface$CRLF$CRLF" + "uses$CRLF  Classes, LibA, LibB;$CRLF")) $t
Check 'A3 ... the implementation uses is untouched' ($t.Contains("implementation$CRLF$CRLF" + "uses$CRLF  ImplU;$CRLF")) $t
Check 'A4 ... the field was retyped' ($t -match 'btnTop: TDstBtn;') $t

$r = Apply 'ImplForm.pas' 'convert.rules' @('--apply', '--no-backup')
$t = Text 'ImplForm.pas'
Check 'B1 implementation field, #convert-only book: --apply exits 0' ($r.Code -eq 0) $r.Out
Check 'B2 ... LibB stays in the IMPLEMENTATION uses (control)' ($t.Contains("uses$CRLF  ImplU, LibB;$CRLF")) $t
Check 'B3 ... the interface uses is untouched' ($t.Contains("uses$CRLF  Classes, LibA;$CRLF")) $t

# ---- path 2: unit rules in the book (PlanUnitRules) -------------------------
$r = Apply 'IntfFormR.pas' 'convertuse.rules' @('--apply', '--no-backup')
$t = Text 'IntfFormR.pas'
Check 'C1 interface field, book with #use: --apply exits 0' ($r.Code -eq 0) $r.Out
Check 'C2 ... LibB lands in the INTERFACE uses' ($t.Contains("interface$CRLF$CRLF" + "uses$CRLF  Classes, LibA, LibB;$CRLF")) $t
Check 'C3 ... #use ExtraU still lands in the IMPLEMENTATION uses' ($t.Contains("uses$CRLF  ImplU, ExtraU;$CRLF")) $t
Check 'C4 ... LibB appears exactly once' (([regex]::Matches($t, '\bLibB\b')).Count -eq 1) $t

$r = Apply 'ImplFormR.pas' 'convertuse.rules' @('--apply', '--no-backup')
$t = Text 'ImplFormR.pas'
Check 'D1 implementation field, book with #use: --apply exits 0' ($r.Code -eq 0) $r.Out
Check 'D2 ... LibB and ExtraU both in the IMPLEMENTATION uses (control)' ($t.Contains("uses$CRLF  ImplU, ExtraU, LibB;$CRLF") -or $t.Contains("uses$CRLF  ImplU, LibB, ExtraU;$CRLF")) $t
Check 'D3 ... the interface uses is untouched' ($t.Contains("uses$CRLF  Classes, LibA;$CRLF")) $t

# ---- the converted units compile -------------------------------------------
[IO.File]::WriteAllText((P 'P.dpr'), (@(
  'program P;', '', 'uses', '  IntfForm, ImplForm, IntfFormR, ImplFormR;', '',
  'begin', 'end.') -join $CRLF) + $CRLF, [Text.Encoding]::ASCII)
New-Item -ItemType Directory (P 'bin'), (P 'dcu') -Force | Out-Null
$bat = P 'compile.bat'; $log = P 'compile.log'
[IO.File]::WriteAllText($bat, (@('@echo off', "call `"$RsVars`"", "cd /d `"$WorkDir`"",
  "dcc64 -Q -B -NSSystem -E`"$WorkDir\bin`" -NU`"$WorkDir\dcu`" P.dpr", 'echo BUILD_EXITCODE=%ERRORLEVEL%') -join $CRLF), [Text.Encoding]::ASCII)
Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $log -RedirectStandardError "$log.err" -NoNewWindow -Wait | Out-Null
$cl = Get-Content $log -Raw -ErrorAction SilentlyContinue
$errLines = @(($cl -split "`r?`n") | Where-Object { $_ -match 'Error|Fatal' })
Check 'J1 every converted unit compiles with dcc64 (private -E/-NU)' (($cl -match 'BUILD_EXITCODE=0') -and ($errLines.Count -eq 0)) ($errLines -join ' | ')

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_convert_apply_intf_uses_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
