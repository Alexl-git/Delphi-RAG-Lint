unit uExtrUse;

interface

uses
  ExtrLibClasses;

type
  TExtrBox = class
  public
    Size: Integer;
    procedure Grow;
  end;

  TExtrBag<T> = class
  public
    constructor Create;
  end;

  TExtrHolder = class
  public
    Box: TExtrBox;
  end;

procedure ExtrUseList;
function ExtrColor(pOwner: TObject): Integer;
function ExtrMakeBox: TExtrBox;
procedure ExtrWith(pHolder: TExtrHolder);
procedure ExtrWithLib(pOwner: TObject);
procedure ExtrGenerics;
function ExtrCasts(pOwner: TObject): Integer;

implementation

constructor TExtrBag<T>.Create;
begin
end;

procedure TExtrBox.Grow;
begin
  Inc(Size);
end;

procedure ExtrUseList;
var
  L: TStringList;
begin
  L := TStringList.Create;
  L.Add('x');
end;

function ExtrColor(pOwner: TObject): Integer;
begin
  Result := StyleServices(pOwner).GetSystemColor(1);
end;

function ExtrMakeBox: TExtrBox;
begin
  Result := TExtrBox.Create;
end;

procedure ExtrWith(pHolder: TExtrHolder);
begin
  with pHolder.Box do
  begin
    Grow;
    Size := 2;
  end;
  ExtrMakeBox.Grow;
  TExtrBox(pHolder).Grow;
end;

procedure ExtrWithLib(pOwner: TObject);
var
  L: TStringList;
begin
  L := TStringList.Create;
  with L do
    Add('a');
  with StyleServices(pOwner) do
    GetSystemColor(2);
end;

procedure ExtrGenerics;
begin
  TObjectList<TExtrBox>.Create(True).Free;
  TExtrBag<Integer>.Create.Free;
end;

function ExtrCasts(pOwner: TObject): Integer;
begin
  TStringList(pOwner).Add('c');
  Result := Length(Copy('abc', 1, 2).Trim);
end;

end.