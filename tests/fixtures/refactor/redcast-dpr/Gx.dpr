program Gx;
{$APPTYPE CONSOLE}
uses
  GxU in 'GxU.pas';

var
  GV: TGxBase;

function GxOv(pAt: Integer): TGxBase; overload;
begin
  Result:= GV;
end;

function GxOv(const pAt: string): TGxBase; overload;
begin
  Result:= GV;
end;

function GxOne: TGxBase;
begin
  Result:= GV;
end;

begin
  GV:= TGxBase(Gx); // FIX
  GV:= TGxBase(GV); // FIX
  GV:= TGxBase(GxOne); // FIX
  GV:= TGxBase(GxOv(1)); // REFUSE overloaded-operand
  GV:= TGxBase(GxUOv(1)); // REFUSE overloaded-operand
end.
