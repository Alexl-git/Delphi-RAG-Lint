unit DRagLint.LSP.Feature.ExecuteCommand;

{ `workspace/executeCommand` (B6) -- the server side of the commands the
  server's own replies carry. Today one: `draglint.showCallers`, which the
  codeLens of DRagLint.LSP.Feature.CodeLens runs with [uri, line]. It answers
  the call sites behind that lens's count: the same index query and the same
  (file, line) dedup as TLSPServer.ComputeCallerCounts, so the number of rows
  equals the number in the lens title. Registered through the S0 feature
  registry exactly as DRagLint.LSP.Feature.CodeLens is. }

interface

uses
  System.JSON
  , DRagLint.LSP.Context
  ;

type
  /// <summary>Answers `workspace/executeCommand` and advertises
  /// executeCommandProvider = {commands: ['draglint.showCallers']}.</summary>
  /// <remarks>Stateless; registered from this unit's initialization. Lines and
  /// characters are 0-based.</remarks>
  TLspExecuteCommandFeature = class(TLspFeature)
  public
    /// <summary>The one method: `workspace/executeCommand`.</summary>
    /// <returns>['workspace/executeCommand'].</returns>
    class function Methods: TArray<string>; override;
    /// <summary>Adds `executeCommandProvider: {commands: ['draglint.showCallers']}`.</summary>
    /// <param name="ACaps">initialize.result.capabilities under construction.</param>
    class procedure AddCapabilities(ACaps: TJSONObject); override;
    /// <summary>Runs one command. `draglint.showCallers` with arguments
    /// [uri, line0] replies [{uri, line, character}] -- every distinct
    /// (file, line) call site, across every configured store, of the
    /// routine(s) the index declares on that line of that file, ordered by
    /// file then line; a line with no routine answers [].</summary>
    /// <param name="ACtx">The server surface; its store list is copied, never
    /// changed.</param>
    /// <param name="AMethod">Always `workspace/executeCommand`.</param>
    /// <param name="AId">The request id; a notification gets no reply.</param>
    /// <param name="AParams">{command, arguments}.</param>
    /// <remarks>Errors are replies, not exceptions: an unknown command answers
    /// -32601; a missing command, or arguments that are not [string, number],
    /// answer -32602.</remarks>
    procedure Handle(const ACtx: ILspServerContext; const AMethod: string; const AId: TJSONValue; const AParams: TJSONObject); override;
  end;

implementation

uses
  System.SysUtils
  , System.Generics.Collections
  , System.Generics.Defaults
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

const
  EXEC_METHOD      = 'workspace/executeCommand';
  CMD_SHOW_CALLERS = 'draglint.showCallers';
  ERR_METHOD_NOT_FOUND = -32601;
  ERR_INVALID_PARAMS   = -32602;
  SHOW_CALLERS_ARGS    = 2; // [uri, line0]

type
  TSite = record
    Path: string;
    Line, Col: Integer; // 1-based, from the store
  end;

function ShowCallers(const ACtx: ILspServerContext; const APath: string; ALine0: Integer): TJSONArray;
begin
  var Sites: TList<TSite>:= TList<TSite>.Create;
  var Seen: TDictionary<string, Byte>:= TDictionary<string, Byte>.Create;
  try
    // D1: the active context's stores (project DB + platform library), not every startup store
    var Stores: TArray<ISymbolStore>:= Copy(ACtx.StoresForFile(APath));
    for var St: ISymbolStore in Stores do
    begin
      if St = nil then Continue;
      for var Sym: TSymbol in St.FindSymbolsByFile(APath) do
      begin
        if not (Sym.Kind in [skProcedure, skFunction, skMethod, skConstructor, skDestructor]) then Continue;
        if Sym.StartLine <> ALine0 + 1 then Continue;
        { ONE PER CALL SITE: FindCallersByName returns a 'call' AND a
          'member-access' ref for `T.Thrice;` -- the (file, line) key collapses
          them, as ComputeCallerCounts does. }
        for var R: TReference in St.FindCallersByName(Sym.Name) do
        begin
          var S: TSite;
          S.Path:= St.GetFilePath(R.FileId);
          S.Line:= R.StartLine;
          S.Col := R.StartCol;
          if Seen.ContainsKey(LowerCase(S.Path) + ':' + IntToStr(S.Line)) then Continue;
          Seen.Add(LowerCase(S.Path) + ':' + IntToStr(S.Line), 1);
          Sites.Add(S);
        end;
      end;
    end;
    Sites.Sort(TComparer<TSite>.Construct(
      function(const A, B: TSite): Integer
      begin
        Result:= CompareText(A.Path, B.Path);
        if Result = 0 then Result:= A.Line - B.Line;
      end));
    Result:= TJSONArray.Create;
    try
      for var S: TSite in Sites do
      begin
        var Item: TJSONObject:= TJSONObject.Create;
        Result.AddElement(Item);
        Item.AddPair('uri'      , ACtx.FileToUri(S.Path));
        Item.AddPair('line'     , TJSONNumber.Create(S.Line - 1));
        Item.AddPair('character', TJSONNumber.Create(if S.Col > 0 then S.Col - 1 else 0));
      end;
    except
      on Exception do
      begin
        Result.Free;
        raise;
      end;
    end;
  finally
    Seen.Free;
    Sites.Free;
  end;
end;

class function TLspExecuteCommandFeature.Methods: TArray<string>;
begin
  Result:= [EXEC_METHOD];
end;

class procedure TLspExecuteCommandFeature.AddCapabilities(ACaps: TJSONObject);
begin
  var Cmds: TJSONArray:= TJSONArray.Create;
  Cmds.Add(CMD_SHOW_CALLERS);
  var Prov: TJSONObject:= TJSONObject.Create;
  Prov.AddPair('commands', Cmds);
  ACaps.AddPair('executeCommandProvider', Prov);
end;

procedure TLspExecuteCommandFeature.Handle(const ACtx: ILspServerContext; const AMethod: string; const AId: TJSONValue; const AParams: TJSONObject);
begin
  if AId = nil then Exit;
  var Cmd: string:= '';
  if (AParams <> nil) and (AParams.GetValue('command') is TJSONString) then Cmd:= AParams.GetValue('command').Value;
  if Cmd = '' then
  begin
    ACtx.ReplyError(AId, ERR_INVALID_PARAMS, 'executeCommand: missing command');
    Exit;
  end;
  if Cmd <> CMD_SHOW_CALLERS then
  begin
    ACtx.ReplyError(AId, ERR_METHOD_NOT_FOUND, 'unknown command: ' + Cmd);
    Exit;
  end;
  var Args: TJSONArray:= nil;
  if AParams.GetValue('arguments') is TJSONArray then Args:= TJSONArray(AParams.GetValue('arguments'));
  if (Args = nil) or (Args.Count < SHOW_CALLERS_ARGS) or not (Args.Items[0] is TJSONString) or not (Args.Items[1] is TJSONNumber) then
  begin
    ACtx.ReplyError(AId, ERR_INVALID_PARAMS, CMD_SHOW_CALLERS + ': arguments must be [uri, line]');
    Exit;
  end;
  var Path: string:= ACtx.FileFromUri(Args.Items[0].Value);
  ACtx.Reply(AId, ShowCallers(ACtx, Path, TJSONNumber(Args.Items[1]).AsInt));
end;

initialization
  RegisterLspFeature(TLspExecuteCommandFeature);

end.
