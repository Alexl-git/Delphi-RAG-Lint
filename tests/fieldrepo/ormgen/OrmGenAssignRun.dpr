program OrmGenAssignRun;

{$APPTYPE CONSOLE}

{ drag-lint 1.54 lane TT-GENFIX -- runs code the ORM generator wrote (OrmGenTests --emit-fixture).
  The stub units of this folder stand in for ORM3. Contract: the generated Assign / AssignTo copy
  every stored column; a list the generator owns (created in DB-RAD 14, freed in 15) is copied by
  content into the receiver's own list; a class column it does not own (TPicture) stays a reference.
  One PASS / FAIL line per check, then "SUMMARY pass=N fail=M". }

uses
  System.SysUtils,
  System.Classes,
  Vcl.Graphics,
  Data.SqlTimSt,
  Data.FmtBcd,
  MSCTYPES,
  MStreams,
  iORMFIX,
  uORMFIX,
  iPLAINFIX,
  uPLAINFIX,
  iEMPTYFIX,
  uEMPTYFIX,
  uORMFIX_SERVER,
  uORMFIX_CLIENT,
  uPLAINFIX_SERVER,
  uPLAINFIX_CLIENT;

type
  TFixAccess = class(TmcORMFIX);
  TPlainAccess = class(TmcPLAINFIX);
  TFixChild = class(TmcORMFIX);

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

procedure Fill(pObj: TmcORMFIX);
begin
  pObj.ID := 77;
  pObj.NAME := 'alpha';
  pObj.ACTIVE := True;
  pObj.AMOUNT := 12.5;
  pObj.QTY := 5;
  pObj.SMALLN := 6;
  pObj.FLAG8 := 7;
  pObj.STATUS := osDone;
  pObj.STAMP := DateTimeToSQLTimeStamp(EncodeDate(2026, 11, 23));
  pObj.WHENAT := EncodeDate(2025, 1, 2);
  pObj.RAW := TBytes.Create(1, 2, 3);
  pObj.BCD := IntegerToBcd(42);
  pObj.MEMO.Text := 'note';
end;

function SameScalars(pA: TmcORMFIX): Boolean;
begin
  Result := (pA.ID = 77) and (pA.NAME = 'alpha') and pA.ACTIVE and (pA.AMOUNT = 12.5) and (pA.QTY = 5) and
    (pA.SMALLN = 6) and (pA.FLAG8 = 7) and (pA.STATUS = osDone) and (pA.STAMP.Year = 2026) and
    (pA.WHENAT = EncodeDate(2025, 1, 2)) and (Length(pA.RAW) = 3) and (BcdToInteger(pA.BCD) = 42);
end;

{ the reference semantics of AssignI leave two owners: hand the copy its own list back before Free }
procedure Detach(pObj: TmcORMFIX);
begin
  pObj.MEMO := nil;
end;

{ bytes the memory manager holds allocated now }
function HeapUsed: NativeUInt;
var
  vState: TMemoryManagerState;
  I: Integer;
begin
  GetMemoryManagerState(vState);
  Result := vState.TotalAllocatedMediumBlockSize + vState.TotalAllocatedLargeBlockSize;
  for I := Low(vState.SmallBlockTypeStates) to High(vState.SmallBlockTypeStates) do
    Result := Result + vState.SmallBlockTypeStates[I].UseableBlockSize * vState.SmallBlockTypeStates[I].AllocatedBlockCount;
end;

