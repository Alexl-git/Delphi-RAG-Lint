unit LabInitSink;

interface

procedure LabInitSinkWrite(const pText: string);
procedure LabInitSinkFlush;

implementation

uses
  LabInitConsumer;

var
  GLines: Integer;

procedure LabInitSinkWrite(const pText: string);
begin
  Inc(GLines);
  Writeln('[init] ', pText);
end;

procedure LabInitSinkFlush;
begin
  LabInitStart;
end;

end.
