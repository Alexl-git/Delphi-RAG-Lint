unit TScanFixture;

interface

uses
  System.Classes, System.Generics.Collections;

type
  TNameMap = TDictionary<string, Integer>;
  TMyList = class(TStringList);
  TOwner = class
  private
    FNames, FOther: TMyList;
    FMap: TNameMap;
  public
    procedure Run;
  end;

function Lookup(const AKey: string): Integer;
procedure Keep;

implementation

var
  GMap: TNameMap;

function Lookup(const AKey: string): Integer;
begin
  Result:= GMap[AKey];
end;

procedure Keep;
var
  L, M: TStringList;
  Idx: Integer;
begin
  L:= TStringList.Create;
  M:= TStringList.Create;
  try
    L.AddObject('a', TStringList.Create);
    if L.Find('a', Idx) then M.Add('x');
  finally
    M.Free;
    L.Free;
  end;
end;

procedure TOwner.Run;
var
  Idx: Integer;
begin
  Self.FNames:= TMyList.Create;
  FNames.Duplicates:= dupIgnore;
  if FNames.Find('b', Idx) then FMap.Add('b', Idx);
  Idx:= FMap['c'];
end;

end.