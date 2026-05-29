unit RuleTest;
interface
implementation
uses Vcl.Dialogs;

procedure GotoExample;
label OutLabel;
var I: Integer;
begin
  for I := 1 to 10 do
    if I = 5 then goto OutLabel;
  OutLabel:
  WriteLn('done');
end;

procedure WithExample;
var L: TStrings;
begin
  L := TStringList.Create;
  with L do
  begin
    Add('foo');
    Add('bar');
  end;
end;

procedure MagicExample;
var X: Integer;
begin
  X := 42 * 3.14159;
end;

procedure CaseNoElse;
var X: Integer;
begin
  case X of
    1: WriteLn('one');
    2: WriteLn('two');
  end;
end;

procedure EmptyBody;
begin
end;

// TODO: fix this later
// FIXME: broken
procedure AssertExample;
var X: Integer;
begin
  X := 0;
  Assert(X > 0);
  Assert(X > 0, 'X must be positive');
end;

procedure NestedWithExample;
var L1, L2: TStringList;
begin
  L1 := TStringList.Create;
  L2 := TStringList.Create;
  with L1 do
    with L2 do
      Add('nested');
  L1.Free;
  L2.Free;
end;

{ v0.35: boolean-comparison-true }
procedure BoolCompareExample;
var B: Boolean;
begin
  B := True;
  if B = True then WriteLn('yes');
  if B = False then WriteLn('no');
end;

{ v0.35: redundant-as-tobject }
procedure AsObjectExample;
var Obj: TObject;
begin
  Obj := TStringList.Create as TObject;
  Obj.Free;
end;

{ v0.35: inherited-bare }
type
  TBaseClass = class
    procedure DoSomething; virtual;
  end;

  TDerivedClass = class(TBaseClass)
    procedure DoSomething; override;
  end;

procedure TBaseClass.DoSomething;
begin
end;

procedure TDerivedClass.DoSomething;
begin
  inherited;
end;

end.
