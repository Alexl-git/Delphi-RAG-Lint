<#
  run_doc_unit_stale_callee_refused.ps1 -- 152b DOCU: `document --unit Y` must not
  build facts from ANOTHER file's text at line numbers the index no longer
  describes.

  THE DEFECT (INT2 152b, BKL O3 regen)
  ------------------------------------
  `document --unit <u> --apply` was run unit after unit against ONE index. The
  first run rewrote Core.Model (doc blocks inserted, every implementation line
  moved down). A later unit's <exception cref> facts are mined from its callees'
  bodies: TDocFactsBuilder.MineRaisesDetailed reads the callee FILE AS IT IS NOW
  at the callee's INDEXED ImplStartLine..ImplEndLine. Core.Model's rows were
  stale, so the range landed on other text: tags citing the wrong Core.Model
  routines, or the right tag dropped. The engine printed only the generic
  "changed since this index was built" note and wrote the wrong facts.

  WHAT IS ASSERTED
  ----------------
    P1  positive control, fresh index: App's block carries
        <exception cref="EAlpha"> via Core.Alpha, exit 0.
    R1  Core.pas rewritten by `document --unit Core.pas --apply`, NO reindex:
        `document --unit App.pas` (dry run) is REFUSED -- exit 1, the message
        names Core.pas, no edit is rendered. (Base 1.50.0-alpha: exit 0 and the
        EAlpha tag is silently dropped.)
    R2  the same with --apply: refused, App.pas byte-identical.
    Q1  `document --qname App.UseAlpha` on the same stale index: refused.
    R3  after `index --project`, `document --unit App.pas` prints EXACTLY P1's
        edit (the run = "each unit after a reindex"), exit 0.
    C1  own-file staleness is NOT refused by this check: documenting Core.pas a
        second time with --apply still goes through ruling D-2's
        reindex-and-retry (no refusal text), exit 0.

  Run from a neutral cwd, pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
