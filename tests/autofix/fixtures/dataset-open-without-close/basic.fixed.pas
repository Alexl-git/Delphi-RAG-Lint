unit basic;

interface

uses
  Data.DB;

procedure P(ASource: TDataSet);
procedure R;
procedure S(ASource: TDataSet);

implementation

procedure P(ASource: TDataSet);
var
  Q: TDataSet;
begin
  Q := ASource;
  Q.Open;
  try
    Q.First;
    Writeln(Q.RecordCount);
  finally
    Q.Close;
  end;
end;

procedure R;
var
  Q: TDataSet;
begin
  Q := TDataSet.Create(nil);
  Q.Open;
  try
    Q.First;
  finally
    Q.Close;
  end;
  Q.Free;
end;

procedure S(ASource: TDataSet);
var
  Q: TDataSet;
begin
  Q := ASource;
  Q.Open;
  try
    Q.Last;
  finally
    Q.Close;
  end;
  Writeln('done');
end;

end.
