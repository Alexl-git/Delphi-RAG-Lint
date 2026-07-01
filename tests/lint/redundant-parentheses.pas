unit redparen;
interface
implementation
procedure P(var X: Integer);
begin
  X := (X);          // line 6: redundant parens around a lone term -> fires
  X := ((X + 1));    // line 7: redundant nested parens -> fires (outer only)
  X := (X + 1);      // line 8: parens aid a binary expr -> must NOT fire
  X := X + 1;        // line 9: no parens -> clean
end;
end.
