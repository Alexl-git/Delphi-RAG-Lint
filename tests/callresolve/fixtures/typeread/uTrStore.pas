unit uTrStore;

{ Fixture for tests\callresolve\run_type_read_bind.ps1 -- the type side. }

interface

type
  TTrStore = class
  public
    constructor Create(const APath: string);
    class function Kind: string;
  end;

  TTrStoreClass = class of TTrStore;

implementation

constructor TTrStore.Create(const APath: string);
begin
  inherited Create;
end;

class function TTrStore.Kind: string;
begin
  Result := 'k';
end;

end.