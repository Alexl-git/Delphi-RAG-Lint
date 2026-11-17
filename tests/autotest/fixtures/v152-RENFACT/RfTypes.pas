unit RfTypes;

{ Fixture of tests\autotest\run_v152_RENFACT.ps1 (E-RENAME-RESIDUE, lane v152 RENFACT):
  default properties reached WITHOUT their name (`Bag[0]`), next to indexed properties
  reached with it (`Shelf.Bags[0]`), arrays, strings and a library list heritage. }

interface

uses
  System.Generics.Collections;

type
  TItem = class
  public
    Kind: Integer;
    constructor Create(pKind: Integer);
  end;

  TBag = class
  private
    FList: TObjectList<TItem>;
    function GetItem(pIndex: Integer): TItem;
    procedure SetItem(pIndex: Integer; pValue: TItem);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(pItem: TItem);
    function FirstKind: Integer;
    function SelfKind: Integer;
    property Items[pIndex: Integer]: TItem read GetItem write SetItem; default;
  end;

  TBagChild = class(TBag)
  end;

  { No default property: `Shelf[0]` does not compile; `Shelf.Bags[0]` is the property's own index. }
  TShelf = class
  private
    FBag: TBag;
    function GetBag(pIndex: Integer): TBag;
    function GetSlot(pIndex: Integer): TItem;
  public
    constructor Create(pBag: TBag);
    property Bags[pIndex: Integer]: TBag read GetBag;
    property Slots[pIndex: Integer]: TItem read GetSlot;
    property Bag: TBag read FBag;
  end;

  TGrid = class
  private
    function GetCell(pX, pY: Integer): Integer;
  public
    property Cells[pX, pY: Integer]: Integer read GetCell; default;
  end;

  TRack = class
  private
    FBag: TBag;
    function GetBag(pIndex: Integer): TBag;
  public
    constructor Create(pBag: TBag);
    property Bags[pIndex: Integer]: TBag read GetBag; default;
  end;

  IRow = interface
    ['{6C3E2B9A-41D7-4F0E-9B52-0D8E7A1C5F21}']
    function GetValue(pIndex: Integer): Integer;
    property Values[pIndex: Integer]: Integer read GetValue; default;
  end;

  TRow = class(TInterfacedObject, IRow)
  public
    function GetValue(pIndex: Integer): Integer;
  end;

  TItemList = class(TObjectList<TItem>)
  end;

implementation

constructor TItem.Create(pKind: Integer);
begin
  inherited Create;
  Kind:= pKind;
end;

constructor TBag.Create;
begin
  inherited Create;
  FList:= TObjectList<TItem>.Create(True);
end;

destructor TBag.Destroy;
begin
  FList.Free;
  inherited Destroy;
end;

function TBag.GetItem(pIndex: Integer): TItem;
begin
  Result:= FList[pIndex];
end;

procedure TBag.SetItem(pIndex: Integer; pValue: TItem);
begin
  FList[pIndex]:= pValue;
end;

procedure TBag.Add(pItem: TItem);
begin
  FList.Add(pItem);
end;

function TBag.FirstKind: Integer;
begin
  Result:= Items[0].Kind;
end;

function TBag.SelfKind: Integer;
begin
  Result:= Self[0].Kind;
end;

constructor TShelf.Create(pBag: TBag);
begin
  inherited Create;
  FBag:= pBag;
end;

function TShelf.GetBag(pIndex: Integer): TBag;
begin
  Result:= FBag;
end;

function TShelf.GetSlot(pIndex: Integer): TItem;
begin
  Result:= FBag[pIndex];
end;

function TGrid.GetCell(pX, pY: Integer): Integer;
begin
  Result:= pX * 10 + pY;
end;

constructor TRack.Create(pBag: TBag);
begin
  inherited Create;
  FBag:= pBag;
end;

function TRack.GetBag(pIndex: Integer): TBag;
begin
  Result:= FBag;
end;

function TRow.GetValue(pIndex: Integer): Integer;
begin
  Result:= pIndex + 100;
end;

end.
