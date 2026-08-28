<#
  run_stat_gated_destructive.ps1 -- docs\INBOX-stat-gated-destructive-acts.md
  (requested by the DataCopy owner, 2026-08-28).

  THE DEFECT CLASS. FileExists / TFile.Exists answer False for ANY failure to
  stat -- a network blip, a permission change, a share dropping -- not only for
  genuine absence. Cash that boolean as a destructive act and a transient fault
  destroys data and returns success. Confirmed six times in one codebase, once
  inside the RTL itself.

  WHY A RULE AND NOT A TEST, in the requester's words: the correct fix REMOVES
  the stat from the decision, so a test injecting a fake FileExists hooks
  nothing after the fix and degenerates into a trivial pass -- a test that
  certifies its own bug.

  THE POSITIVES ARE TRIVIALLY RED (the rule did not exist), so THE NEGATIVES
  CARRY THE WEIGHT of this guard. A matcher that fired on every FileExists would
  pass every positive here and fail N1-N6.

  TWO CORRECTIONS TO THE NOTE, both forced by measurement rather than review:

   1. ARGUMENT EQUALITY IS NOT REQUIRED. The note asked for the destructive call
      to be "on the same path expression X". Its own headline instance is
      `if FileExists(F) then Append(TF) else Rewrite(TF)` -- the stat is on the
      PATH, the destructive call takes the TEXTFILE HANDLE. A same-argument
      matcher would have missed the site the rule was requested for.
   2. THE BRANCH MUST BE A SINGLE STATEMENT. Scanning a whole multi-statement
      branch reported DRagLint.CLI.pas:20433, which redirects stdout to the null
      device (`AssignFile(Output, 'NUL'); Rewrite(Output);`) inside a try, paired
      with an unrelated TDirectory.Exists far above. Rewriting NUL destroys
      nothing. N6 pins that limitation deliberately.

  CORPUS SCAN, before severity was fixed: DataCopy 4, ORM3 5, this repo 10,
  YADF 0 -- and every survivor inspected is the canonical
  `if TFile.Exists(X) then TFile.Delete(X)`. Shipped at WARNING on the
  requester's own pre-authorisation ("if that proves optimistic in a corpus
  scan, ship as a warning first and promote").

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe      = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$RulesDir = "$PSScriptRoot\..\..\rules",
  [string]$WorkDir  = "C:\TEMP\draglint_statgated"
)
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }
function Write-Ascii($p,$t){ [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
$rules   = (Resolve-Path $RulesDir).Path
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

# One routine per shape, so a finding's line maps to exactly one case.
$fixture = @'
unit uStatGated;

interface

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes;

// ---- POSITIVES: reconstructed from the note's confirmed instances ----------

procedure P1_AppendElseRewrite(const F: string; var TF: TextFile);
begin
  if FileExists(F) then Append(TF) else Rewrite(TF);
end;

function P2_ShortCircuit(const LOut: string; var LErr: string): Boolean;
begin
  Result := (not TFile.Exists(LOut)) or SafeDelete(LOut, LErr);
end;

procedure P4_FilenameAppendWriter(const F: string);
var
  W: TStreamWriter;
begin
  W := TStreamWriter.Create(F, True, TEncoding.ASCII);
  W.Free;
end;

procedure P5_ExistsThenDelete(const F: string);
begin
  if TFile.Exists(F) then TFile.Delete(F);
end;

// ---- NEGATIVES: these carry the guard ------------------------------------

procedure N1_ExistsThenRead(const F: string);
begin
  if FileExists(F) then Writeln(F);
end;

procedure N2_GuardClause(const F: string);
begin
  if not FileExists(F) then Exit;
  Writeln(F);
end;

function N3_ActAndReadError(const F: string; var LErr: string): Boolean;
begin
  Result := SafeDelete(F, LErr);
end;

procedure N4_CreateNotAppend(const F: string);
var
  W: TStreamWriter;
begin
  W := TStreamWriter.Create(F, False, TEncoding.ASCII);
  W.Free;
end;

procedure N5_StreamOverload(S: TStream);
var
  W: TStreamWriter;
begin
  W := TStreamWriter.Create(S, TEncoding.ASCII);
  W.Free;
end;

procedure N6_BlockBranch(const F: string; var TF: TextFile);
begin
  if DirectoryExists(F) then
  begin
    Writeln('unrelated');
    AssignFile(TF, 'NUL');
    Rewrite(TF);
  end;
end;

end.
'@

$file = Join-Path $WorkDir 'uStatGated.pas'
Write-Ascii $file $fixture

Push-Location C:\TEMP
try {
  $out = (& $exePath lint $file --rules-dir $rules 2>&1 | Out-String)
  $srcLines = [System.IO.File]::ReadAllLines($file)
  $hits = @()
  foreach ($l in ($out -split "`r?`n")) {
    if ($l -match ':(\d+):\d+\s+\[\w+\]\s+stat-gated-destructive:') { $hits += [int]$Matches[1] }
  }
  function RoutineOf([int]$Line) {
    for ($i = $Line - 1; $i -ge 0; $i--) {
      if ($srcLines[$i] -match '^\s*(procedure|function)\s+(\w+)') { return $Matches[2] }
    }
    return ''
  }
  $fired = @($hits | ForEach-Object { RoutineOf $_ } | Sort-Object -Unique)
  Write-Host ("  fired in: {0}" -f $(if($fired){$fired -join ','}else{'(none)'})) -ForegroundColor DarkGray

  foreach ($r in @('P1_AppendElseRewrite','P2_ShortCircuit','P4_FilenameAppendWriter','P5_ExistsThenDelete')) {
    Check "P  $r FIRES" ($fired -contains $r) ($fired -join ',')
  }
  foreach ($r in @('N1_ExistsThenRead','N2_GuardClause','N3_ActAndReadError','N4_CreateNotAppend','N5_StreamOverload','N6_BlockBranch')) {
    Check "N  $r is SILENT" (-not ($fired -contains $r)) ($fired -join ',')
  }

  # The rule must be in the catalog AND enabled, or lint-all silently skips it
  # while `lint` still fires -- two surfaces disagreeing about one input.
  $cat = (& $exePath rules --json 2>$null | Out-String | ConvertFrom-Json)
  $rs  = if ($cat.rules) { $cat.rules } else { $cat }
  $me  = $rs | Where-Object { $_.id -eq 'stat-gated-destructive' }
  Check 'CAT the rule is in the catalog'        ([bool]$me) 'rules --json does not list it'
  Check 'CAT it is enabled by default'          ($me.default_enabled -eq $true) "default_enabled=$($me.default_enabled)"
  Check 'CAT severity is warning (not error)'   ($me.default_severity -eq 'warning') "severity=$($me.default_severity)"

  Check 'VACUITY the rule fired at all' ($hits.Count -gt 0) 'no findings -- the rule may not be wired into `lint`'
}
finally { Pop-Location }

Write-Host ''
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
