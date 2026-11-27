unit MembFresh;

{ v156 MEM-B fixture: fresh-instance-as-argument, resolved. A line that must report carries the FIRE marker. }

interface

uses
  MembTypes;

procedure Leaks(AKeeper: TKeeper);
procedure Owned(AKeeper: TKeeper; AOwner: TComponent);
procedure NotFresh(AKeeper: TKeeper);

implementation

procedure Leaks(AKeeper: TKeeper);
begin
  ReadOnly(TFoo.Create); // FIRE fresh-instance-as-argument
  AKeeper.Show(TFoo.Create); // FIRE fresh-instance-as-argument
  AKeeper.ShowConst(TFoo.Create); // FIRE fresh-instance-as-argument
  AKeeper.Second(1, TFoo.Create); // FIRE fresh-instance-as-argument
  ShowObject(TFoo.Create()); // FIRE fresh-instance-as-argument
  ShowObject(TWidget.Create(nil)); // FIRE fresh-instance-as-argument
end;

procedure Owned(AKeeper: TKeeper; AOwner: TComponent);
var
  Other: TKeeper;
begin
  AKeeper.Keep(TFoo.Create);
  Other:= TKeeper.Create(TFoo.Create);
  Other.Free;
  AKeeper.Same(TFoo.Create).Free;
  AKeeper.Eat(TFoo.Create);
  AKeeper.Pass(TFoo.Create);
  AKeeper.Later(TFoo.Create);
  AKeeper.Hook(TFoo.Create);
  StoreGlobal(TFoo.Create);
  ReleaseIt(TFoo.Create);
  NotDeclared(TFoo.Create);
  TakeBar(TBar.Create);
  ShowObject(TWidget.Create(AOwner));
end;

procedure NotFresh(AKeeper: TKeeper);
var
  Foo: TFoo;
begin
  Foo:= TFoo.Create;
  try
    AKeeper.Show(Foo);
    ReadOnly(Foo);
  finally
    Foo.Free;
  end;
end;

end.
