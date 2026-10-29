unit MixedCaseHex;

interface

implementation

procedure P;
var
  R: Integer;
begin
  WriteLn($AbCd);
  WriteLn($aBCD);
  WriteLn($ABCD);
  WriteLn($abcd);
  WriteLn($1234);
  WriteLn($12ab);
  WriteLn($12AB);
  WriteLn(1234);
end;

end.
