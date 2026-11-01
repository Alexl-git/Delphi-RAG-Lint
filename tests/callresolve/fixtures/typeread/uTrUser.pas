unit uTrUser;

{ Fixture for tests\callresolve\run_type_read_bind.ps1 -- the sites. The class
  name in each marked line is a `read` ref the guard expects bound to TTrStore. }

interface

procedure UseStore;

implementation

uses
  uTrStore;

procedure UseStore;
var
  S: TTrStore;
  K: string;
  C: TTrStoreClass;
begin
  S := TTrStore.Create('p');
  K := TTrStore.Kind;
  C := TTrStore;
  K := K + S.ClassName;
  if C = nil then Exit;
end;

end.