unit UOther;

{ Second unit of the project: calls TOwn.UsedElsewhere, which keeps it public. }

interface

procedure CallOwn;

implementation

uses
  UOwn;

procedure CallOwn;
var
  O: TOwn;
begin
  O:= TOwn.Create;
  try
    O.UsedElsewhere;
  finally
    O.Free;
  end;
end;

end.
