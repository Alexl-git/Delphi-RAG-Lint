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
  GPath := ParamStr(3);
end;

procedure DelPath;
var
  F: TFileStream;
begin
  DeleteFile(GPath);
  F := TFileStream.Create(ExtractFileName(ParamStr(1)), fmOpenRead);
  F.Free;
  F := TFileStream.Create(ParamStr(1), fmOpenRead);
  F.Free;
end;

end.
