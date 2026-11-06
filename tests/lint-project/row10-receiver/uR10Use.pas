unit uR10Use;

interface

uses
  uR10Base;

type
  TR10User = class
  private
    FQuery : TR10Query;
    FReport: TR10Report;
    FMap   : TDictionary<string, Integer>;
    FConfig: TR10Config;
  public
    procedure Loop;
    procedure Lookup;
  end;

implementation

procedure TR10User.Loop;
var
  Q: TR10Query;
  R: TR10Report;
begin
  while not Q.Eof do
  begin
    Writeln(Q.FieldByName('a').AsString); // ALWAYS-FBN
    Q.Next;
  end;
  while not FQuery.Eof do
  begin
    Writeln(FQuery.FieldByName('a').AsString); // ALWAYS-FBN
    FQuery.Next;
  end;
  while not R.Eof do
  begin
    Writeln(R.FieldByName('a').AsString); // SILENCED-FBN
    R.Next;
  end;
  while not Mystery.Eof do
  begin
    Writeln(Mystery.FieldByName('a').AsString); // ALWAYS-FBN
    Mystery.Next;
  end;
  while not Q.Eof do
  begin
    Writeln(Q.Eof); // CONTROL-FBN
    Q.Next;
  end;
  while not FReport.Eof do
  begin
    Writeln(FReport.FieldByName('a').AsString); // SILENCED-FBN
    FReport.Next;
  end;
end;

procedure TR10User.Lookup;
begin
  if FMap.ContainsKey('k') then // ALWAYS-DDL
    Writeln(FMap['k']);
  if FMap.ContainsKey('k') then // CONTROL-DDL
    Writeln('present');
  if FConfig.ContainsKey('k') then // SILENCED-DDL
    Writeln(FConfig['k']);
end;

end.
