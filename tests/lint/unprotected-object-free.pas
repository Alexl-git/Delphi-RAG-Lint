unit FreeChk;

interface

uses System.SysUtils, System.Generics.Collections;

type
  TFoo = class
    FDoc: TObject;
    procedure Load;
  end;

implementation

procedure Bad;
var
  X: TObject;
begin
  X := TObject.Create;
  X.ToString;
  X.Free;
end;

procedure Good;
var
  Y: TObject;
begin
  Y := TObject.Create;
  try
    Y.ToString;
  finally
    Y.Free;
  end;
end;

procedure TFoo.Load;
begin
  FDoc := TObject.Create;
  FDoc.ToString;
  FDoc.Free;
end;

function MakeIt: TObject;
begin
  Result := TObject.Create;
  if Result <> nil then
    Result.Free;
end;

procedure WithExcept;
var
  Z: TObject;
begin
  Z := TObject.Create;
  try
    Z.ToString;
  except
    Z.Free;
    raise;
  end;
end;

{ SLZ-RULE1 2026-11-19: three ownership shapes that are not leaks. }

{ (a) early Free + nil inside a try whose finally owns the object (FormsMap:960). }
function EarlyFree(B: Boolean): string;
var
  Q: TObject;
begin
  Q := TObject.Create;
  try
    if B then
    begin
      Q.Free;
      Q := nil;
      Exit('x');
    end;
  finally
    Q.Free;
  end;
end;

{ (b) conditional ownership transfer: freed only on the branch that does not hand
  it to the container (AstChecks:3122 / 5591). }
procedure Transfer(AList: TList<TObject>; B: Boolean);
var
  M: TObject;
begin
  M := TObject.Create;
  if B then
    AList.Add(M)
  else
    M.Free;
end;

{ (c) Create; Free with nothing between (MigrateDbs:85 exclusive-open probe). }
procedure Probe;
var
  S: TObject;
begin
  S := TObject.Create;
  S.Free;
end;

{ POSITIVE CONTROLS: a conditional Free with no hand-off anywhere, and a Free + nil
  OUTSIDE any try, still fire. }
procedure CondNoTransfer(B: Boolean);
var
  W: TObject;
begin
  W := TObject.Create;
  W.ToString;
  if B then
    W.Free;
end;

procedure FreeNilNoTry;
var
  K: TObject;
begin
  K := TObject.Create;
  K.ToString;
  K.Free;
  K := nil;
end;

end.