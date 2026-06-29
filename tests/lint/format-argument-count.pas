unit FormatArgCount;

interface

implementation

uses System.SysUtils;

procedure Bad;
var
  S: string;
begin
  S := Format('%s = %d', ['only-one']);
  S := Format('%d', [1, 2, 3]);
end;

procedure Good;
var
  S: string;
  V, W, N, A: Integer;
begin
  S := Format('%s = %d', ['x', 42]);
  S := Format('%d%%', [V]);
  S := Format('[%0:s] %1:x (%1:d)', ['m', A]);
  S := Format('%.*f', [N, V]);
  S := Format('%*d', [W, N]);
end;

end.
