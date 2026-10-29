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
  Q.First;
  Writeln(Q.RecordCount);
end;

procedure R;
var
  Q: TDataSet;
begin
  Q := TDataSet.Create(nil);
  Q.Open;
  Q.First;
  Q.Free;
end;

procedure S(ASource: TDataSet);
var
  Q: TDataSet;
begin
  Q := ASource;
  Q.Open;
  Q.Last;
  Q.Close;
  Writeln('done');
end;

end.
