unit RedundantAssignedFree;

interface

uses System.SysUtils;

implementation

procedure P(Obj: TObject);
begin
  if Assigned(Obj) then Obj.Free;
end;

procedure Q(Obj: TObject);
begin
  if Assigned(Obj) then FreeAndNil(Obj);
end;

procedure R(A, B: TObject);
begin
  if Assigned(A) then B.Free;
end;

end.
