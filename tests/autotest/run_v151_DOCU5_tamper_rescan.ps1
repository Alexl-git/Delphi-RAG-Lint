<#
  run_v151_DOCU5_tamper_rescan.ps1 -- v151 DOCU5 (owner ruling OQ5): when a file's
  timestamp+size say "unchanged" but the facts the index stored disagree with the
  source text, the document verbs rescan BOTH files (the documented file and the
  file its facts were read from), print a WARN on stderr, then run.

  Same-size, mtime-restored edits (a rename that keeps the byte count):
    P1  positive control, untouched fixture: no WARN, exit 0.
    T1  Core.pas tampered (EAlpha -> EAlphX): `document --unit App.pas` prints a
        WARN naming Core.pas, exit 0 (base: silently runs on stale facts).
    T2  after T1 the index agrees with the source: a second run prints no WARN.
    T4  --qname form on a tampered callee WARNs too.
    T3  own file tampered (UseAlpha -> UseAlphb): WARN naming App.pas, exit 0.
  Run from a neutral cwd, pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = '')
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }
try {
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP "draglint_v151_docu5_$PID"
if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path $scratch | Out-Null
function WriteAscii([string]$Path, [string]$Text) {
  $t = $Text -replace "`r`n","`n" -replace "`n","`r`n"
  [System.IO.File]::WriteAllText($Path, $t, (New-Object System.Text.ASCIIEncoding))
}
# same-size rewrite, original mtime put back: the stamp fast path cannot see it
function Tamper([string]$Path, [string]$From, [string]$To) {
  $when = (Get-Item $Path).LastWriteTimeUtc
  $txt = [IO.File]::ReadAllText($Path)
  if ($From.Length -ne $To.Length) { throw 'tamper must keep the size' }
  [IO.File]::WriteAllText($Path, $txt.Replace($From, $To), (New-Object System.Text.ASCIIEncoding))
  (Get-Item $Path).LastWriteTimeUtc = $when
}
WriteAscii (Join-Path $scratch 'Core.pas') @'
unit Core;

interface

uses SysUtils;

type
  EAlpha = class(Exception);

procedure Alpha(const A: Integer);

implementation

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
$db = Join-Path $scratch 'fx.sqlite'; $dpr = Join-Path $scratch 'Fx.dpr'
$core = Join-Path $scratch 'Core.pas'; $app = Join-Path $scratch 'App.pas'
function RunEngine([string[]]$EngineArgs) {
  $out = & $exePath @EngineArgs 2>&1 | Out-String
  return [pscustomobject]@{ Code = $LASTEXITCODE; Text = $out }
}
$ix = RunEngine @('index','--project',$dpr,'--db',$db)
if ($ix.Code -ne 0) { throw "fixture index failed: $($ix.Text)" }

$p1 = RunEngine @('document','--unit',$app,'--db',$db)
Check 'P1 untouched: exit 0, no WARN' (($p1.Code -eq 0) -and -not ($p1.Text -match 'WARN')) "exit $($p1.Code)"

Tamper $core 'EAlpha' 'EAlphX'
$t1 = RunEngine @('document','--unit',$app,'--db',$db)
Check 'T1 callee tampered: exit 0' ($t1.Code -eq 0) "exit $($t1.Code)"
Check 'T1 callee tampered: WARN names Core.pas' ($t1.Text -match 'WARN[^\r\n]*Core\.pas') ($t1.Text.Trim() -split "`n" | Select-Object -First 3)
$t2 = RunEngine @('document','--unit',$app,'--db',$db)
Check 'T2 after rescan: no WARN' (($t2.Code -eq 0) -and -not ($t2.Text -match 'WARN')) "exit $($t2.Code)"

Tamper $core 'EAlphX' 'EAlphY'
$t4 = RunEngine @('document','--qname','App.UseAlpha','--db',$db)
Check 'T4 --qname, callee tampered: WARN names Core.pas' ($t4.Text -match 'WARN[^\r\n]*Core\.pas') "exit $($t4.Code)"

Tamper $app 'UseAlpha' 'UseAlphb'
$t3 = RunEngine @('document','--unit',$app,'--db',$db)
Check 'T3 own file tampered: exit 0, WARN names App.pas' (($t3.Code -eq 0) -and ($t3.Text -match 'WARN[^\r\n]*App\.pas')) "exit $($t3.Code)"

Tamper $core 'EAlphY' 'EAlphZ'
$b1 = RunEngine @('document','--project',$dpr,'--db',$db)
Check 'B1 --project, callee tampered: exit 0, WARN names Core.pas' (($b1.Code -eq 0) -and ($b1.Text -match 'WARN[^\r\n]*Core\.pas')) "exit $($b1.Code)"

Tamper $core 'EAlphZ' 'EAlphW'
$b2 = RunEngine @('document-all','--db',$db)
Check 'B2 document-all, callee tampered: exit 0, WARN names Core.pas' (($b2.Code -eq 0) -and ($b2.Text -match 'WARN[^\r\n]*Core\.pas')) "exit $($b2.Code)"
$b3 = RunEngine @('document-all','--db',$db)
Check 'B3 document-all after rescan: no WARN' (($b3.Code -eq 0) -and -not ($b3.Text -match 'WARN')) "exit $($b3.Code)"

if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
if ($fail) { Write-Host 'run_v151_DOCU5_tamper_rescan: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_v151_DOCU5_tamper_rescan: ALL PASS' -ForegroundColor Green; exit 0
} catch { Write-Host "run_v151_DOCU5_tamper_rescan: ERROR $_" -ForegroundColor Red; exit 2 }
