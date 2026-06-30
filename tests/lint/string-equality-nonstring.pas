unit SEQN;

interface

implementation

procedure P(F1, F2: TField; D: TDataSet);
begin
  if F1.AsInteger = F2.AsInteger then WriteLn('1');    // Integer accessor: must NOT fire
  if F1.AsLargeInt = F2.AsLargeInt then WriteLn('2');  // Int64 accessor: must NOT fire
  if D.State = dsInsert then WriteLn('3');             // enum State: must NOT fire
end;

end.
