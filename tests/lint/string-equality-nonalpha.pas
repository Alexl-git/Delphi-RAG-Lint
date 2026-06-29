unit StringEqualityNonAlpha;

// v0.65.x: string-equality-comparison must NOT fire when an operand is a quoted
// literal with no letters ('+', '0', '-.') or a #NN char literal -- case folding
// is irrelevant for those, so suggesting SameText is noise. It MUST still fire
// when the literal has a letter ('abc'), where case genuinely matters.

interface

implementation

uses
  System.SysUtils;

procedure Classify(const SS: string);
begin
  if SS = '+'   then Exit;
  if SS = '0'   then Exit;
  if SS = '-.'  then Exit;
  if SS = #13   then Exit;
  if SS = 'abc' then Exit;
end;

end.
