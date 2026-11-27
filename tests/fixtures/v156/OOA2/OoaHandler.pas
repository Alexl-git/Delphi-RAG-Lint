unit OoaHandler;

interface

uses
  System.SysUtils;

type
  ENeverRaised = class(Exception);
  ERaised = class(Exception);
  EFactoryBuilt = class(Exception);
  EBase = class(Exception);
  EDerived = class(EBase);
  EDeclaredOnly = class(EBase);
  EOther = class(Exception);

procedure Probe;

implementation

function MakeFactory: Exception;
begin
  Result:= EFactoryBuilt.Create('x');
end;

procedure Probe;
begin
  try
    raise ERaised.Create('x');
  except
    on ERaised do ;
    on E: Exception do ;
    on EAbort do ;
  end;
  try
    raise MakeFactory;
  except
    on EFactoryBuilt do ;
  end;
  try
    raise EDerived.Create('x');
  except
    on EBase do ;
  end;
  try
    Abort;
  except
    on ENeverRaised do ;  // FIRE handler-type-never-raised
    on E: EOther do ;  // FIRE handler-type-never-raised
    on EDeclaredOnly do ;  // FIRE handler-type-never-raised
  end;
end;

end.
