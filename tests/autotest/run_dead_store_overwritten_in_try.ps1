<#
  run_dead_store_overwritten_in_try.ps1 -- SHAPE F. A store whose only overwrite
  sits inside the body of a following try..EXCEPT is live on the exception path,
  so `overwrite-before-read` must not report it.

  THE HISTORY MATTERS, because this guard asserts the OPPOSITE of what its
  sibling `run_overwrite_before_read_pretry.ps1` asserted until 2026-08-29.

    2026-08-26  shape F built, measured (29 -> 25 on this repo), then REVERTED:
                it turned that sibling's `UnrelatedTry` positive control red, and
                the two fixtures are structurally identical. Owner RULED REJECT.
    2026-08-29  owner REVERSED the ruling: "We really do not know where the
                exception might strike, so lets not report it."

  So the shape now expected SILENT is:

      X := nil;                 { NOT a dead store }
      try
        X := TObject.Create;    { the only overwrite, INSIDE the try body }
      except
        Writeln('boom');        { handler never mentions X }
      end;
      R := X;                   { X read AFTER the try }

  If the body raises before the inner assignment completes, the read after the
  try observes the pre-try store. Delete that store -- which is the rule's own
  advice -- and the read is uninitialised.

  THE FOUR POSITIVE CONTROLS ARE THE POINT OF THIS FILE. Shape F's whole danger
  is that it degenerates into the cheap "stop reporting near a try" fix, which is
  the banned failure mode for this entire rule family. Each control names the one
  conjunct it removes:

    * TryFinallyTwin -- the SAME shape with `finally` instead of `except`. MUST
      still fire. Under try..finally the exception propagates onward and the
      code after the try is UNREACHABLE on that path, so the pre-try store really
      IS dead. This is the distinction the 2026-08-26 ruling established and
      ordered a future revisit not to lose: SHAPE F IS EXCEPT-ONLY.
    * NeverReadAfterTry -- overwritten inside a try..except body but never read
      afterwards. MUST still fire: with no post-try read there is no exception
      path that can observe the pre-try store, so nothing protects it.
    * HandlerContinues -- the handler ends in `Continue`, so the code after the
      try is unreachable on the exception path exactly as it is under a finally.
      MUST still fire. THIS CONTROL WAS ADDED BECAUSE THE FIRST IMPLEMENTATION
      FAILED IT: with only the other three conjuncts, shape F silenced
      DRagLint.Lint.RuleCatalog.pas:459, whose handler is `except Continue; end`
      and whose store really is dead. The corpus delta was 31 -> 28 and looked
      like a clean win until the three sites were read one at a time.
    * GenuineDead -- an ordinary dead store, no try in sight. MUST fire.

  Without all four, every silence assertion here would pass with the rule
  switched off.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-obr-shapef"
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
unit uObrShapeF;
interface
procedure OverwrittenInTryExcept(const F: string);
procedure TryFinallyTwin(const F: string);
procedure NeverReadAfterTry(const F: string);
procedure HandlerContinues(const F: string);
procedure GenuineDead(const F: string);
implementation
uses System.SysUtils, System.Classes;

{ SHAPE F. The only overwrite is inside the try body and the handler never
  mentions XT, so on the exception path the post-try read observes the nil.
  MUST BE SILENT. }
procedure OverwrittenInTryExcept(const F: string);
var
  XT: TStringList;
begin
  XT := nil;
  try
    XT := TStringList.Create;
    XT.Add(F);
  except
    Writeln('boom');
  end;
  if XT <> nil then
    Writeln(XT.Count);
end;

{ POSITIVE CONTROL 1 -- the try..FINALLY twin. Structurally identical to the
  case above except for the handler keyword. MUST STILL FIRE: the exception
  propagates past a finally, so `if YF <> nil` is unreachable on that path and
  the pre-try store really is dead. This is the except-only distinction. }
procedure TryFinallyTwin(const F: string);
var
  YF: TStringList;
begin
  YF := nil;
  try
    YF := TStringList.Create;
    YF.Add(F);
  finally
    Writeln('done');
  end;
  if YF <> nil then
    Writeln(YF.Count);
end;

{ POSITIVE CONTROL 2 -- overwritten inside a try..except body, but ZN is never
  read after the try. MUST STILL FIRE: with no post-try read, no exception path
  observes the pre-try store, so there is nothing for it to protect. This is the
  conjunct that stops shape F becoming "a try follows". }
