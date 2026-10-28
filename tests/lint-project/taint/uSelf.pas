unit uSelf;

interface

procedure RunSelf;
procedure RunArgOne;
procedure CacheKnown;
procedure CacheCustom;

implementation

uses
  Windows, SysUtils;

procedure SpawnSelf(const ACmd: string);
var
  SI: TStartupInfo;
  PI: TProcessInformation;
begin
  CreateProcess(nil, PChar(ACmd), nil, nil, False, 0, nil, nil, SI, PI);
end;

procedure RunSelf;
begin
  SpawnSelf(ParamStr(0) + ' index');
end;

procedure RunArgOne;
begin
  SpawnSelf(ParamStr( 1 ));
end;

procedure CacheKnown;
begin
  DeleteFile(GetEnvironmentVariable('LocalAppData') + '\x.tmp');
end;

procedure CacheCustom;
begin
  DeleteFile(GetEnvironmentVariable('MY_CACHE') + '\x.tmp');
end;

end.