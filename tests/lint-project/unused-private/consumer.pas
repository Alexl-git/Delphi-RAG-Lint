unit consumer;

interface

uses helper2;

implementation

uses producer, helper;

procedure ConsumeProducer;
var P: TProducer;
begin
  P := TProducer.Create;
  P.UsedPublicMethod;
  P.Free;
end;

end.
