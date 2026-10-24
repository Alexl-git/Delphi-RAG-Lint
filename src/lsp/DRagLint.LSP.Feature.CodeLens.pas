unit DRagLint.LSP.Feature.CodeLens;

{ `textDocument/codeLens` -- one "<n> callers" lens above every routine
  declaration, from the same index counts as draglint/callerCounts
  (ILspServerContext.CallerCounts). The lens runs the client command
  `draglint.showCallers` (implemented by the editor extension, B6) with
  [uri, line]. Registered through the S0 feature registry exactly as
  DRagLint.LSP.Feature.Ping is. }

interface

uses
  System.JSON
  , DRagLint.LSP.Context
  ;

type
  /// <summary>Answers `textDocument/codeLens` with one lens per routine and
  /// advertises codeLensProvider = {resolveProvider: false}.</summary>
  /// <remarks>Stateless; registered from this unit's initialization. Lenses
  /// are complete as sent (no codeLens/resolve). Lines are 0-based.</remarks>
  TLspCodeLensFeature = class(TLspFeature)
  public
    /// <summary>The one method: `textDocument/codeLens`.</summary>
    /// <returns>['textDocument/codeLens'].</returns>
    class function Methods: TArray<string>; override;
    /// <summary>Adds `codeLensProvider: {resolveProvider: false}`.</summary>
    /// <param name="ACaps">initialize.result.capabilities under construction.</param>
    class procedure AddCapabilities(ACaps: TJSONObject); override;
    /// <summary>Replies a CodeLens[]: for each {line, count} of the file's
    /// caller counts, a zero-width range at (line, 0) and the command
    /// `draglint.showCallers` titled '<n> callers' ('1 caller' singular) with
    /// arguments [uri, line]. A file no store knows answers [].</summary>
    /// <param name="ACtx">The server surface.</param>
    /// <param name="AMethod">Always `textDocument/codeLens`.</param>
    /// <param name="AId">The request id; a notification gets no reply.</param>
    /// <param name="AParams">{textDocument:{uri}}; a missing uri answers [].</param>
    procedure Handle(const ACtx: ILspServerContext; const AMethod: string; const AId: TJSONValue; const AParams: TJSONObject); override;
  end;

implementation

uses
  System.SysUtils
  ;

const
  CODELENS_METHOD  = 'textDocument/codeLens';
  CODELENS_COMMAND = 'draglint.showCallers';

function Position(ALine0: Integer): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('line'     , TJSONNumber.Create(ALine0));
  Result.AddPair('character', TJSONNumber.Create(0));
end;

function Title(ACount: Integer): string;
begin
  Result:= ACount.ToString + (if ACount = 1 then ' caller' else ' callers');
end;

function BuildLens(const AUri: string; ALine0, ACount: Integer): TJSONObject;
begin
  Result:= TJSONObject.Create;
  try
    var Rng: TJSONObject:= TJSONObject.Create;
    Result.AddPair('range', Rng);
    Rng.AddPair('start', Position(ALine0));
    Rng.AddPair('end'  , Position(ALine0));
    var Cmd: TJSONObject:= TJSONObject.Create;
    Result.AddPair('command', Cmd);
    Cmd.AddPair('title'  , Title(ACount));
    Cmd.AddPair('command', CODELENS_COMMAND);
    var Args: TJSONArray:= TJSONArray.Create;
    Cmd.AddPair('arguments', Args);
    Args.Add(AUri);
    Args.Add(ALine0);
  except
    on Exception do
    begin
      Result.Free;
      raise;
    end;
  end;
end;

class function TLspCodeLensFeature.Methods: TArray<string>;
begin
  Result:= [CODELENS_METHOD];
end;

class procedure TLspCodeLensFeature.AddCapabilities(ACaps: TJSONObject);
begin
  var Lens: TJSONObject:= TJSONObject.Create;
  Lens.AddPair('resolveProvider', TJSONBool.Create(False));
  ACaps.AddPair('codeLensProvider', Lens);
end;

procedure TLspCodeLensFeature.Handle(const ACtx: ILspServerContext; const AMethod: string; const AId: TJSONValue; const AParams: TJSONObject);
begin
  if AId = nil then Exit;
  var Res: TJSONArray:= TJSONArray.Create;
  try
    var Uri: string:= '';
    var Doc: TJSONObject:= nil;
    if AParams <> nil then Doc:= AParams.GetValue('textDocument') as TJSONObject;
    if (Doc <> nil) and (Doc.GetValue('uri') <> nil) then Uri:= Doc.GetValue('uri').Value;
    var Path: string:= '';
    if Uri <> '' then Path:= ACtx.FileFromUri(Uri);
    if Path <> '' then
    begin
      var Counts: TJSONArray:= ACtx.CallerCounts(Path);
      try
        for var E: TJSONValue in Counts do
          Res.AddElement(BuildLens(Uri, (E as TJSONObject).GetValue<Integer>('line'), (E as TJSONObject).GetValue<Integer>('count')));
      finally
        Counts.Free;
      end;
    end;
  except
    on Exception do
    begin
      Res.Free;
      raise;
    end;
  end;
  ACtx.Reply(AId, Res);
end;

initialization
  RegisterLspFeature(TLspCodeLensFeature);

end.
