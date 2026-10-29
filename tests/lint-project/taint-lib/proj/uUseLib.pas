unit uUseLib;

interface

uses
  FireDAC.Comp.Client;

procedure ViaTrim;
procedure ViaQuote;
procedure ViaLine;

var
  GDb: TFDConnection;

implementation

uses
  uMiniRtl;

procedure ViaTrim;
begin
  GDb.ExecSQL('select * from T where N = ' + MyTrim(ParamStr(1)));
end;

procedure ViaQuote;
begin
  GDb.ExecSQL('select * from T where N = ' + MyQuote(ParamStr(1)));
end;

procedure ViaLine;
var
  S: string;
begin
  GetLine(S);
  GDb.ExecSQL(S);
end;

end.
