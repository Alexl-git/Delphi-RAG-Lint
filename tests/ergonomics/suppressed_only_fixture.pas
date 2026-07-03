unit suppressed_only_fixture;
interface
implementation

// Trips only 'boolean-flag-parameter' (OFF-by-default). Deliberately minimal
// so no other default-ON rule fires -- proves exit-code-from-survivors:
// a bare run with only suppressed findings must print "0 finding(s)" AND
// exit 0 (see v0.81 review Minor).
procedure DoIt(AFlag: Boolean);
begin
  if AFlag then
    Writeln('a')
  else
    Writeln('b');
end;

end.
