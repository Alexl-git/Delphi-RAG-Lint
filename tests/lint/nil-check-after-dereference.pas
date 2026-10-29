unit nil_check_after_dereference;

interface

implementation

uses
  System.SysUtils, System.Classes;

procedure DerefThenAssigned(L: TStringList);
begin
  L.Add('a');
  if Assigned(L) then
    L.Clear;
end;

procedure DerefThenNotNil(L: TStringList);
begin
  L.Clear;
  if L <> nil then
    L.Add('b');
end;

procedure DerefThenIsNil(L: TStringList);
begin
  L.Clear;
  if L = nil then
    Exit;
end;

procedure IndexThenCheck(L: TStringList);
begin
  Writeln(L[0]);
  if not Assigned(L) then
    Exit;
end;

procedure PointerThenCheck(P: PInteger);
begin
  P^ := 1;
  if P = nil then
    Exit;
end;

procedure CheckFirst(L: TStringList);
begin
  if Assigned(L) then
    L.Add('c');
  L.Clear;
end;

procedure ReassignedBetween(L: TStringList);
begin
  L.Clear;
  L := TStringList.Create;
  if Assigned(L) then
    L.Free;
end;

procedure GuardedDeref(L: TStringList);
begin
  if Assigned(L) then
    L.Add('d');
  if Assigned(L) then
    L.Clear;
end;

procedure NestedRoutine(L: TStringList);

  procedure Inner(M: TStringList);
  begin
    if Assigned(M) then
      M.Clear;
  end;

begin
  L.Clear;
  Inner(L);
end;

procedure FreeThenCheck(L: TStringList);
begin
  L.Free;
  if L = nil then
    Exit;
end;

end.
