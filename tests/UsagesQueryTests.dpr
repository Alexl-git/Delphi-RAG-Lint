program UsagesQueryTests;
{$APPTYPE CONSOLE}
{ O-USAGESFORM: the pure half of Find Usages over draglint/usages.

  THE CASES, and what each one would catch being undone:
    1 parameters carry name + width: the server refuses a request without a name.
    2 a usages result comes out as the document the form already parses.
    3 an error reply, a missing result, another shape and nil are NOT usages: a reader
      that answered an empty document would show "(no usages found)" on an older engine.
    4 the DB test: subset yes, a foreign DB no, an empty query no, case and blanks.
    5 with --reply <file>: an envelope a REAL engine sent (run_usages_lsp_transport.ps1).
    6 a request on a stopped / replaced client is orphaned (148 XP3). }
uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  DragLint.Plugin.UsagesQuery in '..\src\delphi-plugin\DragLint.Plugin.UsagesQuery.pas';

var
  GPassed: Integer = 0;
  GFailed: Integer = 0;

procedure Check(const AName: string; AOk: Boolean; const ADetail: string = '');
begin
  if AOk then
  begin
    Inc(GPassed);
    Writeln('  [PASS] ', AName);
  end
  else
  begin
    Inc(GFailed);
    Writeln('  [FAIL] ', AName, ' ', ADetail);
  end;
end;

function Reads(const AEnvelope: string; out AJson: string): Boolean;
var
  V: TJSONValue;
begin
  V:= TJSONObject.ParseJSONValue(AEnvelope);
  try
    Result:= UsagesFromReply(V, AJson);
  finally
    V.Free;
  end;
end;

var
  P   : TJSONObject;
  Json: string;
  GObjA, GObjB: TObject;
begin
  GObjA:= TObject.Create;
  GObjB:= TObject.Create;
  P:= UsagesLspParams('Foo', 'wide');
  try
    Check('1 parameters', P.ToJSON = '{"name":"Foo","width":"wide"}', P.ToJSON);
  finally
    P.Free;
  end;

  Check('2a a usages result is read', Reads('{"jsonrpc":"2.0","id":1,"result":{"name":"Foo","reads":[]}}', Json));
  Check('2b the document is the result object', Json = '{"name":"Foo","reads":[]}', Json);

  Check('3a an error reply is not usages', not Reads('{"id":1,"error":{"code":-32601,"message":"x"}}', Json));
  Check('3b its text is empty', Json = '', Json);
  Check('3c no result', not Reads('{"id":1}', Json));
  Check('3d another shape', not Reads('{"id":1,"result":{"name":"Foo"}}', Json));
  Check('3e a result that is not an object', not Reads('{"id":1,"result":null}', Json));
  Check('3f nil', not UsagesFromReply(nil, Json));

  Check('4a subset', ServerCoversDbs(['C:\a.sqlite'], ['C:\b.sqlite', 'C:\A.SQLITE']));
  Check('4b equal set, blanks skipped', ServerCoversDbs(['', 'C:\a.sqlite', 'C:\b.sqlite'], ['C:\a.sqlite', '', 'C:\b.sqlite']));
  Check('4c a foreign DB', not ServerCoversDbs(['C:\a.sqlite', 'C:\c.sqlite'], ['C:\a.sqlite', 'C:\b.sqlite']));
  Check('4d an empty query', not ServerCoversDbs([], ['C:\a.sqlite']));
  Check('4e only blanks', not ServerCoversDbs([''], ['C:\a.sqlite']));
  Check('4f a server with no DB', not ServerCoversDbs(['C:\a.sqlite'], []));

  (* 6 (148 XP3 item 4c): a request whose client was stopped or replaced gets no callback (LspClient
    CancelAllAsync), so the form must notice and let the CLI answer. 6a is the positive control:
    the live client that was asked is NOT orphaned, or the form would always double-query. *)
  Check('6a the asked client, alive: still waiting', not UsagesRequestOrphaned(7, GObjA, GObjA, True));
  Check('6b another client now: orphaned', UsagesRequestOrphaned(7, GObjA, GObjB, True));
  Check('6c no client now: orphaned', UsagesRequestOrphaned(7, GObjA, nil, False));
  Check('6d the asked client, dead: orphaned', UsagesRequestOrphaned(7, GObjA, GObjA, False));
  Check('6e nothing in flight: never orphaned', not UsagesRequestOrphaned(0, GObjA, GObjB, True));
  if SameText(ParamStr(1), '--reply') then
  begin
    Check('5a a real envelope is read', Reads(TFile.ReadAllText(ParamStr(2), TEncoding.UTF8), Json));
    Check('5b it names the symbol', Pos('"name":"' + ParamStr(3) + '"', Json) > 0, Copy(Json, 1, 120));
  end;

  Writeln(GPassed, ' passed, ', GFailed, ' failed');
  if GFailed > 0 then ExitCode:= 1;
end.