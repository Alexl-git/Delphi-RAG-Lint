unit InterfacedObjectNilLeak;

interface

uses
  System.SysUtils;

type
  IThing = interface
    ['{5E8F7C60-3D7B-4C7A-9B73-0B71F4B9E001}']
  end;

  TThing = class(TInterfacedObject, IThing)
  public
    Value: Integer;
    procedure Subscribe;
  end;

  TDerivedThing = class(TThing);

  TPlain = class
  public
    Value: Integer;
  end;

function HitResult: TThing;
procedure Sink(const AThing: IThing);
function CtlFind(AFound: Boolean; AThing: TThing): TThing;

implementation

procedure TThing.Subscribe;
begin
  Value := 1;
end;

procedure Sink(const AThing: IThing);
begin
  if AThing = nil then Exit;
end;

function HitResult: TThing;
begin
  Result := TThing.Create;
  Result.Value := 1;
  Result := nil; // HIT
end;

procedure HitLocalDerived;
var
  T: TDerivedThing;
begin
  T := TDerivedThing.Create;
  try
    T.Value := 2;
  finally
    T := nil; // HIT
  end;
end;

function HitExcept: TThing;
begin
  try
    Result := TThing.Create;
    Result.Value := StrToInt('x');
  except
    Result := nil; // HIT
  end;
end;

{ the interface reference owns it: the nil only clears the alias }
procedure CtlEscapedToInterface;
var
  T: TThing;
  I: IThing;
begin
  T := TThing.Create;
  I := T;
  T := nil; // NOHIT
  Sink(I);
end;

procedure CtlPassed;
var
  T: TThing;
begin
  T := TThing.Create;
  Sink(T);
  T := nil; // NOHIT
end;

{ a method may hand Self to an interface holder }
procedure CtlMethodCall;
var
  T: TThing;
begin
  T := TThing.Create;
  T.Subscribe;
  T := nil; // NOHIT
end;

procedure CtlFreed;
var
  T: TThing;
begin
  T := TThing.Create;
  T.Free;
  T := nil; // NOHIT
end;

function CtlFind(AFound: Boolean; AThing: TThing): TThing;
begin
  Result := nil; // NOHIT
  if AFound then
    Result := AThing;
end;

function CtlBranch(ACond: Boolean): TThing;
begin
  if ACond then
    Result := TThing.Create
  else
    Result := nil; // NOHIT
end;

procedure CtlInterfaceTyped;
var
  I: IThing;
begin
  I := TThing.Create;
  I := nil; // NOHIT
end;

{ plain classes are object-leak's business, not this rule's }
procedure CtlPlainClass;
var
  P: TPlain;
begin
  P := TPlain.Create;
  P.Value := 1;
  P := nil; // NOHIT
end;

end.