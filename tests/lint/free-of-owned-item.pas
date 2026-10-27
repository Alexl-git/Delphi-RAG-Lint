unit free_of_owned_item;

{ free-of-owned-item fixture.  HIT marker = rule fires, OK marker = silent. }

interface

implementation

uses
  System.Classes, System.Contnrs, System.Generics.Collections;

type
  TThing = class
  end;

procedure ForeachFree;
var
  L: TObjectList<TThing>;
  O: TThing;
begin
  L:= TObjectList<TThing>.Create;
  try
    for O in L do
      O.Free; {HIT}
  finally
    L.Free;
  end;
end;

procedure IndexedFree;
var
  L: TObjectList;
  O: TObject;
begin
  L:= TObjectList.Create;
  try
    O:= L[0];
    O.Free; {HIT}
  finally
    L.Free;
  end;
end;

procedure AddedFree;
var
  L: TComponentList;
  O: TComponent;
begin
  L:= TComponentList.Create;
  try
    O:= TComponent.Create(nil);
    L.Add(O);
    O.Free; {HIT}
  finally
    L.Free;
  end;
end;

procedure NotOwning;
var
  L: TObjectList<TThing>;
  O: TThing;
begin
  L:= TObjectList<TThing>.Create(False);
  try
    for O in L do
      O.Free; {OK}
  finally
    L.Free;
  end;
end;

procedure ExtractedFirst;
var
  L: TObjectList<TThing>;
  O: TThing;
begin
  L:= TObjectList<TThing>.Create;
  try
    O:= L[0];
    L.Extract(O);
    O.Free; {OK}
  finally
    L.Free;
  end;
end;

end.
