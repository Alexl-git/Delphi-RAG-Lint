unit MemaItems;

{ Fixture of 1.56 lane MEM-A: container-items-leak (G-01).
  A line that must report carries the FIRE marker; every other line must stay silent. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Contnrs;

type
  TFoo = class
  public
    Name: string;
    procedure Work;
  end;

  IBar = interface
    procedure Ping;
  end;

  TBar = class(TInterfacedObject, IBar)
  public
    procedure Ping;
  end;

  TRec = record
    V: Integer;
    constructor Create(AValue: Integer);
  end;

  TKeeper = class
  private
    FItems: TList<TFoo>;
  public
    procedure Expose;
  end;

procedure LeakDirect;
procedure LeakViaLocal;
procedure LeakDictionary;
procedure LeakNotOwningObjectList;
procedure LeakInlineVar;
procedure OkFreeLoop;
procedure OkIndexFreeLoop;
procedure OkOwningList;
function OkReturned: TList<TFoo>;
procedure OkPassedOn;
procedure OkRecordElement;
procedure OkNotFresh(AItem: TFoo);
procedure OkInterfaceElement;
procedure OkItemHandedOn;
procedure OkOwnsObjectsLater;
procedure OkOwnedComponent(AOwner: TComponent);
procedure OkLocalFreedItself;

implementation

procedure Consume(AList: TList<TFoo>);
begin
  AList.Clear;
end;

procedure Keep(AItem: TFoo);
begin
  AItem.Work;
end;

procedure TFoo.Work;
begin
  Name:= Name + '.';
end;

procedure TBar.Ping;
begin
end;

constructor TRec.Create(AValue: Integer);
begin
  V:= AValue;
end;

procedure LeakDirect;
var
  L: TList<TFoo>;
  I: Integer;
begin
  L:= TList<TFoo>.Create;
  try
    for I:= 1 to 3 do
      L.Add(TFoo.Create); // FIRE container-items-leak
    Writeln(L.Count);
  finally
    L.Free;
  end;
end;

procedure LeakViaLocal;
var
  L   : TList<TFoo>;
  Item: TFoo;
  X   : TFoo;
begin
  L:= TList<TFoo>.Create;
  try
    Item:= TFoo.Create;
    Item.Name:= 'a';
    L.Add(Item); // FIRE container-items-leak
    for X in L do
      X.Work;
  finally
    L.Free;
  end;
end;

procedure LeakDictionary;
var
  D: TDictionary<string, TFoo>;
begin
  D:= TDictionary<string, TFoo>.Create;
  try
    D.Add('a', TFoo.Create); // FIRE container-items-leak
    D.Add('b', TFoo.Create);
  finally
    D.Free;
  end;
end;

procedure LeakNotOwningObjectList;
var
  L: TObjectList<TFoo>;
begin
  L:= TObjectList<TFoo>.Create(False);
  try
    L.Add(TFoo.Create); // FIRE container-items-leak
  finally
    L.Free;
  end;
end;

procedure LeakInlineVar;
begin
  var L:= TList<TFoo>.Create;
  try
    L.Insert(0, TFoo.Create); // FIRE container-items-leak
  finally
    L.Free;
  end;
end;

procedure OkFreeLoop;
var
  L: TList<TFoo>;
  X: TFoo;
begin
  L:= TList<TFoo>.Create;
  try
    L.Add(TFoo.Create);
    for X in L do
      X.Free;
  finally
    L.Free;
  end;
end;

procedure OkIndexFreeLoop;
var
  L: TList;
  I: Integer;
begin
  L:= TList.Create;
  try
    L.Add(TFoo.Create);
    for I:= 0 to L.Count - 1 do
      TFoo(L[I]).Free;
  finally
    L.Free;
  end;
end;

procedure OkOwningList;
var
  L: TObjectList<TFoo>;
begin
  L:= TObjectList<TFoo>.Create;
  try
    L.Add(TFoo.Create);
  finally
    L.Free;
  end;
end;

function OkReturned: TList<TFoo>;
var
  L: TList<TFoo>;
begin
  L:= TList<TFoo>.Create;
  L.Add(TFoo.Create);
  Result:= L;
end;

procedure OkPassedOn;
var
  L: TList<TFoo>;
begin
  L:= TList<TFoo>.Create;
  try
    L.Add(TFoo.Create);
    Consume(L);
  finally
    L.Free;
  end;
end;

procedure OkRecordElement;
var
  L: TList<TRec>;
begin
  L:= TList<TRec>.Create;
  try
    L.Add(TRec.Create(1));
  finally
    L.Free;
  end;
end;

procedure OkNotFresh(AItem: TFoo);
var
  L: TList<TFoo>;
begin
  L:= TList<TFoo>.Create;
  try
    L.Add(AItem);
  finally
    L.Free;
  end;
end;

procedure OkInterfaceElement;
var
  L: TList<IBar>;
begin
  L:= TList<IBar>.Create;
  try
    L.Add(TBar.Create);
  finally
    L.Free;
  end;
end;

procedure OkItemHandedOn;
var
  L: TList<TFoo>;
begin
  L:= TList<TFoo>.Create;
  try
    L.Add(TFoo.Create);
    Keep(L[0]);
  finally
    L.Free;
  end;
end;

procedure OkOwnsObjectsLater;
var
  L: TObjectList<TFoo>;
begin
  L:= TObjectList<TFoo>.Create(False);
  try
    L.Add(TFoo.Create);
    L.OwnsObjects:= True;
  finally
    L.Free;
  end;
end;

procedure OkOwnedComponent(AOwner: TComponent);
var
  L: TList<TComponent>;
begin
  L:= TList<TComponent>.Create;
  try
    L.Add(TComponent.Create(AOwner));
  finally
    L.Free;
  end;
end;

procedure OkLocalFreedItself;
var
  L   : TList<TFoo>;
  Item: TFoo;
begin
  L:= TList<TFoo>.Create;
  try
    Item:= TFoo.Create;
    L.Add(Item);
    Item.Free;
  finally
    L.Free;
  end;
end;

procedure TKeeper.Expose;
var
  L: TList<TFoo>;
begin
  L:= TList<TFoo>.Create;
  L.Add(TFoo.Create);
  FItems:= L;
end;

end.
