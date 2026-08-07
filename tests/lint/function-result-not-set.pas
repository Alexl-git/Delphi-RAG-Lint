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
end.
