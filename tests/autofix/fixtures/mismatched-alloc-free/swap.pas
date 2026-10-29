unit swap;

interface

implementation

type
  TRec = record
    A: Integer;
  end;
  PRec = ^TRec;

procedure P1;
var
  P: PRec;
begin
  New(P);
  FreeMem(P);
end;

procedure P2;
var
  O: TObject;
begin
  O:= TObject.Create;
  FreeMem(O);
end;

procedure P3;
var
  Q: Pointer;
begin
  GetMem(Q, 16);
  Dispose(Q);
end;

end.
