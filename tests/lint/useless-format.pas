unit UselessFormat;

interface

uses
  System.SysUtils;

implementation

procedure P(const S: string; N: Integer);
var
  R: string;
begin
  WriteLn(Format('%s', [S]));
  WriteLn(Format('%s', [UpperCase(S)]));
  WriteLn(Format('%s=%s', [S, S]));
  WriteLn(Format('%d', [N]));
  WriteLn(Format('%s', [S, S]));
  WriteLn(Format('x%s', [S]));
  WriteLn(S);
end;

end.
