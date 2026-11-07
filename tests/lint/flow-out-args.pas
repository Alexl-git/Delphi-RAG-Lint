unit flow_out_args;
{ local-only-out-arg and dead-store-before-out-arg, no index: only a bare callee whose signature is in
  this unit has a known mode. Method receivers: tests\autotest\run_flow_out_arg_rules.ps1. }
interface
implementation
procedure GetIt(out V: Integer);
begin
  V := 1;
end;
procedure Touch(var V: Integer);
begin
  Inc(V);
end;
procedure Show(const V: Integer);
begin
end;

procedure OnlyOut;
var
  Dummy: Integer;
begin
  GetIt(Dummy);
end;

procedure OutThenRead;
var
  Value: Integer;
begin
  GetIt(Value);
  Show(Value);
end;

procedure VarIsAUse;
var
  Value: Integer;
begin
  Value := 1;
  Touch(Value);
  Show(Value);
end;

procedure DeadStore;
var
  Value: Integer;
begin
  Value := 1;
  GetIt(Value);
  Show(Value);
end;

procedure ReadBetween;
var
  Value: Integer;
begin
  Value := 1;
  Show(Value);
  GetIt(Value);
  Show(Value);
end;

procedure MaybeRuns(AFlag: Boolean);
var
  Value: Integer;
begin
  Value := 1;
  if AFlag then GetIt(Value);
  Show(Value);
end;
end.