unit Proj.Storage.SQLite;

interface

uses
  Proj.App;

function StorageName: string;

implementation

function StorageName: string;
begin
  Result := 'store-' + AppId;
end;

end.
