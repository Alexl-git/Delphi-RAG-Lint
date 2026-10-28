unit LabInitConsumer;

interface

uses
  LabInitSink;

procedure LabInitStart;

implementation

procedure LabInitStart;
begin
  LabInitSinkWrite('consumer started');
end;

initialization
  LabInitStart;

end.