{ the list a setter replaced is the caller's to free }
procedure DropMemo(pObj: TmcORMFIX);
var
  vOld: TStringList;
begin
  vOld := pObj.MEMO;
  pObj.MEMO := nil;
  vOld.Free;
end;

procedure TestAssign;
var
  vSrc, vDst, vByI: TmcORMFIX;
  vChild: TFixChild;
begin
  vSrc := TmcORMFIX.Create(nil);
  vDst := TmcORMFIX.Create(nil);
  vByI := TmcORMFIX.Create(nil);
  vChild := TFixChild.Create(nil);
  try
    Fill(vSrc);
    vDst.Modified := False;
    vDst.Assign(vSrc);
    Check('A1 Assign copies every scalar column', SameScalars(vDst));
    Check('A2 Assign leaves the source as it was', SameScalars(vSrc) and (vSrc.MEMO.Text = 'note'#13#10));
    Check('A3 Assign does not set Modified (fields, like AssignI)', not vDst.Modified);
    vByI.AssignI(vSrc);
    Check('A4 owned list: same text, own instance', (vDst.MEMO <> vSrc.MEMO) and (vDst.MEMO.Text = vSrc.MEMO.Text));
    Check('A4b AssignI still shares the list (unchanged)', vByI.MEMO = vSrc.MEMO);
    Detach(vByI);
    vChild.Assign(vSrc);
    Check('A5 descendant receives the copy', SameScalars(vChild));
  finally
    vChild.Free;
    vByI.Free;
    vDst.Free;
    vSrc.Free;
  end;
end;

procedure TestAssignTo;
var
  vSrc, vDst: TmcORMFIX;
begin
  vSrc := TmcORMFIX.Create(nil);
  vDst := TmcORMFIX.Create(nil);
  try
    Fill(vSrc);
    vDst.Modified := False;
    TFixAccess(vSrc).AssignTo(vDst);
    Check('T1 AssignTo copies every scalar column', SameScalars(vDst));
    Check('T2 AssignTo leaves Self as it was', SameScalars(vSrc) and (vSrc.MEMO.Text = 'note'#13#10));
    Check('T3 AssignTo sets Dest.Modified (property setters)', vDst.Modified);
    Check('T4 owned list: same text, own instance', (vDst.MEMO <> vSrc.MEMO) and (vDst.MEMO.Text = vSrc.MEMO.Text));
  finally
    vDst.Free;
    vSrc.Free;
  end;
end;

procedure TestOwnedList;
var
  vSrc, vDst: TmcORMFIX;
  vBefore: NativeUInt;
  vHit, I: Integer;
begin
  vSrc := TmcORMFIX.Create(nil);
  vDst := TmcORMFIX.Create(nil);
  try
    Fill(vSrc);
    vDst.Assign(vSrc);
    vSrc.MEMO.Text := 'changed';
    Check('O1 changing the source does not change the copy (Assign)', vDst.MEMO.Text = 'note'#13#10);
    vDst.MEMO.Text := 'other';
    Check('O2 changing the copy does not change the source', vSrc.MEMO.Text = 'changed'#13#10);
    TFixAccess(vSrc).AssignTo(vDst);
    vSrc.MEMO.Text := 'again';
    Check('O3 AssignTo: equal text, own instance, independent', (vDst.MEMO <> vSrc.MEMO) and (vDst.MEMO.Text = 'changed'#13#10));
    { nil source list: the copy is emptied, not nilled }
    DropMemo(vSrc);
    vDst.MEMO.Text := 'x';
    vDst.Assign(vSrc);
    Check('O4 nil source list empties the copy (Assign)', (vDst.MEMO <> nil) and (vDst.MEMO.Count = 0));
    vDst.MEMO.Text := 'x';
    TFixAccess(vSrc).AssignTo(vDst);
    Check('O5 nil source list empties the copy (AssignTo)', (vDst.MEMO <> nil) and (vDst.MEMO.Count = 0));
    { nil destination list }
    vSrc.MEMO := TStringList.Create;
    vSrc.MEMO.Text := 'kept';
    DropMemo(vDst);
    vHit := 0;
    try
      vDst.Assign(vSrc);
    except
      Inc(vHit);
    end;
    try
      TFixAccess(vSrc).AssignTo(vDst);
    except
      Inc(vHit);
    end;
    Check('O6 nil destination list: no exception either way, nothing created', (vHit = 0) and (vDst.MEMO = nil));
    { self-assignment }
    vSrc.Assign(vSrc);
    TFixAccess(vSrc).AssignTo(vSrc);
    Check('O7 self-assignment keeps the list', vSrc.MEMO.Text = 'kept'#13#10);
  finally
    vDst.Free;
    vSrc.Free;
  end;
  { free both: no double free, no leak (the test objects own what they made) }
  vHit := 0;
  vBefore := HeapUsed;
  for I := 1 to 200 do
  try
    vSrc := TmcORMFIX.Create(nil);
    vDst := TmcORMFIX.Create(nil);
    Fill(vSrc);
    vDst.Assign(vSrc);
    TFixAccess(vSrc).AssignTo(vDst);
    vDst.Free;
    vSrc.Free;
  except
    Inc(vHit);
  end;
  Check('O8 freeing both raises nothing', vHit = 0);
  Check('O9 no leak over 200 Assign / AssignTo / Free rounds', HeapUsed <= vBefore + 4096);
end;

procedure TestNotOwned;
var
  vSrc, vDst: TmcORMFIX;
  vPic: TPicture;
begin
  vSrc := TmcORMFIX.Create(nil);
  vDst := TmcORMFIX.Create(nil);
  vPic := TPicture.Create;
  try
    vSrc.PIC := vPic;
    vDst.Assign(vSrc);
    Check('N1 a class column the generator does not own stays a reference (Assign)', vDst.PIC = vPic);
    vDst.PIC := nil;
    TFixAccess(vSrc).AssignTo(vDst);
    Check('N2 same for AssignTo', vDst.PIC = vPic);
    vDst.PIC := nil;
    vSrc.PIC := nil;
  finally
    vPic.Free;
    vDst.Free;
    vSrc.Free;
  end;
end;

procedure TestForeign;
var
  vDst: TmcORMFIX;
  vOther: TStringList;
  vHit: Integer;
begin
  vDst := TmcORMFIX.Create(nil);
  vOther := TStringList.Create;
  vHit := 0;
  try
    try
      vDst.Assign(vOther);
    except
      on E: EConvertError do
        Inc(vHit);
    end;
    try
      TFixAccess(vDst).AssignTo(vOther);
    except
      on E: EConvertError do
        Inc(vHit);
    end;
    Check('F1 a foreign class still goes to inherited (EConvertError, both directions)', vHit = 2);
  finally
    vOther.Free;
    vDst.Free;
  end;
end;

procedure TestPlainAndEmpty;
var
  vA, vB: TmcPLAINFIX;
  vE, vF: TmcEMPTYFIX;
begin
  vA := TmcPLAINFIX.Create(nil);
  vB := TmcPLAINFIX.Create(nil);
  vE := TmcEMPTYFIX.Create(nil);
  vF := TmcEMPTYFIX.Create(nil);
  try
    vA.LINE_NO := 9;
    vA.CODE := 'x';
    vB.Assign(vA);
    Check('P1 Assign on a table without class-typed columns', (vB.LINE_NO = 9) and (vB.CODE = 'x'));
    vA.CODE := 'y';
    TPlainAccess(vA).AssignTo(vB);
    Check('P2 AssignTo on it', vB.CODE = 'y');
    vE.Assign(vF);
    Check('P3 table without stored columns: Assign does nothing and raises nothing', True);
  finally
    vF.Free;
    vE.Free;
    vB.Free;
    vA.Free;
  end;
end;

procedure TestStream;
var
  vA, vB: TmcORMFIX;
  vS: TABZMemoryStream;
begin
  vA := TmcORMFIX.Create(nil);
  vB := TmcORMFIX.Create(nil);
  vS := TABZMemoryStream.Create;
  try
    vA.STATUS := osOpen;
    vA.FLAG8 := 0;
    Check('S1 Writer', vA.Writer(vS));
    vS.Position := 0;
    Check('S2 Reader reads the enumeration through its own local', vB.Reader(vS) and (vB.STATUS = osOpen));
  finally
    vS.Free;
    vB.Free;
    vA.Free;
  end;
end;

begin
  try
    TestAssign;
    TestAssignTo;
    TestOwnedList;
    TestNotOwned;
    TestForeign;
    TestPlainAndEmpty;
    TestStream;
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
