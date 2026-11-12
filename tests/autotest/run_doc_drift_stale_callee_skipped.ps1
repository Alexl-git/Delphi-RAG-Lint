<#
  run_doc_drift_stale_callee_skipped.ps1 -- 152b DOCU2: the doc-drift lint rule
  must not grade exception / facts drift from a callee file's text at line
  numbers the index no longer describes.

  THE DEFECT (152b DOCU, FOUND-152b)
  ----------------------------------
  TDocDrift.Analyze rebuilds a decl's facts with TDocFactsBuilder.Build, which
  mines a CALLEE's raises from the callee file AS IT IS NOW at the callee's
  INDEXED body range. After the callee file is edited and not reindexed, that
  range covers other text: doc-drift reported "<exception cref> not raised" and
  "facts block out of date" for a doc that is correct, and `lint --fix` would
  have rewritten it from the wrong text. DOCU fixed the `document` verbs
  (refusal); this is the lint side: Lint.DocRules drops the facts-derived kinds
  (ddExceptionNotRaised, ddFactsBlockStale) of a decl whose facts read a file
  changed since indexing, skips its --fix edits, and says so on stderr.

  WHAT IS ASSERTED
  ----------------
    P1  positive control, fresh index after `document --apply`: lint finds NO
        doc-drift on App.UseAlpha, and DOES find doc-param-not-in-signature on
        App.BadParam (the rule runs).
    P2  positive control, fresh index: a hand-written WRONG
        <exception cref="EGamma"> on App.UseGamma2 is reported as doc-drift
        (the exception check itself works).
    R1  Core.pas shifted 6 lines (callee ranges now cover the NEXT routine),
        NO reindex: no doc-drift on UseAlpha. (Base 1.50.0-alpha: doc-drift
        reported from Core.Beta's text.)
    R2  stderr names Core.pas and asks for a reindex.
    C1  the non-facts finding on BadParam is still reported on the stale index.
    R3  `lint --fix --apply` on the stale index leaves App.pas's EAlpha tag in
        place (no rewrite from stale text).
    R4  after `index --project`, lint again finds no doc-drift on UseAlpha.

  Run from a neutral cwd, pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
try {
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
$exePath = (Resolve-Path $Exe).Path

$scratch = Join-Path C:\TEMP "draglint_docdrift_stale_callee_$PID"
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

/// <summary>Has a documented parameter the signature lost.</summary>
/// <param name="Nope">Gone.</param>
procedure BadParam;

/// <summary>Calls Alpha but claims EGamma.</summary>
/// <param name="A">Value.</param>
/// <exception cref="EGamma">Never raised here.</exception>
procedure UseGamma2(const A: Integer);

implementation

uses Core;

procedure UseAlpha(const A: Integer);
begin
  Alpha(A);
end;

procedure BadParam;
begin
end;

procedure UseGamma2(const A: Integer);
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
# lint --json is a bare array (rule, file_path, start_line, message ...); stderr kept apart.
function LintApp {
  $errFile = Join-Path $scratch 'lint.err'
  $json = & $exePath lint $app --db $db --project-rules --json 2> $errFile | Out-String
  $arr = @()
  $s = $json.IndexOf('[')
  if ($s -ge 0) { $arr = @($json.Substring($s) | ConvertFrom-Json) }
  return [pscustomobject]@{ Findings = $arr; Err = (Get-Content $errFile -Raw) + '' }
}
# lint --json carries no symbol name: a finding belongs to routine $Sym when its
# start_line falls in Sym's interface doc block .. declaration line of App.pas.
function SymLines([string]$Sym) {
  $lines = [IO.File]::ReadAllLines($app)
  $decl = [Array]::FindIndex($lines, [Predicate[string]]{ param($l) $l -match "^procedure $Sym\b" })
  if ($decl -lt 0) { throw "no declaration of $Sym in App.pas" }
  $first = $decl
  while (($first -gt 0) -and ($lines[$first - 1] -match '^///')) { $first-- }
  return @(($first + 1), ($decl + 1))
}
function Has($Findings, [string]$Rule, [string]$Sym) {
  $r = SymLines $Sym
  return @($Findings | Where-Object { $_.rule -eq $Rule -and $_.start_line -ge $r[0] -and $_.start_line -le $r[1] }).Count -gt 0
}
function Reindex { $r = RunEngine @('index','--project',$dpr,'--db',$db); if ($r.Code -ne 0) { throw "fixture index failed: $($r.Text)" } }

Reindex
$d = RunEngine @('document','--qname','App.UseAlpha','--db',$db,'--apply','--no-backup')
if (($d.Code -ne 0) -or -not ([IO.File]::ReadAllText($app) -match '<exception cref="EAlpha">')) { throw "fixture document failed: $($d.Text)" }
Reindex

$p = LintApp
Check 'P0 lint output parsed (non-empty)' ($p.Findings.Count -gt 0) "count $($p.Findings.Count)"
Check 'P1 fresh: no doc-drift on UseAlpha' (-not (Has $p.Findings 'doc-drift' 'UseAlpha'))
Check 'P1 fresh: doc-param-not-in-signature on BadParam' (Has $p.Findings 'doc-param-not-in-signature' 'BadParam')
Check 'P2 fresh: wrong EGamma tag on UseGamma2 is doc-drift' (Has $p.Findings 'doc-drift' 'UseGamma2')

# Shift Core's implementation 6 lines: every indexed callee range now covers the routine BEFORE it.
WriteAscii $core ([IO.File]::ReadAllText($core).Replace("implementation`r`n", "implementation`r`n// 1`r`n// 2`r`n// 3`r`n// 4`r`n// 5`r`n// 6`r`n"))
$r = LintApp
Check 'R1 stale callee: no doc-drift on UseAlpha' (-not (Has $r.Findings 'doc-drift' 'UseAlpha')) (@($r.Findings | Where-Object rule -eq 'doc-drift' | ForEach-Object message) -join ' | ')
Check 'R2 stale callee: stderr names Core.pas and a reindex' ($r.Err -match 'doc-drift[^\r\n]*Core\.pas[^\r\n]*[Rr]eindex') (($r.Err.Trim() -split "`n") | Select-Object -Last 1)
Check 'C1 stale callee: BadParam finding still reported' (Has $r.Findings 'doc-param-not-in-signature' 'BadParam')

$fx = RunEngine @('lint',$app,'--db',$db,'--project-rules','--fix','--apply','--no-backup')
Check 'R3 stale callee: --fix --apply keeps the EAlpha tag' ([IO.File]::ReadAllText($app) -match '<exception cref="EAlpha">') "exit $($fx.Code)"

Reindex
$r4 = LintApp
Check 'R4 after reindex: no doc-drift on UseAlpha' (-not (Has $r4.Findings 'doc-drift' 'UseAlpha'))

if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
if ($fail) { Write-Host 'run_doc_drift_stale_callee_skipped: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_doc_drift_stale_callee_skipped: ALL PASS' -ForegroundColor Green; exit 0
} catch { Write-Host "run_doc_drift_stale_callee_skipped: ERROR $_" -ForegroundColor Red; exit 2 }
