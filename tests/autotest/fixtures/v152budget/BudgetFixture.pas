unit BudgetFixture;

interface

uses
  Vcl.Forms;

procedure Report;
procedure Encrypt;

implementation

procedure Report;
begin
  Writeln('report');
end;

procedure Encrypt;
var
  C: TDCP_rc4;
begin
  C:= nil;
  C.Free;
end;

end.
