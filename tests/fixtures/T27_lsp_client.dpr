program T27_lsp_client;
{$APPTYPE CONSOLE}
uses
  System.SysUtils, System.JSON,
  DragLint.Plugin.LspClient;
var
  Client: TDragLintLspClient;
  Resp: TJSONValue;
begin
  Client := TDragLintLspClient.Create;
  try
    if not Client.Start(ExtractFilePath(ParamStr(0)) + '..\..\third_party\dll\drag-lint.exe') then
    begin
      Writeln('FAIL: could not spawn drag-lint.exe');
      Halt(1);
    end;
    if not Client.Initialize then
    begin
      Writeln('FAIL: initialize did not respond');
      Halt(1);
    end;
    Resp := Client.Request('shutdown', nil, 2000);
    if Resp = nil then
    begin
      Writeln('FAIL: shutdown timed out');
      Halt(1);
    end;
    Resp.Free;
    Client.Notify('exit', nil);
    Client.Stop;
    Writeln('OK');
  finally
    Client.Free;
  end;
end.
