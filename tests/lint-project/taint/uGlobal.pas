unit uGlobal;

interface

procedure InitPath;
procedure DelPath;

var
  GPath: string;

implementation

uses
  SysUtils, Classes;

procedure InitPath;
begin
  GPath := GetEnvironmentVariable('APP_PATH');
end;

procedure DelPath;
var
  F: TFileStream;
begin
  DeleteFile(GPath);
  F := TFileStream.Create(ExtractFileName(GetEnvironmentVariable('APP_FILE')), fmOpenRead);
  F.Free;
  F := TFileStream.Create(GetEnvironmentVariable('APP_FILE'), fmOpenRead);
  F.Free;
  F := TFileStream.Create(ParamStr(1), fmOpenRead);
  F.Free;
  F := TFileStream.Create(ExpandFileName(ParamStr(2)), fmOpenRead);
  F.Free;
end;

end.
