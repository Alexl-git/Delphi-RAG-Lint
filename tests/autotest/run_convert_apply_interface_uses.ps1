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

# ---- MOVE: the To unit is ALREADY in the implementation uses only ----------
# An interface field needs it in the interface; left in the implementation the
# unit fails E2003 at the field. It is MOVED -- removed from the implementation
# clause and added to the interface one -- on both planner paths. The move is
# the #convert surface, so it is not a uses[] row (like the add itself).
$r = Apply 'IntfMove.pas' 'convert.rules' @('--apply', '--no-backup', '--format', 'json')
$t = Text 'IntfMove.pas'
$j = $null; try { $j = $r.Out.Substring($r.Out.IndexOf('{')) | ConvertFrom-Json } catch {}
Check 'M1 #convert-only book, LibB already in the implementation uses: exit 0' ($r.Code -eq 0) $r.Out
Check 'M2 ... LibB MOVED to the interface uses' ($t.Contains("interface$CRLF$CRLF" + "uses$CRLF  Classes, LibA, LibB;$CRLF")) $t
Check 'M3 ... and removed from the implementation uses (ImplU kept), exactly once in the file' `
  ($t.Contains("implementation$CRLF$CRLF" + "uses$CRLF  ImplU;$CRLF") -and (([regex]::Matches($t, '\bLibB\b')).Count -eq 1)) $t
Check 'M4 ... no uses[] row for the move (it is the #convert surface)' (($null -ne $j) -and (@($j.uses).Count -eq 0)) $r.Out
$r = Apply 'IntfMoveR.pas' 'convertuse.rules' @('--apply', '--no-backup')
$t = Text 'IntfMoveR.pas'
Check 'M5 book with #use: LibB moved to the interface, ExtraU added to the implementation beside ImplU' `
  (($r.Code -eq 0) -and $t.Contains("uses$CRLF  Classes, LibA, LibB;$CRLF") -and $t.Contains("uses$CRLF  ImplU, ExtraU;$CRLF") -and `
   (([regex]::Matches($t, '\bLibB\b')).Count -eq 1)) ($r.Out + "`n" + $t)
$r = Apply 'IntfMoveSolo.pas' 'convert.rules' @('--apply', '--no-backup')
$t = Text 'IntfMoveSolo.pas'
Check 'M6 LibB was the implementation clause''s only entry: the clause goes, LibB is in the interface' `
  (($r.Code -eq 0) -and $t.Contains("uses$CRLF  Classes, LibA, LibB;$CRLF") -and -not ($t -match '(?s)implementation.*\buses\b')) ($r.Out + "`n" + $t)

# a move whose implementation entry sits in a {$IF...} region cannot be done
# safely: the existing conditional-entry refusal fires, nothing is written
$hM = (Get-FileHash (P 'IntfMoveIf.pas')).Hash
$r = Apply 'IntfMoveIf.pas' 'convert.rules' @('--apply', '--no-backup')
Check 'M7 move of a {$IFDEF}-guarded implementation entry: REFUSED (exit 1) with the conditional-entry reason' `
  (($r.Code -eq 1) -and ($r.Out -match ('(?m)^REFUSED: ' + [regex]::Escape('IntfMoveIf.pas: "LibB" sits inside a conditional ({$IF...}) region of the implementation uses clause -- unit rules not applied to this unit') + '\r?$'))) $r.Out
Check 'M8 ... IntfMoveIf.pas byte-identical' ((Get-FileHash (P 'IntfMoveIf.pas')).Hash -eq $hM)
# ---- PIN: the dmToolStats shape (an interface unit rule + an interface field)
# 1.21.1 planned dmToolStats (BDE-to-FireDAC.rules) at 40 edits, 1.23.0 at 38:
# the interface clause was already rewritten for '#unuse DBTables', and the
# FireDAC adds used to be a SECOND rewrite of the implementation clause
# (delete + insert = the 2 edits) -- which also left the TFDTable fields
# undeclared (E2003). Now the adds ride the interface rewrite. Same shape here:
# 1.22.0 planned 7 edits for IntfFormU, this plan is 5, and the implementation
# clause (lines 15..16) is not touched.
$r = Apply 'IntfFormU.pas' 'convertunuse.rules' @('--format', 'json')
$j = $null; try { $j = $r.Out.Substring($r.Out.IndexOf('{')) | ConvertFrom-Json } catch {}
Check 'P1 #unuse OldU (interface) + interface field: 5 edits planned (dfm 2, retype 1, ONE interface clause rewrite 2)' `
  (($r.Code -eq 0) -and ($null -ne $j) -and ($j.edits_count -eq 5)) $r.Out
$r = Apply 'IntfFormU.pas' 'convertunuse.rules'
Check 'P2 text plan: no edit of the implementation clause (lines 15..16)' (($r.Code -eq 0) -and -not ($r.Out -match 'delete lines 15\.\.16')) $r.Out
$r = Apply 'IntfFormU.pas' 'convertunuse.rules' @('--apply', '--no-backup')
$t = Text 'IntfFormU.pas'
Check 'P3 --apply: interface uses is Classes, LibA, LibB (OldU gone), implementation uses ImplU untouched' `
  (($r.Code -eq 0) -and $t.Contains("uses$CRLF  Classes, LibA, LibB;$CRLF") -and $t.Contains("implementation$CRLF$CRLF" + "uses$CRLF  ImplU;$CRLF")) ($r.Out + "`n" + $t)

# ---- the converted units compile -------------------------------------------
[IO.File]::WriteAllText((P 'P.dpr'), (@(
  'program P;', '', 'uses', '  IntfForm, ImplForm, IntfFormR, ImplFormR, IntfMove, IntfMoveR, IntfMoveSolo, IntfFormU;', '',
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
