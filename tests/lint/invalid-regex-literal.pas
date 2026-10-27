unit InvalidRegexLiteral;

interface

implementation

uses
  System.RegularExpressions;

procedure P(const S, Pat: string);
var
  R: TRegEx;
  B: Boolean;
begin
  R:= TRegEx.Create('([a-z');
  R:= TRegEx.Create('([a-z]+)');
  B:= TRegEx.IsMatch(S, '(unclosed');
  B:= TRegEx.IsMatch(S, '^\d+$');
  B:= TRegEx.IsMatch(S, Pat);
  B:= TRegEx.IsMatch(S, '*bad');
  B:= TRegEx.IsMatch('(not a pattern', '^x');
  S.Replace('(', '');
end;

end.
