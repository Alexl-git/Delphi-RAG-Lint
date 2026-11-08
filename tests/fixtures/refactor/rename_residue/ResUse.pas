unit ResUse;

interface

procedure RunAll;

implementation

uses
  System.SysUtils, System.Classes, ResTypes, ResLocal, ResA, ResB, ResSplit;

procedure RunAll;
var
  Last : TPair;
  First: ResA.TPair;
  Bag  : TBag;
  Child: TBagChild;
  Shelf: TShelf;
  List : TItemList;
  Lines: TStringList;
begin
  Last.Kind:= 1;
  Last.OnlyB:= 2;
  First.Kind:= 3;
  First.OnlyA:= 4;
  WriteLn('pairs ', Last.Kind, ' ', Last.OnlyB, ' ', First.Kind, ' ', First.OnlyA);

  Bag:= TBag.Create;
  Bag.Add(TItem.Create(5));
  WriteLn('default ', Bag[0].Kind);
  WriteLn('items ', Bag.Items[0].Kind);
  WriteLn('first ', Bag.FirstKind);

  Child:= TBagChild.Create;
  Child.Add(TItem.Create(6));
  WriteLn('inherited ', Child[0].Kind);

  Shelf:= TShelf.Create(Bag);
  WriteLn('slots ', Shelf.Slots[0].Kind);
  WriteLn('shelf ', Shelf.Bag[0].Kind);

  List:= TItemList.Create(True);
  List.Add(TItem.Create(7));
  WriteLn('descendant ', List[0].Kind, ' ', List[0].Capacity);

  Lines:= TStringList.Create;
  Lines.Capacity:= 4;
  WriteLn('library ', Lines.Capacity);

  Lines.Free;
  List.Free;
  Shelf.Free;
  Child.Free;
  Bag.Free;
  RunLocal;
  RunSplit;
end;

end.