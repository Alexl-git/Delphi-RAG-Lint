unit DRagLint.Lint.QueryRules;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  TreeSitter,
  TreeSitterLib,
  TreeSitter.Query,
  DRagLint.Core.Model;

type
  // A loaded external lint rule expressed as a tree-sitter S-expression query.
  // Sister .json file (same basename) supplies metadata: id, severity, message.
  TQueryRule = class
  strict private
    FQuery: TTSQuery;
    FId: string;
    FSeverity: string;
    FMessage: string;
    FSourcePath: string;
    FWarnCapture: string;
  public
    constructor Create(const ALanguage: PTSLanguage;
      const AQuerySource, AScmPath, AJsonPath: string);
    destructor Destroy; override;
    function Run(const ARootNode: TTSNode; const ASource: TBytes;
      const AFilePath: string): TArray<TLintFinding>;
    property Id: string read FId;
    property Severity: string read FSeverity;
    property Message: string read FMessage;
    property SourcePath: string read FSourcePath;
  end;

  TQueryRuleLoader = class
  public
    // Loads every *.scm under ARulesDir as a TQueryRule, paired with the
    // sibling <basename>.json if present. Skips and warns on compile failures.
    class function LoadAll(const ALanguage: PTSLanguage;
      const ARulesDir: string): TArray<TQueryRule>;
  end;

implementation

function NodeText(const ANode: TTSNode; const ASource: TBytes): string;
var
  StartIdx, EndIdx, Len: Integer;
begin
  Result := '';
  if ANode.IsNull then
    Exit;
  StartIdx := Integer(ANode.StartByte);
  EndIdx := Integer(ANode.EndByte);
  Len := EndIdx - StartIdx;
  if (Len <= 0) or (StartIdx < 0) or (EndIdx > Length(ASource)) then
    Exit;
  Result := TEncoding.UTF8.GetString(ASource, StartIdx, Len);
end;

{ TQueryRule }

constructor TQueryRule.Create(const ALanguage: PTSLanguage;
  const AQuerySource, AScmPath, AJsonPath: string);
var
  ErrOff: UInt32;
  ErrType: TTSQueryError;
  Json: TJSONObject;
  RawJson: string;
begin
  inherited Create;
  FSourcePath := AScmPath;
  FId := TPath.GetFileNameWithoutExtension(AScmPath);
  FSeverity := 'warning';
  FMessage := Format('matched rule "%s"', [FId]);
  FWarnCapture := 'warn';

  if (AJsonPath <> '') and TFile.Exists(AJsonPath) then
  begin
    RawJson := TFile.ReadAllText(AJsonPath, TEncoding.UTF8);
    Json := TJSONObject.ParseJSONValue(RawJson) as TJSONObject;
    if Assigned(Json) then
      try
        if Json.GetValue('id') <> nil then
          FId := Json.GetValue('id').Value;
        if Json.GetValue('severity') <> nil then
          FSeverity := Json.GetValue('severity').Value;
        if Json.GetValue('message') <> nil then
          FMessage := Json.GetValue('message').Value;
        if Json.GetValue('warn_capture') <> nil then
          FWarnCapture := Json.GetValue('warn_capture').Value;
      finally
        Json.Free;
      end;
  end;

  ErrOff := 0;
  ErrType := TSQueryError(0);
  FQuery := TTSQuery.Create(ALanguage, AQuerySource, ErrOff, ErrType);
  if FQuery.Query = nil then
  begin
    raise Exception.CreateFmt(
      'tree-sitter query compile failed: rule "%s" (offset %d, errType %d, ' +
      'source %s)', [FId, ErrOff, Ord(ErrType), AScmPath]);
  end;
end;

destructor TQueryRule.Destroy;
begin
  FQuery.Free;
  inherited;
end;

function TQueryRule.Run(const ARootNode: TTSNode; const ASource: TBytes;
  const AFilePath: string): TArray<TLintFinding>;
var
  Cursor: TTSQueryCursor;
  Match: TTSQueryMatch;
  Captures: TTSQueryCaptureArray;
  CapIdx: UInt32;
  FoundList: TList<TLintFinding>;
  Finding: TLintFinding;
  CapNode: TTSNode;
  CaptureName: string;
  Picked: TTSNode;
  HasWarn, HasFirst: Boolean;
  i: Integer;
begin
  FoundList := TList<TLintFinding>.Create;
  Cursor := TTSQueryCursor.Create;
  try
    Cursor.Execute(FQuery, ARootNode);
    while Cursor.NextMatch(Match) do
    begin
      Captures := Match.CapturesArray;
      // Prefer the capture named @<FWarnCapture>; otherwise pin to the
      // first capture.
      Picked := Default(TTSNode);
      HasWarn := False;
      HasFirst := False;
      for i := 0 to Length(Captures) - 1 do
      begin
        CapIdx := Captures[i].index;
        CaptureName := FQuery.CaptureNameForID(CapIdx);
        CapNode := Captures[i].node;
        if (not HasFirst) then
        begin
          Picked := CapNode;
          HasFirst := True;
        end;
        if SameText(CaptureName, FWarnCapture) then
        begin
          Picked := CapNode;
          HasWarn := True;
          Break;
        end;
      end;
      if not (HasWarn or HasFirst) then
        Continue;

      Finding := Default(TLintFinding);
      Finding.RuleId := FId;
      Finding.Severity := FSeverity;
      Finding.FilePath := AFilePath;
      Finding.Message := FMessage;
      Finding.StartLine := Integer(Picked.StartPoint.row) + 1;
      Finding.StartCol := Integer(Picked.StartPoint.column) + 1;
      Finding.EndLine := Integer(Picked.EndPoint.row) + 1;
      Finding.EndCol := Integer(Picked.EndPoint.column) + 1;
      FoundList.Add(Finding);
    end;
    Result := FoundList.ToArray;
  finally
    Cursor.Free;
    FoundList.Free;
  end;
end;

{ TQueryRuleLoader }

class function TQueryRuleLoader.LoadAll(const ALanguage: PTSLanguage;
  const ARulesDir: string): TArray<TQueryRule>;
var
  Files: TArray<string>;
  ScmPath, JsonPath, Source: string;
  Rule: TQueryRule;
  List: TList<TQueryRule>;
begin
  SetLength(Result, 0);
  if not TDirectory.Exists(ARulesDir) then
    Exit;
  Files := TDirectory.GetFiles(ARulesDir, '*.scm', TSearchOption.soAllDirectories);
  List := TList<TQueryRule>.Create;
  try
    for ScmPath in Files do
    begin
      JsonPath := ChangeFileExt(ScmPath, '.json');
      try
        Source := TFile.ReadAllText(ScmPath, TEncoding.UTF8);
        Rule := TQueryRule.Create(ALanguage, Source, ScmPath, JsonPath);
        List.Add(Rule);
      except
        on E: Exception do
          Writeln(Format('  RULE-LOAD-FAIL %s: %s', [ScmPath, E.Message]));
      end;
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

end.
