unit uProvider;
interface
procedure OnlyInternal;
procedure UsedElsewhere;
procedure NeverUsed;
procedure InternalDriver;
implementation
procedure OnlyInternal;
begin
end;
procedure UsedElsewhere;
begin
end;
procedure NeverUsed;
begin
end;
procedure InternalDriver;
begin
  OnlyInternal;
end;
end.
