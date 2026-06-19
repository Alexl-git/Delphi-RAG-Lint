unit di_edges;

interface

type
  ImcSTATIONS = interface ['{00000000-0000-0000-0000-000000000001}']
    function ID: Integer;
  end;

  IDataService<T> = interface ['{00000000-0000-0000-0000-000000000002}']
    procedure Run;
  end;

  ImcCAUSFAIL = interface ['{00000000-0000-0000-0000-000000000003}']
  end;

  TmcSTATIONS = class(TInterfacedObject, ImcSTATIONS)
    function ID: Integer;
  end;

  TDataService_CAUSFAIL_SERVER = class(TInterfacedObject, IDataService<ImcCAUSFAIL>)
    procedure Run;
  end;

implementation

uses Spring.Container;

function TmcSTATIONS.ID: Integer; begin Result := 0; end;
procedure TDataService_CAUSFAIL_SERVER.Run; begin end;

procedure RegisterAll;
begin
  GlobalContainer.RegisterType<TmcSTATIONS>.Implements<ImcSTATIONS>.AsSingleton;
  GlobalContainer.RegisterType<TDataService_CAUSFAIL_SERVER>
    .Implements<IDataService<ImcCAUSFAIL>>.AsSingletonPerThread;
  GlobalContainer.RegisterType<TmcCAUSFAIL>.Implements<ImcCAUSFAIL>;
  GlobalContainer.RegisterInstance<ImcCAUSFAIL>(nil);
end;

procedure UseIt;
var
  S: ImcSTATIONS;
begin
  S := GlobalContainer.Resolve<ImcSTATIONS>;
  S.ID;
end;

end.
