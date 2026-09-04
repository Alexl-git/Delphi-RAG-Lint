unit uUuDeadConsumer;

{ Fixture: imports two units and references NOTHING from either.

  Both are genuine dead imports, and they differ in exactly one property -- one
  has an initialization section and one does not -- so this single file must
  produce one WARNING and one INFO in the same run. }

interface

uses
  uUuNoInit, uUuWithInit;

procedure ZzDoNothing;

implementation

procedure ZzDoNothing;
var
  I: Integer;
begin
  I:= 0;
  while I < 3 do
    Inc(I);
end;

end.
