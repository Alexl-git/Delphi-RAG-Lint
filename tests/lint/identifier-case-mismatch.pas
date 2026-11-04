unit IdentifierCaseMismatch;

interface

procedure Hits(Param1: Integer);
procedure Controls(Param1: Integer);

implementation

type
  TRec = record
    mycounter: Integer;
  end;

procedure Hits(Param1: Integer);
var
  MyCounter: Integer;
begin
  mycounter := 1; // HIT
  MyCounter := MYCOUNTER + mycounter; // HIT
  if PARAM1 > 0 then // HIT
    MyCounter := 0;
  var Inlined := MyCounter;
  Hits(inlined); // HIT
end;

procedure Controls(Param1: Integer);
var
  MyCounter: Integer;
  R: TRec;
  Dup: Integer;
begin
  MyCounter := Param1; // NOHIT
  R.mycounter := MyCounter; // NOHIT
  with R do
    mycounter := 2; // NOHIT
  Dup := R.MyCounter; // NOHIT
  Controls(Dup);
end;

procedure Outer;
var
  Shared: Integer;

  procedure Nested;
  var
    SHARED: Integer;
  begin
    SHARED := 1; // NOHIT
    Controls(SHARED);
  end;

begin
  Shared := 2;
  Controls(Shared);
  Nested;
end;

end.