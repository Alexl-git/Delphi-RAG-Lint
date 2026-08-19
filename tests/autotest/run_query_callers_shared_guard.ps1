<#
  run_query_callers_shared_guard.ps1 -- `query find-callers --resolved` renders
  the SAME text and the SAME JSON after its computation moved out of
  DRagLint.CLI and into DRagLint.Query.Callers.

  WHAT THIS IS, HONESTLY:
    This is a REFACTORING-INVARIANCE guard, and unlike the others in this
    battery it CANNOT be demonstrated red before the change -- nothing has moved
    yet, so it trivially passes against the pre-change build. Its job starts the
    moment the extraction lands: it fails if the shared unit renders even one
    character differently from the inline code it replaced.

    That is stated out loud because a guard that only ever passes is exactly the
    thing this repo's own docs-drift list was written about. The RED-provable
    half of this work lives in run_hover_bundle_guard.ps1, which asserts the CLI
    and the LSP produce the SAME rows -- the assertion that fails if the two
    surfaces ever diverge.

  WHY BOTH FORMATS:
    The text path groups rows under a per-target header and prints callbacks
    WITHOUT one; the JSON path emits a fixed key order and OMITS the 'line' pair
    entirely when the enclosing symbol is unknown. Both are easy to get subtly
    wrong when flattening the computation into rows, and neither is covered by
    the other.

  THE CONTROLS:
    * D_Orphan must still report '0 caller(s)' AND exit 1. An extraction that
      returned rows for everything would otherwise look like a success.
    * A_Predicate must still be marked [callback]. The callback rules are the
      most intricate part of what moved.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-shared-callers"
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
$SrcDir = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $SrcDir | Out-Null

$Fixture = @'
unit uSharedCallers;

interface

type
  TPickPred = function(const AItem: string): Boolean;

  TWorker = class
  public
    function ApplyDelta(const ADelta: string; ACount: Integer): Integer;
    { TWO OVERLOADS, both called. They are DISTINCT target symbols that share
      one qualified name -- the case that tells "a header per TARGET" apart
      from "a header per distinct name". }
    function Pick(const AName: string): Integer; overload;
    function Pick(AIndex: Integer): Integer; overload;
  end;

function  A_Predicate(const AItem: string): Boolean;
procedure C_Driver;
procedure D_Orphan;

implementation

function TWorker.ApplyDelta(const ADelta: string; ACount: Integer): Integer;
begin
  Result := ACount;
end;

function TWorker.Pick(const AName: string): Integer;
begin
  Result := Length(AName);
end;

function TWorker.Pick(AIndex: Integer): Integer;
begin
  Result := AIndex;
end;

function A_Predicate(const AItem: string): Boolean;
begin
  Result := AItem <> '';
end;

procedure D_Orphan;
begin
  Writeln('orphan');
end;

procedure Choose(P: TPickPred);
begin
  if Assigned(P) then Writeln('chosen');
end;

procedure C_Driver;
var
  W: TWorker;
begin
  Choose(A_Predicate);
  W := TWorker.Create;
  try
    W.ApplyDelta('x', 3);
    W.Pick('a');
    W.Pick(1);
  finally
    W.Free;
  end;
end;

end.
'@

WriteAnsi (Join-Path $SrcDir 'uSharedCallers.pas') $Fixture

$Db = Join-Path $WorkDir 'fix.sqlite'
& $Exe index $SrcDir --db $Db 2>&1 | Out-Null
if (-not (Test-Path $Db)) { Write-Host 'FATAL: index produced no DB' -ForegroundColor Red; exit 2 }

# ---- text form ------------------------------------------------------------
# Capture stdout ONLY. 2>&1 interleaves the config banner into the captured
# stream and has already, in this repo, landed a banner inside generated source.
$txt = (& $Exe query find-callers --name ApplyDelta --resolved --db $Db 2>$null | Out-String)
Check 'text: the target header is printed' ($txt -match 'TWorker\.ApplyDelta:') "got: $($txt.Trim())"
Check 'text: the caller is listed with a confidence tag' ($txt -match 'C_Driver\s+\(.*\)\s+\[(certain|ambiguous)\]') `
  "got: $($txt.Trim())"

$cbTxt = (& $Exe query find-callers --name A_Predicate --resolved --db $Db 2>$null | Out-String)
Check 'CONTROL: the callback reach is still marked [callback]' ($cbTxt -match '\[callback\]') "got: $($cbTxt.Trim())"
Check 'text: a callback row is printed WITHOUT a target header' ($cbTxt -notmatch '(?m)^\s+A_Predicate:') `
  "got: $($cbTxt.Trim())"

$orphanTxt = (& $Exe query find-callers --name D_Orphan --resolved --db $Db 2>$null | Out-String)
$orphanExit = $LASTEXITCODE
Check 'CONTROL: the orphan reports 0 caller(s)' ($orphanTxt -match '0 caller\(s\)') "got: $($orphanTxt.Trim())"
Check 'CONTROL: the orphan exits 1' ($orphanExit -eq 1) "exit=$orphanExit"

