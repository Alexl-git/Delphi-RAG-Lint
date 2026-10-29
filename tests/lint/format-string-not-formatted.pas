unit FmtNotFormatted;

interface

implementation

uses SysUtils;

procedure Bad(A: Integer);
var S: string;
begin
  S := Format('hello world', []);           // HIT_A: literal, no specifier, no args
  S := Format('hello world', [A]);          // HIT_B: literal, no specifier, args ignored
  S := WideFormat('plain', []);             // HIT_C: WideFormat too
end;

procedure Good(A: Integer; const AFmt: string);
var S: string;
begin
  S := Format('value %d', [A]);             // NOT_A: has a specifier
  S := Format('100%%', []);                 // NOT_B: escaped percent counts as a format string
  S := Format(AFmt, [A]);                   // NOT_C: format string not a literal
  S := Format('a' + 'b%d', [A]);            // NOT_D: concatenation, not a bare literal (known FP shape: skipped)
  S := Format('%s', ['no percent here']);   // NOT_E: percent is in the format string, not the args
end;

end.
