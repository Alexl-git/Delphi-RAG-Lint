unit uIcmUse;

interface

uses
  uIcmDecl;

procedure Run(AThing: TIcmThing);

implementation

procedure Run(AThing: TIcmThing);
begin
  AThing.dowork; // TRIGGER-LOWER
  AThing.DOWORK; // TRIGGER-UPPER
  AThing.dowork; // CONTROL-SECOND-SAME-SPELLING
  AThing.DoWork; // CONTROL-DECLARED
  if AThing.count > 0 then // TRIGGER-PROPERTY
    globalroutine; // TRIGGER-FUNCTION
end;

end.