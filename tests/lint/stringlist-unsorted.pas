unit StringListUnsorted;

interface

uses
  System.Classes;

type
  TNames = class
  private
    FNames: TStringList;
    FSortedNames: TStringList;
  public
    constructor Create;
    destructor Destroy; override;
    function Has(const AName: string): Boolean;
    function HasSorted(const AName: string): Boolean;
  end;

implementation

constructor TNames.Create;
begin
  inherited Create;
  FNames := TStringList.Create;
  FSortedNames := TStringList.Create;
  FSortedNames.Sorted := True;
end;

destructor TNames.Destroy;
begin
  FSortedNames.Free;
  FNames.Free;
  inherited Destroy;
end;

function TNames.Has(const AName: string): Boolean;
var
  Idx: Integer;
begin
  Result := FNames.Find(AName, Idx); // MUST-FIRE never sorted
end;

function TNames.HasSorted(const AName: string): Boolean;
var
  Idx: Integer;
begin
  Result := FSortedNames.Find(AName, Idx); // sorted in the constructor: silent
end;

procedure LocalFind;
var
  L: TStringList;
  Idx: Integer;
begin
  L := TStringList.Create;
  try
    L.LoadFromFile('x.txt');
    if L.Find('a', Idx) then // MUST-FIRE local, never sorted
      L.Delete(Idx);
    L.Duplicates := dupIgnore; // MUST-FIRE no effect on an unsorted list
  finally
    L.Free;
  end;
end;

procedure LocalSortedFirst;
var
  L: TStringList;
  Idx: Integer;
begin
  L := TStringList.Create;
  try
    L.LoadFromFile('x.txt');
    L.Sort;
    if L.Find('a', Idx) then // sorted explicitly: silent
      L.Delete(Idx);
  finally
    L.Free;
  end;
end;

procedure ParamNotCreatedHere(const AList: TStringList);
var
  Idx: Integer;
begin
  AList.Find('a', Idx); // not created in this unit: silent
end;

end.
