unit dep;
interface
procedure OldWay; deprecated 'use NewWay';
procedure OldBare; deprecated;
procedure Fine;
implementation
procedure OldWay;
begin
end;
procedure OldBare;
begin
end;
procedure Fine;
begin
  OldWay();
end;
end.
