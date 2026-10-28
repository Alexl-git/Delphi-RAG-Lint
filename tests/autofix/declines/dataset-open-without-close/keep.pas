unit keep;
interface
uses
  Data.DB;
implementation
procedure P(Q: TDataSet);
begin
  Q.Open;
  Q.First;
end;
end.
