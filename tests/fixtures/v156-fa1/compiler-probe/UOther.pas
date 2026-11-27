unit UOther;
interface
procedure OtherPlain;
procedure OtherFail; noreturn;
implementation
uses System.SysUtils;
procedure OtherPlain;
begin
end;
procedure OtherFail;
begin
  raise Exception.Create('o');
end;
end.
