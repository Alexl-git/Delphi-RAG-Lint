program V154SchemaFactsRetryTests;
{$APPTYPE CONSOLE}
{ Pins DRagLint.V154.SCHEMA.Support.FactsOf (1.54): a field repository that could not be read once is read again although
  the file did not change. Run as `V154SchemaFactsRetryTests lint --project <X.dproj> --repo <file>`: the project names the
  repository as in a lint run. Runner: tests\autotest\run_v154_SCHEMA.ps1. }
uses
  System.SysUtils,
  System.Classes,
  DRagLint.V151.Api,
  DRagLint.FieldRepo.SchemaFactsEx,
  DRagLint.V154.SCHEMA.Support;

const
  ARG_REPO = 5;
  AFTER_TTL_MS = 2200;   // the located path is trusted for LOCATE_TTL_MS

var
  GFailed: Integer;

procedure Check(const AName: string; AOk: Boolean);
begin
  Writeln(if AOk then '[PASS] ' else '[FAIL] ', AName);
  if not AOk then Inc(GFailed);
end;

procedure Run;
var
  Ctx : TV151FileCtx;
  Lock: TFileStream;
begin
  Ctx := Default(TV151FileCtx);
  Lock:= TFileStream.Create(ParamStr(ARG_REPO), fmOpenRead or fmShareExclusive);
  try
    Check('a locked repository gives no facts', FactsOf(Ctx) = nil);
  finally
    Lock.Free;
  end;
  Sleep(AFTER_TTL_MS);
  Check('the same file is read once the lock is gone', FactsOf(Ctx) <> nil);
  Sleep(AFTER_TTL_MS);
  Check('and stays read', FactsOf(Ctx) <> nil);
end;

begin
  try
    Run;
  except
    on E: Exception do
      Check(E.ClassName + ': ' + E.Message, False);
  end;
  Writeln('failed=', GFailed);
  if GFailed > 0 then Halt(1);
end.