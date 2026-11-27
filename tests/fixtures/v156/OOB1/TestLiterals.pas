unit TestLiterals;

interface

procedure RunTests;

implementation

procedure Show(const S: string);
begin
  Writeln(S);
end;

procedure RunTests;
begin
  Show('Customer_Name');
  Show('Customer_Name');
  Show('Another_Literal_X');
  Show('Another_Literal_X');
  Show('Another_Literal_X');
  Show('Another_Literal_X');
  Show('Another_Literal_X');
  Show('Another_Literal_X');
end;

end.
