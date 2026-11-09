unit DsUse;

interface

procedure RunAll;

implementation

uses
  DsTypes;

procedure RunAll;
begin
  var B:= TBoxKid.Create;
  try
    B.Tally:= 7;
    B.Extra:= 3;
    Writeln('tally ', B.Tally, ' spare ', B.Spare, ' extra ', B.Extra);
  finally
    B.Free;
  end;
end;

end.