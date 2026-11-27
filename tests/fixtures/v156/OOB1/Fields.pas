unit Fields;

interface

type
  TWork = class
  private
    FTemp: Integer;          // FIRE field-could-be-local
    FKept: Integer;
    FReadFirst: Integer;
    FShared: Integer;
    FIdx: Integer;           // FIRE field-could-be-local
  public
    FPub: Integer;
    procedure Run;
    procedure Other;
    procedure Cache;
    procedure Seed;
  end;

implementation

procedure TWork.Run;
begin
  FTemp:= 5;
  FTemp:= FTemp + 1;
  Writeln(FTemp);
  FIdx:= 0;
  while FIdx < 3 do Inc(FIdx);
  FKept:= 1;
  FPub:= 2;
end;

procedure TWork.Other;
begin
  Writeln(FKept);
  FShared:= 1;
end;

procedure TWork.Cache;
begin
  if FReadFirst = 0 then FReadFirst:= 7;
  Writeln(FReadFirst);
end;

procedure TWork.Seed;
begin
  FShared:= 2;
end;

end.
