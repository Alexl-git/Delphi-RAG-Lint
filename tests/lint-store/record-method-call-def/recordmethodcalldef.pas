unit recordmethodcalldef;

interface

type
  TRecState = record
    Total: Integer;
    procedure Reset;
    function Peek: Integer;
  end;

  TFooClass = class
    procedure DoStuff;
  end;

procedure NeedsVarParam(var AX: Integer);

procedure Fixture1RecordMethodInit;
procedure Fixture2ClassMethodStillFlagged;
procedure Fixture3RecordFieldReadNoInit;
procedure Fixture4VarArgDefStillWorks;

implementation

procedure TRecState.Reset;
begin
  Total := 0;
end;

function TRecState.Peek: Integer;
begin
  Result := Total;
end;

procedure TFooClass.DoStuff;
begin
  Total := 0;
end;

procedure NeedsVarParam(var AX: Integer);
begin
  AX := 42;
end;

{ Fixture 1: a record local initialised via its own method call (R.Reset),
  then used -- must NOT flag used-before-assignment. This is the false
  positive the task fixes; mirrors YADF.LineScan.ComputeBlockCommentLock,
  where St.Reset is flagged even though it is the initialising call. }
procedure Fixture1RecordMethodInit;
var
  R: TRecState;
  V: Integer;
begin
  R.Reset;
  V := R.Peek;
end;

{ Fixture 2: a class-typed local with a method called on it before any
  assignment -- MUST still flag. A method call on an uninitialised class
  reference is a genuine nil-dereference bug; the fix is restricted to
  tcRecord and must not widen to classes. }
procedure Fixture2ClassMethodStillFlagged;
var
  C: TFooClass;
begin
  C.DoStuff;
end;

{ Fixture 3: a record local whose FIELD (not a method) is read before
  anything is called or assigned. Total is a plain field (skField), not a
  callable member, so the record-method-call-defines-the-local seam does not
  apply here -- this must still flag. }
procedure Fixture3RecordFieldReadNoInit;
var
  R2: TRecState;
  V2: Integer;
begin
  V2 := R2.Total;
end;

{ Fixture 4: pre-existing CallDefs behaviour (a var-argument call assigns its
  actual) must not regress. }
procedure Fixture4VarArgDefStillWorks;
var
  V3: Integer;
begin
  NeedsVarParam(V3);
  V3 := V3 + 1;
end;

end.
