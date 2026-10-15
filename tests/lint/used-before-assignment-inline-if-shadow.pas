unit UbaInlineIfShadow;

{ used-before-assignment, gap log 2026-10-14 (charts):
  (a) an out param assigned by the CONDITION of an inline-if is not read
      before assignment in its branches;
  (c) a later `var X: T;` declaration is not a read of an earlier inner-block
      `var X := ...` that owns the same name.
  Positive controls keep the rule alive on the same shapes. }

interface

implementation

type
  TRt = record
    Id: Integer;
  end;

function FindRoutine(AFid: Integer; out ARt: TRt): Boolean;
begin
  ARt.Id := AFid;
  Result := AFid > 0;
end;

function ShapeA(AFid: Integer): Integer;
var
  Rt: TRt;
begin
  var Key := if FindRoutine(AFid, Rt) then Rt.Id else -AFid;
  Result := Key;
end;

function ShapeAControl(AFid: Integer): Integer;
var
  Rt: TRt;
begin
  var Key := if AFid > 0 then Rt.Id else -AFid;
  Result := Key;
end;

procedure GetWhy(AFid: Integer; out AWhy: Integer);
begin
  AWhy := AFid;
end;

function ShapeC(AFid: Integer; AFlag: Boolean): Integer;
begin
  Result := 0;
  if AFlag then
  begin
    var Why := AFid + 1;
    if Why = 0 then Exit;
  end;
  var Why: Integer;
  GetWhy(AFid, Why);
  Result := Why;
end;

function ShapeCControl(AFid: Integer; AFlag: Boolean): Integer;
begin
  Result := 0;
  if AFlag then
  begin
    var Why := AFid + 1;
    if Why = 0 then Exit;
  end;
  var Why: Integer;
  Result := Why;
end;

end.