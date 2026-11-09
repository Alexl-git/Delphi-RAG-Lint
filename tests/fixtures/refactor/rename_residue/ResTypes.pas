unit ResTypes;

{ Fixture of tests\autotest\run_rename_residue.ps1: a default property, an indexed property, a list descendant. }

interface

uses
  System.Generics.Collections;

type
  TItem = class
  public
    Kind: Integer;
    Capacity: Integer;
    constructor Create(pKind: Integer);
  end;

  TBag = class
  private
    FList: TObjectList<TItem>;
    function GetItem(pIndex: Integer): TItem;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(pItem: TItem);
    function FirstKind: Integer;
    property Items[pIndex: Integer]: TItem read GetItem; default;
  end;

  TBagChild = class(TBag)
  end;

  { No default property: `Shelf[0]` would not compile, `Shelf.Slots[0]` is the element. }
  TShelf = class
  private
    FBag: TBag;
    function GetSlot(pIndex: Integer): TItem;
  public
    constructor Create(pBag: TBag);
    property Slots[pIndex: Integer]: TItem read GetSlot;
    property Bag: TBag read FBag;
  end;

  TItemList = class(TObjectList<TItem>)
  end;

implementation

constructor TItem.Create(pKind: Integer);
begin
  inherited Create;
  Kind:= pKind;
  Capacity:= pKind * 2;
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

procedure TBag.Add(pItem: TItem);
begin
  FList.Add(pItem);
end;

function TBag.FirstKind: Integer;
begin
  Result:= Items[0].Kind;
end;

constructor TShelf.Create(pBag: TBag);
begin
  inherited Create;
  FBag:= pBag;
end;

function TShelf.GetSlot(pIndex: Integer): TItem;
begin
  Result:= FBag[pIndex];
end;

end.