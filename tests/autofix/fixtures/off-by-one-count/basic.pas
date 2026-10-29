unit basic;

interface

uses
  System.Generics.Collections;

implementation

procedure P(List: TList<Integer>);
var
  I: Integer;
begin
  for I := 0 to List.Count do
    List[I] := 0;
end;

end.
