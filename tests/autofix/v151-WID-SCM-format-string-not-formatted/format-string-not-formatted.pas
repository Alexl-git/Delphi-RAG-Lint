unit FormatNotFormattedFix;

interface

function Run(const A: string): string;

implementation

uses System.SysUtils;

function Run(const A: string): string;
begin
  Result := Format('plain text', []);
  Result := Format('with arg', [A]);
  Result := Format('%s', [A]);
end;

end.
