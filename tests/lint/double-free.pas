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
{ B1: a try..EXCEPT whose body frees X exactly ONCE. The try body was emitted
  into the CFG TWICE -- the handler scan accepted any 'statements' child at
  index > 0, and the try body IS the 'statements' child at index 1 -- so the one
  Free was analysed as two on a single path. -> absent }
procedure P7;
var
  X: TFoo;
begin
  X := TFoo.Create;
  try
    X.Free;
  except
    exit;
  end;
end;
{ same, but the handler falls through: the duplication was never conditional on
  the handler diverting, so this shape was equally wrong -> absent }
procedure P8;
var
  X: TFoo;
begin
  X := TFoo.Create;
  try
    X.Free;
  except
    Writeln('boom');
  end;
end;
{ same, reached through an `on E: ... do` handler node rather than a bare
  statements handler -> absent }
procedure P9;
var
  X: TFoo;
begin
  X := TFoo.Create;
  try
    X.Free;
  except
    on E: Exception do exit;
  end;
end;
{ CONTROL: a GENUINE double free INSIDE a try body must still be reported --
  otherwise the fix merely stopped analysing try bodies -> warning }
procedure P10;
var
  X: TFoo;
begin
  X := TFoo.Create;
  try
    X.Free;
    X.Free;
  except
    exit;
  end;
end;
{ CONTROL: freed in the try body and again AFTER the try. The normal-completion
  path runs both, so this is a real double free -> warning }
procedure P11;
var
  X: TFoo;
begin
  X := TFoo.Create;
  try
    X.Free;
  except
    exit;
  end;
  X.Free;
end;
end.