procedure NeverReadAfterTry(const F: string);
var
  ZN: TStringList;
begin
  ZN := nil;
  try
    ZN := TStringList.Create;
    ZN.Add(F);
    ZN.Free;
  except
    Writeln('boom');
  end;
  Writeln(F);
end;

{ POSITIVE CONTROL 3 -- the handler ends in an unconditional Continue, so the
  post-try read is unreachable on the exception path exactly as it would be
  under a finally. MUST STILL FIRE. Reduced from the real site this control was
  written for, DRagLint.Lint.RuleCatalog.pas:459. }
procedure HandlerContinues(const F: string);
var
  Raw: string ;
  I  : Integer;
begin
  for I := 1 to 3 do
  begin
    Raw := '';
    try
      Raw := F + IntToStr(I);
    except
      Continue;
    end;
    Writeln(Raw);
  end;
end;

{ POSITIVE CONTROL 4 -- an ordinary dead store, no try anywhere. MUST fire. }
procedure GenuineDead(const F: string);
var
  N: Integer;
begin
  N := 1;
  N := Length(F);
  Writeln(N);
end;

end.
'@
$file = Join-Path $WorkDir 'uObrShapeF.pas'
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
foreach ($n in @('OverwrittenInTryExcept','TryFinallyTwin','NeverReadAfterTry','HandlerContinues','GenuineDead')) { $rows[$n] = Impl-Row $n }
if (@($rows.Values | Sort-Object -Unique).Count -ne 5) {
  Write-Host "FATAL: anchors collapsed: $($rows.Values -join ',')" -ForegroundColor Red; exit 2
}
Write-Host ("  anchors: " + (($rows.Keys | ForEach-Object { "$_=$($rows[$_])" }) -join ' ')) -ForegroundColor DarkGray

# FlowChecks runs on the bare per-file path, so `lint <file>` is sufficient here.
$out  = & $Exe lint $file 2>&1 | Out-String
$hits = @([regex]::Matches($out, 'uObrShapeF\.pas:(\d+):\d+\s+\[\w+\]\s+overwrite-before-read') |
          ForEach-Object { [int]$_.Groups[1].Value })
function Proc-Of([int]$Row) {
  $best = '(none)'
  foreach ($n in $rows.Keys) { if ($Row -ge $rows[$n]) { $best = $n } }
  $best
}
function Rows-In([string]$P) { ($hits | Where-Object { (Proc-Of $_) -eq $P }) -join ',' }
Write-Host ("  overwrite-before-read at rows: " + (($hits -join ',') -replace '^$','(none)')) -ForegroundColor DarkGray

Write-Host ''
Write-Host 'SHAPE F -- the overwrite is inside a following try..except' -ForegroundColor Cyan
Check 'OverwrittenInTryExcept: the pre-try store is NOT reported' `
  ((Rows-In 'OverwrittenInTryExcept') -eq '') "rows=$(Rows-In 'OverwrittenInTryExcept')"

Write-Host ''
Write-Host 'POSITIVE CONTROLS -- the rule must still work' -ForegroundColor Cyan
Check 'TryFinallyTwin: the finally twin STILL fires (shape F is except-only)' `
  ((Rows-In 'TryFinallyTwin') -ne '') "rows=$(Rows-In 'TryFinallyTwin')"
Check 'NeverReadAfterTry: no post-try read means no protection; STILL fires' `
  ((Rows-In 'NeverReadAfterTry') -ne '') "rows=$(Rows-In 'NeverReadAfterTry')"
Check 'HandlerContinues: an except that Continues does not fall through; STILL fires' `
  ((Rows-In 'HandlerContinues') -ne '') "rows=$(Rows-In 'HandlerContinues')"
Check 'GenuineDead: an ordinary dead store STILL fires' `
  ((Rows-In 'GenuineDead') -ne '') "rows=$(Rows-In 'GenuineDead')"

if ((Rows-In 'TryFinallyTwin') -eq '' -or (Rows-In 'NeverReadAfterTry') -eq '' -or
    (Rows-In 'HandlerContinues') -eq '' -or (Rows-In 'GenuineDead') -eq '') {
  Write-Host '  !! A control failed. The silence assertion above proves NOTHING -- it' -ForegroundColor Yellow
  Write-Host '  !! would pass with the rule switched off, which is precisely the cheap' -ForegroundColor Yellow
  Write-Host '  !! "stop reporting near a try" fix this guard exists to reject.' -ForegroundColor Yellow
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
