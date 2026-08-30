<#
  run_overwrite_before_read_pretry.ps1 -- a nil-init guarding an exception path is
  not a dead store, and reporting it gave advice that CRASHES.

  THE DEFECT THIS PINS:
    `overwrite-before-read` flagged the initialisation immediately preceding a
    `try`. 56 findings on this repo's own source, majority of this shape:

        Bindings := nil;                       <- reported as a dead store
        try
          Bindings := ExtractDfmEventBindings(...);
        except
          Bindings := nil;
        end;

    The store is NOT dead: it is what makes the handler path safe. Deleting it --
    which is what the finding tells the reader to do -- leaves an uninitialised
    variable to be tested or freed on the exception path. So this rule was not
    merely noisy, ITS ADVICE WAS WRONG, which is why it outranked every other
    open lint defect.

    Liveness is right about the CFG and wrong about the code: `try..except` wires
    the handler edge from the END of the try body, modelling "the exception fired
    after the body's assignments ran", so the pre-try store is killed before any
    exception-path use is seen. That edge is deliberate and tuned (used-before-
    assignment depends on the state it carries), so the fix is a syntactic guard
    scoped to the one wrong rule -- exactly the precedent FreedInFinallyBlock set
    for object-leak's identical cause.

  THE TWO POSITIVE CONTROLS ARE THE POINT OF THIS FILE. The cheap fix for every
  rule in this family is to stop reporting near a `try`, and that would silence
  genuine dead stores. So:
    * GenuineDead  -- an ordinary dead store with no try in sight MUST still fire.
    * UnrelatedTry -- a store before a try whose handler never MENTIONS that
      variable MUST still fire. This is what separates the sound predicate
      ("the handler uses it") from the cheap one ("a try follows").
  Without both, every assertion above would pass with the rule disabled.

  ------------------------------------------------------------------------------
  2026-08-29 -- UnrelatedTry WAS RESHAPED, AND A CASE IT USED TO COVER NOW
  ASSERTS THE OPPOSITE. Read this before concluding the control was weakened to
  get a build green; it was not, and the sequence matters.

  UnrelatedTry was originally written as:

      Val := 1;
      try
        Val := Length(F);      <- the overwrite, INSIDE the try body
        Other := TStringList.Create;
        Other.Free;
      except
        Writeln('failed');     <- handler never mentions Val
      end;
      Writeln(Val);            <- Val read AFTER the try

  That is SHAPE F, and this file asserted the finding MUST fire on it. On
  2026-08-26 that assertion is what caused shape F to be rejected: the two
  fixtures were structurally identical and only the owner could choose. The
  owner chose REJECT, and this control stayed as written.

  ON 2026-08-29 THE OWNER REVERSED THAT RULING -- "We really do not know where
  the exception might strike, so lets not report it." Shape F shipped
  (OverwrittenInsideFollowingTry in FlowChecks.pas), so the old body must now be
  SILENT. Both halves of the flip are written down rather than deleted:

    * OverwrittenInBodyNowSilent -- the ORIGINAL UnrelatedTry body, verbatim,
      now asserting SILENCE. The case that forced the 2026-08-26 ruling is kept
      in the file that used to assert the opposite, so the reversal is visible
      at the point it applies instead of only in a retired note.
    * UnrelatedTry -- RESHAPED so its overwrite sits ABOVE the try rather than
      inside it. Shape F therefore cannot reach it, and it STILL FIRES -- which
      means it still separates "the handler uses it" from "a try follows",
      which is the one job this control has ever had. It kept its teeth; it did
      not keep the disputed case.

  The finally-twin control that gives shape F ITS teeth lives with shape F, in
  run_dead_store_overwritten_in_try.ps1, not here.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-obr-pretry"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

$FixtureBody = @'
unit uObrPretry;
interface
procedure ProtectedSingle(const F: string);
procedure ProtectedMulti(const F: string);
procedure GenuineDead(const F: string);
procedure UnrelatedTry(const F: string);
procedure OverwrittenInBodyNowSilent(const F: string);
implementation
uses System.SysUtils, System.Classes;

{ The store guards the handler path: on an exception List must still be nil. }
procedure ProtectedSingle(const F: string);
var
  List: TStringList;
begin
  List := nil;
  try
    List := TStringList.Create;
    List.Add(F);
  except
    List := nil;
  end;
  if List <> nil then
    Writeln(List.Count);
end;

{ Five inits, ONE shared try. Protection must cover every member of the run,
  not merely the one closest to the try. }
procedure ProtectedMulti(const F: string);
var
  A, B, C, D, E: TStringList;
begin
  A := nil;
  B := nil;
  C := nil;
  D := nil;
  E := nil;
  try
    A := TStringList.Create;
    B := TStringList.Create;
    C := TStringList.Create;
    D := TStringList.Create;
    E := TStringList.Create;
    A.Add(F);
  finally
    A.Free;
    B.Free;
    C.Free;
    D.Free;
    E.Free;
  end;
end;

{ POSITIVE CONTROL 1 -- an ordinary dead store, no try anywhere. MUST fire. }
procedure GenuineDead(const F: string);
var
  N: Integer;
begin
  N := 1;
  N := Length(F);
  Writeln(N);
end;

