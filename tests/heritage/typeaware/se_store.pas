unit se_store;

// string-equality store-path: an integer '=' must NOT fire (the .scm rule's
// type-blind false positive); a string '=' MUST fire. The precise built-in
// runs only on the store-bearing path.

interface

procedure Test;

implementation

procedure Test;
var
  iA, iB: Integer;
  sA, sB: string;
begin
  if iA = iB then Exit;   // line 18: ordinals -> must NOT fire
  if sA = sB then Exit;   // line 19: strings  -> must fire
end;

end.
