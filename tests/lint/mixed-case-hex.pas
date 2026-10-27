unit MixedCaseHex;

interface

implementation

procedure P;
var
  R: Integer;
begin
  R := $AbCd;
  R := $aBCD;
  R := $ABCD;
  R := $abcd;
  R := $1234;
  R := $12ab;
  R := $12AB;
  R := 1234;
end;

end.
