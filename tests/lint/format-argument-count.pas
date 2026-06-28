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
  V: Integer;
begin
  S := Format('%s = %d', ['x', 42]);
  S := Format('%d%%', [V]);
end;

end.