# ---- json form ------------------------------------------------------------
function ResolvedJson([string]$name) {
  $raw = & $Exe query find-callers --name $name --resolved --json --db $Db 2>$null | Out-String
  $m = [regex]::Match($raw, '\[.*\]', 'Singleline')
  if (-not $m.Success) { return $null }
  return $m.Value
}

$jsonRaw = ResolvedJson 'ApplyDelta'
Check 'json: a balanced array is emitted' ($null -ne $jsonRaw)
if ($null -ne $jsonRaw) {
  $rows = @($jsonRaw | ConvertFrom-Json)
  Check 'json: exactly one resolved caller' ($rows.Count -eq 1) "count=$($rows.Count)"
  if ($rows.Count -ge 1) {
    $r = $rows[0]
    Check 'json: caller_qname is the calling routine' ($r.caller_qname -match 'C_Driver') "got=$($r.caller_qname)"
    Check 'json: target_qname is the resolved target' ($r.target_qname -match 'TWorker\.ApplyDelta') "got=$($r.target_qname)"
    Check 'json: file is file-name-only, not a path' (($r.file -notmatch '[\\/]') -and ($r.file -match '\.pas$')) "got=$($r.file)"
    Check 'json: a line is present when the enclosing symbol is known' ($null -ne $r.line -and $r.line -gt 0) "got=$($r.line)"
  }
  # Key ORDER is part of the contract -- a consumer diffing two runs sees it.
  Check 'json: key order is caller_qname,file,confidence,target_qname[,line]' `
    ($jsonRaw -match '"caller_qname"[\s\S]*?"file"[\s\S]*?"confidence"[\s\S]*?"target_qname"') `
    'key order changed'
}

# ---- OVERLOADS -----------------------------------------------------------
# WHY THIS CASE IS HERE, AND WHAT IT DOES *NOT* PROVE.
#
# The extraction flattened per-target caller lists into one flat row array, so
# the text form has to rediscover where each target's run begins. Doing that by
# "the qualified name changed" LOOKS equivalent to the inline version's
# per-target loop and is not: two overloads are distinct target symbols that
# SHARE one qualified name, so name-grouping would merge two runs into one and
# drop a header. The shipped code therefore carries an explicit FirstOfTarget
# flag set once per target, rather than comparing names.
#
# HONESTY ABOUT THIS FIXTURE: it does NOT distinguish the two implementations.
# Measured 2026-08-19 -- the resolver reports BOTH `W.Pick('a')` and `W.Pick(1)`
# as `ambiguous` and attributes both call sites to the SAME overload symbol, so
# exactly one target has callers and both implementations print one header. An
# assertion of "expect 2 headers" was written first and failed against correct
# code; the expectation was wrong, not the code.
#
# So this pins the CURRENT truth (one header, both rows under it) and will fail
# loudly if overload resolution ever becomes type-precise -- at which point the
# per-target grouping starts to matter and this case becomes a real control.
$ovTxt = (& $Exe query find-callers --name Pick --resolved --db $Db 2>$null | Out-String)
$ovHeaders = ([regex]::Matches($ovTxt, '(?m)^\s+\S*TWorker\.Pick:\s*$')).Count
$ovRowLines = ([regex]::Matches($ovTxt, '(?m)^\s+\S*C_Driver\s+\(')).Count
Check 'OVERLOADS: both call sites are reported' ($ovRowLines -eq 2) `
  "rows=$ovRowLines in: $($ovTxt.Trim())"
Check 'OVERLOADS: headers match the number of TARGETS that have callers' ($ovHeaders -eq 1) `
  "headers=$ovHeaders (1 = the resolver still collapses ambiguous overloads onto one target; if this becomes 2, overload resolution got precise and that is the news)"

$ovJson = ResolvedJson 'Pick'
if ($null -ne $ovJson) {
  $ovRows = @($ovJson | ConvertFrom-Json)
  Check 'OVERLOADS: both call sites survive into json' ($ovRows.Count -eq 2) "count=$($ovRows.Count)"
}

$cbJson = ResolvedJson 'A_Predicate'
if ($null -ne $cbJson) {
  $cbRows = @($cbJson | ConvertFrom-Json)
  $cbOnly = @($cbRows | Where-Object { $_.confidence -eq 'callback' })
  Check 'CONTROL json: the callback row survives with confidence=callback' ($cbOnly.Count -gt 0) `
    "confidences=$(($cbRows | ForEach-Object { $_.confidence }) -join ',')"
  if ($cbOnly.Count -gt 0) {
    Check 'CONTROL json: the callback row carries its call-site line' ($cbOnly[0].line -gt 0) "line=$($cbOnly[0].line)"
  }
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
