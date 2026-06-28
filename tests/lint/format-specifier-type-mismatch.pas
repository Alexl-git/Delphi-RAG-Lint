unit FormatTypeMismatch;

interface

implementation

uses System.SysUtils;

procedure Bad;
var
  S: string;
begin
  S := Format('%d', ['notanumber']);
  S := Format('%f', ['x']);
end;

procedure Good;
var
  S: string;
  V: Integer;
begin
  S := Format('%d', [42]);
  S := Format('%s', ['text']);
  S := Format('%d', [V]);
end;

end.
