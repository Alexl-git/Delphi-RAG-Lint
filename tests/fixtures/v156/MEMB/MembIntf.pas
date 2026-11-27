unit MembIntf;

{ v156 MEM-B fixture: class-passed-as-interface. A line that must report carries the FIRE marker. }

interface

uses
  MembTypes;

procedure FreedAfter;
procedure UsedAfter;
procedure DeepClass;
procedure FreshToConst;
procedure LastUse;
procedure NotCounted;
procedure InterfaceVariable;
procedure ClassParameter;

implementation

procedure FreedAfter;
var
  Bar: TBar;
begin
  Bar:= TBar.Create;
  UseBar(Bar); // FIRE class-passed-as-interface
  Bar.Free;
end;

procedure UsedAfter;
var
  Bar: TBar;
begin
  Bar:= TBar.Create;
  TakeBar(Bar); // FIRE class-passed-as-interface
  Bar.Ping;
end;

procedure DeepClass;
var
  Bar: TDeepBar;
begin
  Bar:= TDeepBar.Create;
  TakeBar(Bar); // FIRE class-passed-as-interface
  Bar.Ping;
end;

procedure FreshToConst;
begin
  UseBar(TBar.Create); // FIRE class-passed-as-interface
  TakeBar(TBar.Create);
end;

procedure LastUse;
var
  Bar: TBar;
begin
  Bar:= TBar.Create;
  Bar.Ping;
  TakeBar(Bar);
end;

procedure NotCounted;
var
  Bar: TPlainBar;
begin
  Bar:= TPlainBar.Create;
  UseBar(Bar);
  Bar.Free;
  UseBar(TPlainBar.Create);
end;

procedure InterfaceVariable;
var
  Bar: IBar;
begin
  Bar:= TBar.Create;
  UseBar(Bar);
  Bar.Ping;
end;

procedure ClassParameter;
var
  Foo: TFoo;
begin
  Foo:= TFoo.Create;
  ReadOnly(Foo);
  Foo.Free;
end;

end.
