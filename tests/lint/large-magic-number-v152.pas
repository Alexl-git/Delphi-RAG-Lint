unit LargeMagicV152;

interface

implementation

procedure P(Q: TObject; X: Integer);
begin
  Q.Length := 50000;
  Q.Interval := 3000;
  Self.Q.Size := 5000000;
  X := 50000;
  X := Q.Count * 3000;
  Q.Interval := X * 3000;
  X := Q.ReadInteger('GENERAL', 'TimeInJobFolder', 1800000);
  X := Q.ReadInt64('GENERAL', 'MaxBytes'    , 5000000);
  X := Q.Lookup('GENERAL', 'TimeInJobFolder', 1800000);
  X := Q.ReadInteger('GENERAL', 'Limit', 3000) * 50000;
end;

end.