unit NullCompare;

interface

implementation

uses
  System.Variants, Data.DB;

procedure Test(AField: TField; V: Variant);
var
  S: string;
begin
  if AField.Value = Null then // MUST-FIRE equal
    S := 'a';
  if V <> Null then // MUST-FIRE not equal
    S := 'b';
  if Null = V then // MUST-FIRE reversed
    S := 'c';
  if VarIsNull(V) then // silent
    S := 'd';
  if AField.IsNull then // silent
    S := 'e';
  V := Null; // assignment: silent
  S := 'x = Null'; // inside a string: silent
  // if V = Null then   comment: silent
end;

end.
