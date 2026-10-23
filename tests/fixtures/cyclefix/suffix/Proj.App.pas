unit Proj.App;

interface

function AppId: string;
function Describe: string;

implementation

uses
  SQLite;

function AppId: string;
begin
  Result := 'app';
end;

function Describe: string;
begin
  Result := StorageName;
end;

end.
