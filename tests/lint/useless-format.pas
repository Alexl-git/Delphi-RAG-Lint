unit UselessFormat;

interface

uses
  System.SysUtils;

implementation

procedure P(const S: string; N: Integer);
var
  R: string;
begin
  R := Format('%s', [S]);
  R := Format('%s', [UpperCase(S)]);
  R := Format('%s=%s', [S, S]);
  R := Format('%d', [N]);
  R := Format('%s', [S, S]);
  R := Format('x%s', [S]);
  R := S;
end;

end.
