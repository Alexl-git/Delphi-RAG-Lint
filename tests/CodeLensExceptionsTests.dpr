program CodeLensExceptionsTests;
{$APPTYPE CONSOLE}
{ Wave 149 PL item 1: the RAD Studio code lens shows the engine's exception
  title beside the caller count.

  WHAT THIS PINS. draglint/callerCounts (engine 1.49, lane LX) carries
  `exceptions`: an array of (line, title) objects -- the same ExceptionLensTitle the VS Code lens
  shows. The plugin parses it (ParseCallerCountsReply) and renders it after the
  caller and implementor parts (CallerLensLabel), e.g.
  `[1 caller] [raises 2 types, handles 1 type]`.

  THE CONTROLS. A reply WITHOUT `exceptions` (engine <= 1.48) must render
  exactly what it rendered before -- otherwise "the title appears" could be
  satisfied by a parser that invents one. And the end-to-end check goes through
  the real hook path (SetCallerCountsHook + PopulateOnce + GetForLine), so a
  renderer that is correct but never called still fails. }
uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  DragLint.Plugin.CodeLensCache in '..\src\delphi-plugin\DragLint.Plugin.CodeLensCache.pas';

const
  { A routine on line 10 with one caller that raises two types and handles one;
    a routine on line 30 with no caller entry at all that raises one type; an
    interface line 40 with only implementors. }
  REPLY_WITH_EXC =
    '{"jsonrpc":"2.0","id":7,"result":{' +
    '"counts":[{"line":10,"count":1},{"line":20,"count":0}],' +
    '"implementors":[{"line":40,"count":2}],' +
    '"exceptions":[{"line":10,"title":"raises 2 types, handles 1 type"},' +
    '{"line":30,"title":"raises 1 type"},{"line":40,"title":"handles 1 type"}]}}';
  { The same reply from an engine that predates the exceptions key. }
  REPLY_OLD_ENGINE =
    '{"jsonrpc":"2.0","id":7,"result":{' +
    '"counts":[{"line":10,"count":1},{"line":20,"count":0}],' +
    '"implementors":[{"line":40,"count":2}]}}';
  FILE_EXC = 'C:\fixture\Raising.pas';
  FILE_OLD = 'C:\fixture\OldEngine.pas';

var
  GPass, GFail: Integer;
  GReply: string;

procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then begin Inc(GPass); Writeln('PASS  ', AName); end
  else begin Inc(GFail); Writeln('FAIL  ', AName); end;
end;

function IndexOfLine(const ALines: TArray<Integer>; ALine: Integer): Integer;
begin
  Result:= -1;
  for var K:= 0 to High(ALines) do
    if ALines[K] = ALine then Exit(K);
end;

procedure TestLabel;
begin
  Check('label: callers + exceptions',
    CallerLensLabel(1, 0, 'raises 2 types') = '[1 caller] [raises 2 types]');
  Check('label: exceptions only (no caller entry)',
    CallerLensLabel(-1, 0, 'raises 1 type') = '[raises 1 type]');
  Check('label: callers + implementors + exceptions',
    CallerLensLabel(3, 1, 'handles 1 type') = '[3 callers] [1 implementor] [handles 1 type]');
  Check('label control: no exception title = the 1.48 label',
    CallerLensLabel(2, 1, '') = '[2 callers] [1 implementor]');
  Check('label control: zero callers still labelled',
    CallerLensLabel(0, 0, '') = '[0 callers]');
  Check('label control: nothing = empty',
    CallerLensLabel(-1, 0, '') = '');
end;

procedure TestParse;
var
  V: TJSONValue;
  Lines, Counts, Impls: TArray<Integer>;
  Excs: TArray<string>;
  Ok: Boolean;
