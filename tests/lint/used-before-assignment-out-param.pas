unit used_before_assignment_out_param;

{ v151 WID-FLOW: used-before-assignment widened to out parameters. An out
  parameter carries no value on entry (for an unmanaged type it holds whatever
  the caller's variable held, which the routine must not rely on). }

interface

type
  TRec = record
    A, B: Integer;
  end;

procedure ReadFirst(out V: Integer);
procedure AssignFirst(out V: Integer);
procedure ManagedOut(out S: string);
procedure MaybeAssigned(AFlag: Boolean; out V: Integer);
procedure FillFirst(out R: TRec);
procedure PassedAsOut(out V: Integer);
procedure VarParamRead(var V: Integer);

implementation

procedure Produce(out AValue: Integer);
begin
  AValue := 1;
end;

procedure ReadFirst(out V: Integer);
begin
  if V > 0 then
    V := 1;
end;

procedure AssignFirst(out V: Integer);
begin
  V := 0;
  if V > 0 then
    V := 1;
end;

procedure ManagedOut(out S: string);
begin
  if S = '' then
    S := 'x';
end;

procedure MaybeAssigned(AFlag: Boolean; out V: Integer);
begin
  if AFlag then
    V := 1;
  if V = 0 then Writeln(0);
end;

procedure FillFirst(out R: TRec);
begin
  FillChar(R, SizeOf(R), 0);
  Writeln(R.A);
end;

procedure PassedAsOut(out V: Integer);
begin
  Produce(V);
  Writeln(V);
end;

procedure VarParamRead(var V: Integer);
begin
  if V > 0 then
    V := 1;
end;

end.