{ POSITIVE CONTROL 2 -- a store before a try whose handler never MENTIONS Val.
  MUST fire: this is what separates "the handler uses it" from "a try follows".

  RESHAPED 2026-08-29: the overwrite (Val := Length(F)) sits ABOVE the try, not
  inside it, so shape F cannot reach this case and the control keeps its teeth.
  Val := 1 is still a store BEFORE a try -- ProtectedByFollowingTry skips the run
  of sibling assignments to find it -- so flattening that guard to "a try
  follows" still turns this red, which is the whole point. }
procedure UnrelatedTry(const F: string);
var
  Val  : Integer;
  Other: TStringList;
begin
  Val := 1;
  Val := Length(F);
  try
    Other := TStringList.Create;
    Other.Free;
  except
    Writeln('failed');
  end;
  Writeln(Val);
end;

{ THE CASE THAT FORCED THE 2026-08-26 RULING, kept verbatim and now asserting the
  OPPOSITE. This is the original UnrelatedTry body: overwrite inside the try
  body, handler silent about Val, Val read after the try. Shape F. The owner
  reversed the ruling on 2026-08-29, so it MUST NOW BE SILENT. }
procedure OverwrittenInBodyNowSilent(const F: string);
var
  Val  : Integer;
  Other: TStringList;
begin
  Val := 1;
  try
    Val := Length(F);
    Other := TStringList.Create;
    Other.Free;
  except
    Writeln('failed');
  end;
  Writeln(Val);
end;

end.
'@
$file = Join-Path $WorkDir 'uObrPretry.pas'
$norm = ($FixtureBody -replace "`r`n", "`n") -replace "`n", "`r`n"
[System.IO.File]::WriteAllText($file, $norm, [System.Text.Encoding]::ASCII)

# Anchors derived from the fixture. LAST match: every routine is named twice
# (interface + implementation) and -First would put every anchor in the
# interface section, attributing every finding to the final routine.
$src = Get-Content $file
function Impl-Row([string]$Name) {
  ($src | Select-String -Pattern ("procedure {0}(const F: string);" -f $Name) -SimpleMatch | Select-Object -Last 1).LineNumber
}
$rows = [ordered]@{}
foreach ($n in @('ProtectedSingle','ProtectedMulti','GenuineDead','UnrelatedTry','OverwrittenInBodyNowSilent')) { $rows[$n] = Impl-Row $n }
if (@($rows.Values | Sort-Object -Unique).Count -ne 5) {
  Write-Host "FATAL: anchors collapsed: $($rows.Values -join ',')" -ForegroundColor Red; exit 2
}
Write-Host ("  anchors: " + (($rows.Keys | ForEach-Object { "$_=$($rows[$_])" }) -join ' ')) -ForegroundColor DarkGray

# FlowChecks runs on the bare per-file path, so `lint <file>` is sufficient here.
# (Whole-index rules like doc-drift would need lint-all -- see
# INBOX-lint-single-file-silently-omits-lint-all-rules.md.)
$out  = & $Exe lint $file 2>&1 | Out-String
$hits = @([regex]::Matches($out, 'uObrPretry\.pas:(\d+):\d+\s+\[\w+\]\s+overwrite-before-read') |
          ForEach-Object { [int]$_.Groups[1].Value })
function Proc-Of([int]$Row) {
  $best = '(none)'
  foreach ($n in $rows.Keys) { if ($Row -ge $rows[$n]) { $best = $n } }
  $best
}
function Rows-In([string]$P) { ($hits | Where-Object { (Proc-Of $_) -eq $P }) -join ',' }
Write-Host ("  overwrite-before-read at rows: " + (($hits -join ',') -replace '^$','(none)')) -ForegroundColor DarkGray

Write-Host ''
Write-Host 'A store guarding an exception path is not a dead store' -ForegroundColor Cyan
Check 'ProtectedSingle: the nil-init before try..except is NOT reported' `
  ((Rows-In 'ProtectedSingle') -eq '') "rows=$(Rows-In 'ProtectedSingle')"
Check 'ProtectedMulti: NONE of the five inits before one shared try is reported' `
  ((Rows-In 'ProtectedMulti') -eq '') "rows=$(Rows-In 'ProtectedMulti')"
Check 'OverwrittenInBodyNowSilent: shape F, silent since the 2026-08-29 reversal' `
  ((Rows-In 'OverwrittenInBodyNowSilent') -eq '') "rows=$(Rows-In 'OverwrittenInBodyNowSilent')"

Write-Host ''
Write-Host 'POSITIVE CONTROLS -- the rule must still work' -ForegroundColor Cyan
Check 'GenuineDead: an ordinary dead store STILL fires' `
  ((Rows-In 'GenuineDead') -ne '') "rows=$(Rows-In 'GenuineDead')"
Check 'UnrelatedTry: a store before a try that ignores it STILL fires' `
  ((Rows-In 'UnrelatedTry') -ne '') "rows=$(Rows-In 'UnrelatedTry')"

if ((Rows-In 'GenuineDead') -eq '' -or (Rows-In 'UnrelatedTry') -eq '') {
  Write-Host '  !! A control failed. The two assertions above prove NOTHING -- they' -ForegroundColor Yellow
  Write-Host '  !! would pass with the rule switched off, which is precisely the' -ForegroundColor Yellow
  Write-Host '  !! cheap "stop reporting near a try" fix this guard exists to reject.' -ForegroundColor Yellow
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
