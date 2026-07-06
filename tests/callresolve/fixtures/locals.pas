unit locals;

interface

type
  TWorker = class
    procedure Go;
  end;

implementation

procedure TWorker.Go;
var
  L: TWorker;
  N: Integer;
  X, Y: TWorker;
begin
  L := Self;
  N := 0;
  X := L;
  Y := L;
end;

end.
