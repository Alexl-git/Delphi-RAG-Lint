unit StringListObjectsLeak;

interface

uses
  System.Classes;

type
  TCustomer = class
  end;

implementation

procedure DirectLeak;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.AddObject('a', TCustomer.Create); // MUST-FIRE direct create
  finally
    L.Free;
  end;
end;

procedure LocalLeak;
var
  L: TStringList;
  C: TCustomer;
begin
  L := TStringList.Create;
  try
    C := TCustomer.Create;
    L.InsertObject(0, 'b', C); // MUST-FIRE created local, not freed
  finally
    L.Free;
  end;
end;

procedure IndexedLeak;
var
  Names: TStringList;
begin
  Names := TStringList.Create;
  try
    Names.Add('x');
    Names.Objects[0] := TCustomer.Create; // MUST-FIRE indexed assignment
  finally
    Names.Free;
  end;
end;

procedure ListOwnsObjects;
var
  L: TStringList;
begin
  L := TStringList.Create(True);
  try
    L.AddObject('c', TCustomer.Create); // owned: silent
  finally
    L.Free;
  end;
end;

procedure ObjectFreedAfterwards;
var
  L: TStringList;
  I: Integer;
begin
  L := TStringList.Create;
  try
    L.AddObject('d', TCustomer.Create);
  finally
    for I := 0 to L.Count - 1 do
      L.Objects[I].Free; // objects freed: silent
    L.Free;
  end;
end;

end.
