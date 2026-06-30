unit consumer;

interface

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