try {
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
$exePath = (Resolve-Path $Exe).Path

$scratch = Join-Path C:\TEMP "draglint_doc_stale_callee_$PID"
if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path $scratch | Out-Null
function WriteAscii([string]$Path, [string]$Text) {
  $t = $Text -replace "`r`n","`n" -replace "`n","`r`n"
  [System.IO.File]::WriteAllText($Path, $t, (New-Object System.Text.ASCIIEncoding))
}
WriteAscii (Join-Path $scratch 'Core.pas') @'
unit Core;

interface

uses SysUtils;

type
  EAlpha = class(Exception);
  EBeta = class(Exception);
  EGamma = class(Exception);

procedure Gamma(const A: Integer);
procedure Beta(const A: Integer);
procedure Alpha(const A: Integer);

implementation

procedure Gamma(const A: Integer);
begin
  if A > 0 then
    raise EGamma.Create('gamma');
end;

procedure Beta(const A: Integer);
begin
  if A > 0 then
    raise EBeta.Create('beta');
end;

procedure Alpha(const A: Integer);
begin
  if A > 0 then
    raise EAlpha.Create('alpha');
end;

end.
'@
WriteAscii (Join-Path $scratch 'App.pas') @'
unit App;

interface

procedure UseAlpha(const A: Integer);

implementation

uses Core;

procedure UseAlpha(const A: Integer);
begin
  Alpha(A);
end;

end.
'@
WriteAscii (Join-Path $scratch 'Fx.dpr') @'
program Fx;

uses
  Core in 'Core.pas',
  App in 'App.pas';

begin
end.
'@
$db   = Join-Path $scratch 'fx.sqlite'
$dpr  = Join-Path $scratch 'Fx.dpr'
$core = Join-Path $scratch 'Core.pas'
$app  = Join-Path $scratch 'App.pas'

function RunEngine([string[]]$EngineArgs) {
  $out = & $exePath @EngineArgs 2>&1 | Out-String
  return [pscustomobject]@{ Code = $LASTEXITCODE; Text = $out }
}
# The rendered edit only: from the first 'insert' line to the summary line.
function EditBlock([string]$Text) {
  $m = [regex]::Match($Text, '(?s)insert after line.*?(?=\r?\ndoc: )')
  if ($m.Success) { return $m.Value.Trim() } else { return '' }
}

$ix = RunEngine @('index','--project',$dpr,'--db',$db)
if ($ix.Code -ne 0) { throw "fixture index failed: $($ix.Text)" }

# P1 -- positive control on a fresh index.
$p1 = RunEngine @('document','--unit',$app,'--db',$db)
$p1Block = EditBlock $p1.Text
Check 'P1 fresh index: App block cites EAlpha via Core.Alpha' (($p1.Code -eq 0) -and ($p1Block -match '<exception cref="EAlpha">[^\r\n]*via Core\.Alpha')) "exit $($p1.Code)"
Check 'P1 fresh index: no other exception tag' (-not ($p1Block -match '<exception cref="E(Beta|Gamma)"'))

# Rewrite Core.pas -- its implementation lines all move down; the index is not refreshed.
$dc = RunEngine @('document','--unit',$core,'--db',$db,'--apply','--no-backup')
Check 'setup: Core.pas documented' (($dc.Code -eq 0) -and ($dc.Text -match 'edit\(s\) applied')) "exit $($dc.Code)"

# R1 -- dry run against the stale callee file is refused, nothing rendered.
$r1 = RunEngine @('document','--unit',$app,'--db',$db)
Check 'R1 stale callee: dry run exits 1' ($r1.Code -eq 1) "exit $($r1.Code)"
Check 'R1 stale callee: refusal names Core.pas' ($r1.Text -match 'REFUSED[^\r\n]*changed since[^\r\n]*Core\.pas') ($r1.Text.Trim() -split "`n" | Select-Object -Last 2)
Check 'R1 stale callee: no edit rendered' (-not ($r1.Text -match 'insert after line'))

# R2 -- --apply is refused and writes nothing.
$appBefore = [IO.File]::ReadAllBytes($app)
$r2 = RunEngine @('document','--unit',$app,'--db',$db,'--apply','--no-backup')
$appAfter = [IO.File]::ReadAllBytes($app)
Check 'R2 stale callee: --apply exits 1' ($r2.Code -eq 1) "exit $($r2.Code)"
Check 'R2 stale callee: App.pas byte-identical' ([Convert]::ToBase64String($appBefore) -eq [Convert]::ToBase64String($appAfter))

# Q1 -- the --qname form shares the miners and the refusal.
$q1 = RunEngine @('document','--qname','App.UseAlpha','--db',$db)
Check 'Q1 stale callee: --qname refused, exit 1' (($q1.Code -eq 1) -and ($q1.Text -match 'REFUSED[^\r\n]*Core\.pas')) "exit $($q1.Code)"

# R3 -- after the reindex the run equals the fresh-index run.
$ix2 = RunEngine @('index','--project',$dpr,'--db',$db)
if ($ix2.Code -ne 0) { throw "fixture reindex failed: $($ix2.Text)" }
$r3 = RunEngine @('document','--unit',$app,'--db',$db)
Check 'R3 after reindex: exit 0, edit identical to P1' (($r3.Code -eq 0) -and ($p1Block -ne '') -and ((EditBlock $r3.Text) -ceq $p1Block)) "exit $($r3.Code)"

# C1 -- own-file staleness keeps ruling D-2 (reindex + retry), never this refusal.
WriteAscii $core ([IO.File]::ReadAllText($core).Replace("implementation`r`n", "implementation`r`n`r`n// shifted`r`n"))
$c1 = RunEngine @('document','--unit',$core,'--db',$db,'--apply','--no-backup')
Check 'C1 own file stale: not refused by the callee check' (($c1.Code -eq 0) -and -not ($c1.Text -match 'changed since it was indexed')) "exit $($c1.Code)"

if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
if ($fail) { Write-Host 'run_doc_unit_stale_callee_refused: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_doc_unit_stale_callee_refused: ALL PASS' -ForegroundColor Green; exit 0
} catch { Write-Host "run_doc_unit_stale_callee_refused: ERROR $_" -ForegroundColor Red; exit 2 }
