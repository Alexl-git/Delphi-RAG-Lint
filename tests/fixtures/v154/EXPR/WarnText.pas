unit WarnText;

interface

implementation

procedure P;
var
  S: string;
begin
  S := '{$WARNINGS OFF}';
  // {$WARNINGS OFF}
  { {$WARNINGS OFF} is nested in a comment }
  Exit;
end;

end.
