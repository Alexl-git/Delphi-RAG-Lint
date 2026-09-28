unit functionresultnotset;
interface
implementation
function F1: Integer;
begin
end;
function F2(b: Boolean): Integer;
begin
  if b then Result := 1;
end;
function F3: Integer;
begin
  Result := 0;
end;
procedure P;
begin
end;
{ B9: `exit(v)` ASSIGNS Result. F4 sets it on every path -- through two valued
  exits and a final assignment -- so nothing is missing. The check for this
  existed but asked for NodeType 'exprCall' while a CFG block stores the
  STATEMENT node, so it never fired; it was harmless only while exit did not
  divert either, and became three false positives on real code the moment it
  did. }
function F4(b: Boolean; c: Boolean): Integer;
begin
  if b then
    exit(1);
  if c then
    exit(2);
  Result := 3;
end;
{ CONTROL: a BARE `exit;` does NOT assign Result -- it leaves it as it stands --
  so this really can return with Result unset }
function F5(b: Boolean): Integer;
begin
  if b then
    exit;
  Result := 1;
end;
{ D21: a function sets its result through its OWN NAME (`F6 := 1`), the Pascal
  form D12 fixed in purity. TH-4 (2026-09-28): the generic free-function shape
  F<T> had no pin -- F7 sets it through its own name, F8 is the control that
  still fires. }
function F6: Integer;
begin
  F6 := 1;
end;
function F7<T>(const A: T): Integer;
begin
  F7 := 1;
end;
function F8<T>(const A: T): Integer;
begin
end;
end.