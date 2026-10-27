unit FreshArg;

interface

implementation

uses
  System.Classes;

procedure UseList(const pList: TStringList);
begin
end;

procedure Bad;
begin
  UseList(TStringList.Create);
  UseList(TStringList.Create(True));
end;

procedure Good(pOwner: TComponent; pList: TList);
var
  L: TStringList;
begin
  pList.Add(TObject.Create);
  pList.Insert(0, TObject.Create);
  TButton.Create(pOwner);
  L := TStringList.Create;
  try
    UseList(L);
  finally
    L.Free;
  end;
  RegisterComponents('x', [TComponent.Create(nil)]);
  TStringList.Create(TStringList.Create);
end;

end.
