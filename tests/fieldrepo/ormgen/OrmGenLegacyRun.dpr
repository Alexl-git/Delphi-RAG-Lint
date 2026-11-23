program OrmGenLegacyRun;

{$APPTYPE CONSOLE}

{ drag-lint 1.54 lane TT-GENFIX-3 -- runs a unit pair written BEFORE the Assign overload (AssignI, old 'with' headers)
  after repo update-orm regenerated its regions, without repo upgrade-orm-headers: it must still compile and copy.
  One PASS / FAIL line per check, then "SUMMARY pass=N fail=M". }

uses
  System.SysUtils,
  System.Classes,
  Vcl.Graphics,
  Data.SqlTimSt,
  Data.FmtBcd,
  MSCTYPES,
  MStreams,
  uMicObjectBase,
  iORMFIX,
  uORMFIX;

var
  GPass: Integer = 0;
  GFail: Integer = 0;

procedure Check(const pName: string; pCond: Boolean);
begin
  if pCond then
    Inc(GPass)
  else
    Inc(GFail);
  Writeln(if pCond then 'PASS ' else 'FAIL ', pName);
end;

procedure TestLegacy;
var
  vSrc, vDst: TmcORMFIX;
  vSrcI, vDstI: ImcORMFIX;
  vD0: Integer;
begin
  vD0 := MicDestroyCount;
  vSrc := TmcORMFIX.Create(nil);
  vDst := TmcORMFIX.Create(nil);
  vSrc.ID := 5;
  vSrc.NAME := 'legacy';
  vDst.Assign(vSrc);
  Check('L1 object Assign copies under the old headers', (vDst.ID = 5) and (vDst.NAME = 'legacy') and (MicDestroyCount = vD0));
  vDst.Free;
  vSrc.Free;
  vSrc := TmcORMFIX.Create(nil);
  vSrcI := vSrc;
  vDst := TmcORMFIX.Create(nil);
  vDstI := vDst;
  vSrc.ID := 6;
  vDst.AssignI(vSrcI);
  Check('L2 AssignI (object receiver, interface argument) copies', vDst.ID = 6);
  vDst.ID := 0;
  vDstI.AssignI(vSrcI);
  Check('L3 AssignI (interface receiver) copies', vDst.ID = 6);
  vDstI := nil;
  vSrcI := nil;
end;

begin
  try
    TestLegacy;
  except
    on E: Exception do
    begin
      Inc(GFail);
      Writeln('FAIL unexpected ', E.ClassName, ': ', E.Message);
    end;
  end;
  Writeln('SUMMARY pass=', GPass, ' fail=', GFail);
  if GFail > 0 then
    Halt(1);
end.
