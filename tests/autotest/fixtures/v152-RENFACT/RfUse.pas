unit RfUse;

interface

procedure RunAll;

implementation

uses
  System.SysUtils, RfTypes;

procedure RunAll;
var
  Bag  : TBag;
  Child: TBagChild;
  Shelf: TShelf;
  Grid : TGrid;
  Rack : TRack;
  Row  : IRow;
  List : TItemList;
  Arr  : array [0 .. 1] of TItem;
  Txt  : string;
  N    : Integer;
begin
  Bag:= TBag.Create;
  Bag.Add(TItem.Create(5));
  WriteLn('default ', Bag[0].Kind);
  WriteLn('named ', Bag.Items[0].Kind);
  Bag[0]:= TItem.Create(6);
  WriteLn('first ', Bag.FirstKind, ' ', Bag.SelfKind);

  Child:= TBagChild.Create;
  Child.Add(TItem.Create(7));
  WriteLn('inherited ', Child[0].Kind);

  Shelf:= TShelf.Create(Bag);
  WriteLn('property then default ', Shelf.Bag[0].Kind);
  WriteLn('own index ', Shelf.Bags[0].FirstKind);
  WriteLn('own index then default ', Shelf.Bags[0][0].Kind);
  WriteLn('slots ', Shelf.Slots[0].Kind);

  Grid:= TGrid.Create;
  N:= Grid[1, 2];
  WriteLn('grid ', N);

  Rack:= TRack.Create(Bag);
  WriteLn('nested ', Rack[0][0].Kind);

  Row:= TRow.Create;
  WriteLn('interface ', Row[3]);

  List:= TItemList.Create(False);
  List.Add(Bag[0]);
  WriteLn('library heritage ', List[0].Kind);

  Arr[0]:= Bag[0];
  Arr[1]:= nil;
  Txt:= 'abc';
  WriteLn('array ', Arr[0].Kind, ' string ', Txt[2]);

  List.Free;
  Rack.Free;
  Grid.Free;
  Shelf.Free;
  Child.Free;
  Bag.Free;
end;

end.