begin
  V:= TJSONObject.ParseJSONValue(REPLY_WITH_EXC);
  try
    Ok:= ParseCallerCountsReply(V, Lines, Counts, Impls, Excs);
  finally
    V.Free;
  end;
  Check('parse: ok', Ok);
  Check('parse: the four arrays agree in length',
    (Length(Lines) = Length(Counts)) and (Length(Lines) = Length(Impls)) and (Length(Lines) = Length(Excs)));
  var I10:= IndexOfLine(Lines, 10);
  var I30:= IndexOfLine(Lines, 30);
  var I40:= IndexOfLine(Lines, 40);
  Check('parse: title merged onto the caller line',
    (I10 >= 0) and (Excs[I10] = 'raises 2 types, handles 1 type') and (Counts[I10] = 1));
  Check('parse: title-only line appended with no caller label',
    (I30 >= 0) and (Excs[I30] = 'raises 1 type') and (Counts[I30] = -1) and (Impls[I30] = 0));
  Check('parse: title merged onto an implementor-only line',
    (I40 >= 0) and (Excs[I40] = 'handles 1 type') and (Impls[I40] = 2) and (Counts[I40] = -1));
  Check('parse: line without a title gets empty',
    (IndexOfLine(Lines, 20) >= 0) and (Excs[IndexOfLine(Lines, 20)] = ''));

  V:= TJSONObject.ParseJSONValue(REPLY_OLD_ENGINE);
  try
    Ok:= ParseCallerCountsReply(V, Lines, Counts, Impls, Excs);
  finally
    V.Free;
  end;
  Check('parse control: old engine reply is ok', Ok);
  Check('parse control: old engine -> no titles, arrays agree',
    (Length(Excs) = Length(Lines)) and (Length(Lines) = 3) and
    (Excs[0] = '') and (Excs[1] = '') and (Excs[2] = ''));

  V:= TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":7,"result":null}');
  try
    Ok:= ParseCallerCountsReply(V, Lines, Counts, Impls, Excs);
  finally
    V.Free;
  end;
  Check('parse control: no counts = not ok, empty arrays', (not Ok) and (Length(Lines) = 0) and (Length(Excs) = 0));
end;

procedure TestHookPath;
var
  C: TDragLintCodeLensCache;
begin
  { The fake hook answers synchronously with GReply, parsed by the same
    ParseCallerCountsReply the IDE's LSP reply handler calls. }
  SetCallerCountsHook(
    function(const AFilePath: string; const ADone: TCallerCountsDone): Boolean
    var
      V: TJSONValue;
      Lines, Counts, Impls: TArray<Integer>;
      Excs: TArray<string>;
      Ok: Boolean;
    begin
      V:= TJSONObject.ParseJSONValue(GReply);
      try
        Ok:= ParseCallerCountsReply(V, Lines, Counts, Impls, Excs);
      finally
        V.Free;
      end;
      ADone(Ok, Lines, Counts, Impls, Excs);
      Result:= True;
    end);
  C:= TDragLintCodeLensCache.Create(8);
  try
    GReply:= REPLY_WITH_EXC;
    C.PopulateOnce(FILE_EXC, 'engine.exe', 'project.sqlite');
    Check('lens: caller line shows the exception title',
      C.GetForLine(FILE_EXC, 10) = '[1 caller] [raises 2 types, handles 1 type]');
    Check('lens: raising routine without callers shows the title alone',
      C.GetForLine(FILE_EXC, 30) = '[raises 1 type]');
    Check('lens: implementor line keeps its part and gains the title',
      C.GetForLine(FILE_EXC, 40) = '[2 implementors] [handles 1 type]');
    Check('lens: untitled line unchanged', C.GetForLine(FILE_EXC, 20) = '[0 callers]');

    GReply:= REPLY_OLD_ENGINE;
    C.PopulateOnce(FILE_OLD, 'engine.exe', 'project.sqlite');
    Check('lens control: old engine caller line unchanged', C.GetForLine(FILE_OLD, 10) = '[1 caller]');
    Check('lens control: old engine has no line 30 label', C.GetForLine(FILE_OLD, 30) = '');
    Check('lens control: old engine implementor line unchanged', C.GetForLine(FILE_OLD, 40) = '[2 implementors]');
  finally
    C.Free;
    SetCallerCountsHook(nil);
  end;
end;

begin
  try
    TestLabel;
    TestParse;
    TestHookPath;
  except
    on E: Exception do
    begin
      Inc(GFail);
      Writeln('FAIL  raised ', E.ClassName, ': ', E.Message);
    end;
  end;
  Writeln(Format('%d passed, %d failed', [GPass, GFail]));
  if GFail > 0 then ExitCode:= 1;
end.
