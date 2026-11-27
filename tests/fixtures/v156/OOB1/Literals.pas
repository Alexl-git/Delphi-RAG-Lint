unit Literals;

interface

procedure Many;
procedure Few;

implementation

procedure Show(const S: string);
begin
  Writeln(S);
end;

procedure Many;
begin
  Show('Customer_Name');   // FIRE repeated-string-literal
  Show('Customer_Name');
  Show('Customer_Name');
  Show('Customer_Name');
  Show('Customer_Name');
  Show('Short');
  Show('Short');
  Show('Short');
  Show('Short');
  Show('Short');
  Show('Short');
end;

procedure Few;
begin
  Show('Only_Four_Times');
  Show('Only_Four_Times');
  Show('Only_Four_Times');
  Show('Only_Four_Times');
end;

end.
