unit doublefree;
interface
type
  TFoo = class
  end;
implementation
{ linear double free: X.Free then X.Free again, no reassignment/nil-ing between
  -> the second Free acts on a dangling pointer -> warning }
procedure P1;
var
  X: TFoo;
begin
  X := TFoo.Create;
  X.Free;
  X.Free;
end;
{ reassigned between the two frees -> absent (X points to a fresh object) }
procedure P2;
var
  X: TFoo;
begin
  X := TFoo.Create;
  X.Free;
  X := TFoo.Create;
  X.Free;
end;
{ FreeAndNil nils X, so the later raw Free is a safe no-op -> absent }
procedure P3;
var
  X: TFoo;
begin
  X := TFoo.Create;
  FreeAndNil(X);
  X.Free;
end;
{ free on ONE if-branch only, then a COMMON free after the if -> the common
  free may act on an already-dangling X (only on the branch that freed it)
  -> info (may-dangling, not must-dangling) }
procedure P4(b: Boolean);
var
  X: TFoo;
begin
  X := TFoo.Create;
  if b then X.Free;
  X.Free;
end;
{ single free guarded by Assigned -> absent (only one Free site) }
procedure P5;
var
  X: TFoo;
begin
  X := TFoo.Create;
  if Assigned(X) then X.Free;
end;
{ single free in a try/finally -> absent (only one Free site) }
procedure P6;
var
  X: TFoo;
begin
  X := TFoo.Create;
  try
    Writeln('using X');
  finally
    X.Free;
  end;
end;
end.
